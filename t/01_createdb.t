#!/usr/bin/env perl
use lib::abs 'lib';
use lib::abs '../lib';
use Test::More;

my $DB = "/tmp/dbix-basis_test.db";

ok( 0 == system(qq{sh -c "sqlite3 '$DB' < '} . lib::abs::path('.') . qq{/test.sql'"})>>8, qq{Init "$DB"} );

done_testing();
