package DBIx::Basis::Test;
use base DBIx::Basis;

__PACKAGE__->db('test');
__PACKAGE__->table('test');
__PACKAGE__->definition([
    'id' => { primary => 1 },
    'value',
]);

sub make_happy {
    return "HAPPYNESS";
}

1;
