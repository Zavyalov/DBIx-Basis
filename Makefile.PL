#!/usr/bin/env perl
use inc::Module::Install;

name 'DBIx-Basis';
all_from 'lib/DBIx/Basis.pm';

requires 'DBI';
requires 'JSON';
requires 'lib::abs';
requires 'List::MoreUtils';
requires 'List::Util';
requires 'Module::Find';
requires 'Scalar::Util';
requires 'SQL::Abstract';
requires 'Storable';
requires 'Sub::Name';

recommends 'JSON::XS';
test_requires 'DBD::SQLite';

auto_install;
WriteAll;
