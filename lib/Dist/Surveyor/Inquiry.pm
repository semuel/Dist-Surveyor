package Dist::Surveyor::Inquiry;
use strict;
use warnings;
use Memoize; # core
use FindBin;
use Fcntl qw(:DEFAULT :flock); # core
use Dist::Surveyor::DB_File; # internal
use LWP::UserAgent;
use JSON;

# We have to limit the number of results when using MetaCPAN::API.
# We can'r make it too large as it hurts the server (it preallocates)
# but need to make it large enough for worst case distros (eg eBay-API).
# TODO: switching to the ElasticSearch module, with cursor support, will
# probably avoid the need for this. Else we could dynamically adjust.
our $metacpan_size = 2500;
our $metacpan_calls = 0;

our ($DEBUG, $VERBOSE);
*DEBUG = \$::DEBUG;
*VERBOSE = \$::VERBOSE;

my $ua = LWP::UserAgent->new( agent => $0, timeout => 10 );

require Exporter;
our @ISA = qw{Exporter};
our @EXPORT = qw{
    get_candidate_cpan_dist_releases
    get_candidate_cpan_dist_releases_fallback
    get_module_versions_in_release
    get_release_info
};

# caching via persistent memoize

my %memoize_cache;
my $locking_file;

sub perma_cache {
    my $class = shift;
    my $db_generation = 2; # XXX increment on incompatible change
    my $pname = $FindBin::Script;
    $pname =~ s/\..*$//;
    my $memoize_file = "$pname-$db_generation.db";
    open $locking_file, ">", "$memoize_file.lock" 
        or die "Unable to open lock file: $!";
    flock ($locking_file, LOCK_EX) || die "flock: $!";
    tie %memoize_cache => 'Dist::Surveyor::DB_File', $memoize_file, O_CREAT|O_RDWR, 0640
        or die "Unable to use persistent cache: $!";
}

my @memoize_subs = qw(
    get_candidate_cpan_dist_releases
    get_candidate_cpan_dist_releases_fallback
    get_module_versions_in_release
    get_release_info
);
for my $subname (@memoize_subs) {
    my %memoize_args = (
        SCALAR_CACHE => [ HASH => \%memoize_cache ],
        LIST_CACHE   => 'FAULT',
    );
    memoize($subname, %memoize_args);
}

sub get_release_info {
    my ($author, $release) = @_;
    $metacpan_calls++;
    my $response = $ua->get("http://api.metacpan.org/v0/release/$author/$release");
    die $response->status_line unless $response->is_success;
    my $release_data = decode_json $response->decoded_content;
    if (!$release_data) {
        warn "Can't find release details for $author/$release - SKIPPED!\n";
        return; # XXX could fake some of $release_data instead
    }
    return $release_data;
}

