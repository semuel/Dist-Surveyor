#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use File::Spec;

my @ignored_package = qw{ 
    Data/Dumper 
    Carp 
    JSON/XS 
    LWP 
    Encode/Locale 
    HTTP/Date 
    HTTP/Message 
    URI 
    Cwd
    List/Util
    };

my %handled_packages = (
    map( { $_ => \&pass } qw{ JSON JSON/PP Module/Metadata CPAN/DistnameInfo } ),
    version => \&version,
);

my $filename = shift @ARGV;
open my $fh, "<", $filename or die "can not open $filename";
my @output;

while (my $line = <$fh>) {
    chomp $line;
    my ($module) = $line =~ m!/auto/(\w+(?:/\w+)?)/\.packlist$!;
    warn "Could not process line |$line|"
        unless $module;
    next if grep { $_ eq $module } @ignored_package;
    my $handler = delete $handled_packages{$module}
        or die "I do not know what to do with the |$module| module";
    $line = $handler->($line);
    push @output, $line;

}
close $fh;

if (%handled_packages) {
    die "did not see the following modules: " . join(', ', keys %handled_packages);
}

open  $fh, ">", $filename or die "can not open $filename to write";
print $fh join("\n", @output), "\n";
close $fh;

sub pass {
    my $line = shift;
    return $line;
}

sub version {
    my $line = shift;
    open my $in, "<", $line or die "can not open packlist for version";
    return $line if grep m!/version/vpp\.pm!, <$in>;
    close $in;
    warn "You have the XS of version installed - replacing with stored PP version";
    open my $orig, "<", File::Spec->catfile($FindBin::Bin, qw{ extlib arch auto version .packlist-orig })
        or die "can not open .packlist-orig";
    open my $dest, ">", File::Spec->catfile($FindBin::Bin, qw{ extlib arch auto version .packlist })
        or die "can not open .packlist";
    while (my $path = <$orig>) {
        chomp $path;
        print $dest File::Spec->catdir($FindBin::Bin, $path), "\n";
    }
    close $orig;
    close $dest;
    return File::Spec->catfile($FindBin::Bin, qw{ extlib arch auto version .packlist });
}
