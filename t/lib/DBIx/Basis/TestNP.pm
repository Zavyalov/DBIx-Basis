package DBIx::Basis::TestNP;
use base DBIx::Basis;

__PACKAGE__->db('test');
__PACKAGE__->table('testnp');
__PACKAGE__->definition([
    'val1' => { column => 1 },
    'val2',
    'val3',
]);

1;
