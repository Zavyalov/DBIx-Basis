#!/usr/bin/env perl
use lib::abs 'lib';
use lib::abs '../lib';
use Test::More tests => 9;

my $DB = "/tmp/dbix-basis_test.db";

use_ok('DBIx::Basis::Handle');
use_ok('TestObject');

ok( DBIx::Basis::Handle->init( { test => ["dbi:SQLite:$DB"] } ), qq{Init DBIx::Basis::Handle} );

ok( DBIx::Basis::Handle->otherdb("dbi:SQLite:$DB"), qq{Connect to another database });

my ($one) = TestObject->select({ id => 1 });
ok( defined $one, qq{Retrieve first object });

$one->{value} = 'Thousand';
ok( $one->update(), qq{Update first object });

ok( $one->delete(), qq{Delete first object });

my $two = TestObject->new({ id => 2, value => 'Two' });
ok( $two->insert(), qq{Insert second object });

$two->{value} = 'Million';
ok( $two->replace(), qq{Replace second object });
