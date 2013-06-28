use strict;
use warnings;
use Dist::Surveyor::Inquiry;
use Test::More;

my $module_data = get_module_versions_in_release('SEMUELF', 'Dist-Surveyor-0.009');
my $expected =  {
    'Dist::Surveyor' => {
        'version' => '0.009',
        'name' => 'Dist::Surveyor',
        'path' => 'lib/Dist/Surveyor.pm',
        'size' => 43879
    },
    'Dist::Surveyor::DB_File' => {
        'version' => '0.009',
        'name' => 'Dist::Surveyor::DB_File',
        'path' => 'lib/Dist/Surveyor/DB_File.pm',
        'size' => 676
    }
};
is_deeply($module_data, $expected, "get_module_versions_in_release");

done_testing();
