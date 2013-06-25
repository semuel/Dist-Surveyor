package Dist::Surveyor::Tools;
use strict;
use warnings;

require Exporter;
our @ISA = qw{Exporter};
our @EXPORT = qw{write_fields $distro_key_mod_names};

# for distros with names that don't match the principle module name
# yet the principle module version always matches the distro
# Used for perllocal.pod lookups and for picking 'token packages' for minicpan
# # XXX should be automated lookup rather than hardcoded (else remove perllocal.pod parsing)
our $distro_key_mod_names = {
    'PathTools' => 'File::Spec',
    'Template-Toolkit' => 'Template',
    'TermReadKey' => 'Term::ReadKey',
    'libwww-perl' => 'LWP',
    'ack' => 'App::Ack',
};

sub write_fields {
    my ($releases, $format, $fields, $fh) = @_;

    $format ||= join("\t", ('%s') x @$fields);
    $format .= "\n";

    for my $release_data (@$releases) {
        printf $fh $format, map {
            exists $release_data->{$_} ? $release_data->{$_} : "?$_"
        } @$fields;
    }
}

1;
