package Dist::Surveyor::DB_File;
{
  $Dist::Surveyor::DB_File::VERSION = '0.005';
}
use base 'DB_File';
use Storable qw(freeze thaw);

# DB_File can store only strings as values, and not Perl structures
# this small wrapper fixes the problem

sub STORE {
    my ($self, $key, $val) = @_;
    $self->SUPER::STORE($key, freeze($val));
}

sub FETCH {
    my ($self, $key) = @_;
    my $val = $self->SUPER::FETCH($key);
    return thaw($val);
}

return 1;
