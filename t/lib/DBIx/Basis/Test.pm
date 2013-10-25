package DBIx::Basis::Test;
use base DBIx::Basis;

__PACKAGE__->db('test');
__PACKAGE__->table('test');
__PACKAGE__->definition([
    'id' => { primary => 1 },
    'value',
    'value2' => { column => 1, default => '' },
    'value3' => { column => 'valueX', default => '' },
]);

sub make_happy {
    return "HAPPYNESS";
}

1;