sub get_candidate_cpan_dist_releases {
    my ($module, $version, $file_size) = @_;

    $version = 0 if not defined $version; # XXX

    # timbunce: So, the current situation is that: version_numified is a float
    # holding version->parse($raw_version)->numify, and version is a string
    # also holding version->parse($raw_version)->numify at the moment, and
    # that'll change to ->stringify at some point. Is that right now? 
    # mo: yes, I already patched the indexer, so new releases are already
    # indexed ok, but for older ones I need to reindex cpan
    my $v = (ref $version && $version->isa('version')) ? $version : version->parse($version);
    my %v = map { $_ => 1 } "$version", $v->stringify, $v->numify;
    my @version_qual;
    push @version_qual, { term => { "file.module.version" => $_ } }
        for keys %v;
    push @version_qual, { term => { "file.module.version_numified" => $_ }}
        for grep { looks_like_number($_) } keys %v;

    my @and_quals = (
        {"term" => {"file.module.name" => $module }},
        (@version_qual > 1 ? { "or" => \@version_qual } : $version_qual[0]),
    );
    push @and_quals, {"term" => {"file.stat.size" => $file_size }}
        if $file_size;

    # XXX doesn't cope with odd cases like 
    # http://explorer.metacpan.org/?url=/module/MLEHMANN/common-sense-3.4/sense.pm.PL
    $metacpan_calls++;

    my $query = {
        "size" => $metacpan_size,
        "query" =>  { "filtered" => {
            "filter" => {"and" => \@and_quals },
            "query" => {"match_all" => {}},
        }},
        "fields" => [qw(
            release _parent author version version_numified file.module.version 
            file.module.version_numified date stat.mtime distribution file.path
            )]
    };
    my $response = $ua->post(
        'http://api.metacpan.org/v0/file',
        Content_Type => 'application/json',
        Content => to_json( $query, { canonical => 1 } ),
    );
    die $response->status_line unless $response->is_success;
    my $results = decode_json $response->decoded_content;

    my $hits = $results->{hits}{hits};
    die "get_candidate_cpan_dist_releases($module, $version, $file_size): too many results (>$metacpan_size)"
        if @$hits >= $metacpan_size;
    warn "get_candidate_cpan_dist_releases($module, $version, $file_size): ".Dumper($results)
        if grep { not $_->{fields}{release} } @$hits; # XXX temp, seen once but not since

    # filter out perl-like releases
    @$hits = 
        grep { $_->{fields}{path} !~ m!^(?:t|xt|tests?|inc|samples?|ex|examples?|bak|local-lib)\b! }
        grep { $_->{fields}{release} !~ /^(perl|ponie|parrot|kurila|SiePerl-)/ } 
        @$hits;

    for my $hit (@$hits) {
        $hit->{release_id} = delete $hit->{_parent};
        # add version_obj for convenience (will fail and be undef for releases like "0.08124-TRIAL")
        $hit->{fields}{version_obj} = eval { version->parse($hit->{fields}{version}) };
    }

    # we'll return { "Dist-Name-Version" => { details }, ... }
    my %dists = map { $_->{fields}{release} => $_->{fields} } @$hits;
    warn "get_candidate_cpan_dist_releases($module, $version, $file_size): @{[ sort keys %dists ]}\n"
        if $VERBOSE;

    return \%dists;
}

sub get_candidate_cpan_dist_releases_fallback {
    my ($module, $version) = @_;

    # fallback to look for distro of the same name as the module
    # for odd cases like
    # http://explorer.metacpan.org/?url=/module/MLEHMANN/common-sense-3.4/sense.pm.PL
    (my $distname = $module) =~ s/::/-/g;

    # timbunce: So, the current situation is that: version_numified is a float
    # holding version->parse($raw_version)->numify, and version is a string
    # also holding version->parse($raw_version)->numify at the moment, and
    # that'll change to ->stringify at some point. Is that right now? 
    # mo: yes, I already patched the indexer, so new releases are already
    # indexed ok, but for older ones I need to reindex cpan
    my $v = (ref $version && $version->isa('version')) ? $version : version->parse($version);
    my %v = map { $_ => 1 } "$version", $v->stringify, $v->numify;
    my @version_qual;
    push @version_qual, { term => { "version" => $_ } }
        for keys %v;
    push @version_qual, { term => { "version_numified" => $_ }}
        for grep { looks_like_number($_) } keys %v;

    my @and_quals = (
        {"term" => {"distribution" => $distname }},
        (@version_qual > 1 ? { "or" => \@version_qual } : $version_qual[0]),
    );

    # XXX doesn't cope with odd cases like 
    $metacpan_calls++;
    my $query = {
        "size" => $metacpan_size,
        "query" =>  { "filtered" => {
            "filter" => {"and" => \@and_quals },
            "query" => {"match_all" => {}},
        }},
        "fields" => [qw(
            release _parent author version version_numified file.module.version 
            file.module.version_numified date stat.mtime distribution file.path)]
    };
    my $response = $ua->post(
        'http://api.metacpan.org/v0/file',
        Content_Type => 'application/json',
        Content => to_json( $query, { canonical => 1 } ),
    );
    die $response->status_line unless $response->is_success;
    my $results = decode_json $response->decoded_content;

    my $hits = $results->{hits}{hits};
    die "get_candidate_cpan_dist_releases_fallback($module, $version): too many results (>$metacpan_size)"
        if @$hits >= $metacpan_size;
    warn "get_candidate_cpan_dist_releases_fallback($module, $version): ".Dumper($results)
        if grep { not $_->{fields}{release} } @$hits; # XXX temp, seen once but not since

    # filter out perl-like releases
    @$hits = 
        grep { $_->{fields}{path} !~ m!^(?:t|xt|tests?|inc|samples?|ex|examples?|bak|local-lib)\b! }
        grep { $_->{fields}{release} !~ /^(perl|ponie|parrot|kurila|SiePerl-)/ } 
        @$hits;

    for my $hit (@$hits) {
        $hit->{release_id} = delete $hit->{_parent};
        # add version_obj for convenience (will fail and be undef for releases like "0.08124-TRIAL")
        $hit->{fields}{version_obj} = eval { version->parse($hit->{fields}{version}) };
    }

    # we'll return { "Dist-Name-Version" => { details }, ... }
    my %dists = map { $_->{fields}{release} => $_->{fields} } @$hits;
    warn "get_candidate_cpan_dist_releases_fallback($module, $version): @{[ sort keys %dists ]}\n"
        if $VERBOSE;

    return \%dists;
}

