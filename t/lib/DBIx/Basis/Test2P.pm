package DBIx::Basis::Test2P;
use base DBIx::Basis;

__PACKAGE__->db('test');
__PACKAGE__->table('test2p');
__PACKAGE__->definition([
    'key1' => { primary => 1 },
    'key2' => { primary => 1 },
    'val1' => { column  => 1 },
    'val2',
]);

1;
