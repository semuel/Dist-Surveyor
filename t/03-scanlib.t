use strict;
use warnings;
use Dist::Surveyor;
use FindBin;
use File::Spec;
use Test::More;


my $options = {
    distro_key_mod_names => {},
};
my $libdirs = [ File::Spec->catdir($FindBin::Bin, "scanlib") ];
my @installed_releases = determine_installed_releases($options, $libdirs);
@installed_releases = sort { $a->{name} cmp $b->{name} } @installed_releases;
is_deeply(
    [ 'Dist-Surveyor-0.009', 'Test-Class-0.36', 'Test-Deep-0.084' ], 
    [ map $_->{name}, @installed_releases ],
    "Got all three releases" );
is_deeply(
    ['100.00', '100.00', '2.78'],
    [ map $_->{dist_data}->{percent_installed}, @installed_releases ],
    "Got all three percents correctly" );

done_testing();
