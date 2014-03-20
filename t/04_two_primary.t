#!/usr/bin/env perl
use lib::abs 'lib';
use lib::abs '../lib';
use Test::More tests => 31;

my $DB = "/tmp/dbix-basis_test.db";

use_ok('DBIx::Basis::Handle');
ok( DBIx::Basis::Handle->init( { test => ["dbi:SQLite:$DB"] } ), qq{Init DBIx::Basis::Handle} );

use_ok('TestObject2P');
my $obj_2p = TestObject2P->new({ key1 => 5, key2 => 8, val1 => 'fib1', 'val2' => 'fib2' });
$obj_2p->insert;
$obj_2p    = TestObject2P->select( { key1 => 5, key2 => 8 } );
cmp_ok( $obj_2p->{key1}, 'eq', '5',    '2p object key1');
cmp_ok( $obj_2p->{key2}, 'eq', '8',    '2p object key2');
cmp_ok( $obj_2p->{val1}, 'eq', 'fib1', '2p object val1');
cmp_ok( $obj_2p->{val2}, 'eq', 'fib2', '2p object val2');

$obj_2p = TestObject2P->new({ key1 => 2, key2 => 3, val1 => 'fib3', val2 => 'fib4' })->insert;
cmp_ok( $obj_2p->{key1}, 'eq', '2',    '2p object key1');
cmp_ok( $obj_2p->{key2}, 'eq', '3',    '2p object key2');
cmp_ok( $obj_2p->{val1}, 'eq', 'fib3', '2p object val1');
cmp_ok( $obj_2p->{val2}, 'eq', 'fib4', '2p object val2');
$obj_2p    = TestObject2P->select( { key1 => 2, key2 => 3 } );
cmp_ok( $obj_2p->{key1}, 'eq', '2',    '2p object key1');
cmp_ok( $obj_2p->{key2}, 'eq', '3',    '2p object key2');
cmp_ok( $obj_2p->{val1}, 'eq', 'fib3', '2p object val1');
cmp_ok( $obj_2p->{val2}, 'eq', 'fib4', '2p object val2');

$obj_2p->{val1} = 'fib5';
$obj_2p->{val2} = 'fib6';
$obj_2p->update;
cmp_ok( $obj_2p->{key1}, 'eq', '2',    '2p object key1');
cmp_ok( $obj_2p->{key2}, 'eq', '3',    '2p object key2');
cmp_ok( $obj_2p->{val1}, 'eq', 'fib5', '2p object val1');
cmp_ok( $obj_2p->{val2}, 'eq', 'fib6', '2p object val2');

$obj_2p    = TestObject2P->select( { key1 => 2, key2 => 3 } );
cmp_ok( $obj_2p->{key1}, 'eq', '2',    '2p object key1');
cmp_ok( $obj_2p->{key2}, 'eq', '3',    '2p object key2');
cmp_ok( $obj_2p->{val1}, 'eq', 'fib5', '2p object val1');
cmp_ok( $obj_2p->{val2}, 'eq', 'fib6', '2p object val2');

$obj_2p->{val1} = 'fib7';
$obj_2p->{val2} = 'fib8';
$obj_2p = $obj_2p->update;
cmp_ok( $obj_2p->{key1}, 'eq', '2',    '2p object key1');
cmp_ok( $obj_2p->{key2}, 'eq', '3',    '2p object key2');
cmp_ok( $obj_2p->{val1}, 'eq', 'fib7', '2p object val1');
cmp_ok( $obj_2p->{val2}, 'eq', 'fib8', '2p object val2');

$obj_2p    = TestObject2P->select( { key1 => 2, key2 => 3 } );
cmp_ok( $obj_2p->{key1}, 'eq', '2',    '2p object key1');
cmp_ok( $obj_2p->{key2}, 'eq', '3',    '2p object key2');
cmp_ok( $obj_2p->{val1}, 'eq', 'fib7', '2p object val1');
cmp_ok( $obj_2p->{val2}, 'eq', 'fib8', '2p object val2');
