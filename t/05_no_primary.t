#!/usr/bin/env perl
use lib::abs 'lib';
use lib::abs '../lib';
use Test::More tests => 9;

my $DB = "/tmp/dbix-basis_test.db";

use_ok('DBIx::Basis::Handle');
ok( DBIx::Basis::Handle->init( { test => ["dbi:SQLite:$DB"] } ), qq{Init DBIx::Basis::Handle} );

use_ok('TestObjectNP');
my $obj_np = TestObjectNP->new({ val1 => 'a1', 'val2' => 'a2', val3 => 'a3' });
$obj_np->insert;
$obj_np    = TestObjectNP->select( { val1 => 'a1' } );
cmp_ok( $obj_np->{val1}, 'eq', 'a1', 'np object val1');
cmp_ok( $obj_np->{val2}, 'eq', 'a2', 'np object val2');
cmp_ok( $obj_np->{val3}, 'eq', 'a3', 'np object val2');

eval {
    $obj_np = TestObjectNP->new({ val1 => 'b1', 'val2' => 'b2', val3 => 'b3' })->insert;
};
ok($@, "Got error from insert");

$obj_np    = TestObjectNP->select( { val1 => 'b1' } );
ok( !$obj_np, 'b1 not inserted' );

$obj_np    = TestObjectNP->select( { val1 => 'a1' } );
$obj_np->{val2} = 'c3';
eval {
    $obj_np->update;
};
ok($@, "Got error from update");
