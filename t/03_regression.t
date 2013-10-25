#!/usr/bin/env perl
use lib::abs 'lib';
use lib::abs '../lib';
use Test::More tests => 9;

my $DB = "/tmp/dbix-basis_test.db";

use_ok('DBIx::Basis::Handle');
use_ok('TestObject');

ok( DBIx::Basis::Handle->init( { test => ["dbi:SQLite:$DB"] } ), qq{Init DBIx::Basis::Handle} );

my ($obj) = TestObject->select({ id => 2 });
ok( defined $obj, qq{Retrieve object });

$obj->{value2} = 'qweqwe';
$obj->{value3} = 'asdasd';
ok( $obj->update( undef, [ 'valueX' ] ), qq{Partial update object });

my ($obj2) = TestObject->select({ id => 2 });
ok( $obj2, qq{Retrieve partial updated object });
cmp_ok( $obj2->{value2}, 'ne', $obj->{value2}, qq{value3 is different });
cmp_ok( $obj2->{value3}, 'eq', $obj->{value3}, qq{value3 is equal });

eval { $obj->update( undef, [ 'noncolumn' ] ) };
cmp_ok( $@, '=~', qr/^Can't serialize object: column not in the basis/, qq{Non-column update attempt croaks });