# this can be called for all sorts of releases that are only vague possibilities
# and aren't actually installed, so generally it's quiet
sub get_module_versions_in_release {
    my ($author, $release) = @_;

    $metacpan_calls++;
    my $results = eval { 
        my $query = {
            "size" => $metacpan_size,
            "query" =>  { "filtered" => {
                "filter" => {"and" => [
                    {"term" => {"release" => $release }},
                    {"term" => {"author" => $author }},
                    {"term" => {"mime" => "text/x-script.perl-module"}},
                ]},
                "query" => {"match_all" => {}},
            }},
            "fields" => ["path","name","_source.module", "_source.stat.size"],
        }; 
        my $response = $ua->post(
            'http://api.metacpan.org/v0/file',
            Content_Type => 'application/json',
            Content => to_json( $query, { canonical => 1 } ),
        );
        die $response->status_line unless $response->is_success;
        decode_json $response->decoded_content;
    };
    if (not $results) {
        warn "Failed get_module_versions_in_release for $author/$release: $@";
        return {};
    }
    my $hits = $results->{hits}{hits};
    die "get_module_versions_in_release($author, $release): too many results"
        if @$hits >= $metacpan_size;

    my %modules_in_release;
    for my $hit (@$hits) {
        my $path = $hit->{fields}{path};

        # XXX try to ignore files that won't get installed
        # XXX should use META noindex!
        if ($path =~ m!^(?:t|xt|tests?|inc|samples?|ex|examples?|bak|local-lib)\b!) {
            warn "$author/$release: ignored non-installed module $path\n"
                if $DEBUG;
            next;
        }

        my $size = $hit->{fields}{"_source.stat.size"};
        # files can contain more than one package ('module')
        my $rel_mods = $hit->{fields}{"_source.module"} || [];
        for my $mod (@$rel_mods) { # actually packages in the file

            # Some files may contain multiple packages. We want to ignore
            # all except the one that matches the name of the file.
            # We use a fairly loose (but still very effective) test because we
            # can't rely on $path including the full package name.
            (my $filebasename = $hit->{fields}{name}) =~ s/\.pm$//;
            if ($mod->{name} !~ m/\b$filebasename$/) {
                warn "$author/$release: ignored $mod->{name} in $path\n"
                    if $DEBUG;
                next;
            }

            # warn if package previously seen in this release
            # with a different version or file size
            if (my $prev = $modules_in_release{$mod->{name}}) {
                my $version_obj = eval { version->parse($mod->{version}) };
                die "$author/$release: $mod $mod->{version}: $@" if $@;

                if ($VERBOSE) {
                    # XXX could add a show-only-once cache here
                    my $msg = "$mod->{name} $mod->{version} ($size) seen in $path after $prev->{path} $prev->{version} ($prev->{size})";
                    warn "$release: $msg\n"
                        if ($version_obj != version->parse($prev->{version}) or $size != $prev->{size});
                }
            }

            # keep result small as Storable thawing this is major runtime cost
            # (specifically we avoid storing a version_obj here)
            $modules_in_release{$mod->{name}} = {
                name => $mod->{name},
                path => $path,
                version => $mod->{version},
                size => $size,
            };
        }
    }

    warn "\n$author/$release contains: @{[ map { qq($_->{name} $_->{version}) } values %modules_in_release ]}\n"
        if $DEBUG;

    return \%modules_in_release;
}

1;
