#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 9;

require '../Role.pm';

my $role1 = new MMM::Agent::Role:: name	=> 'writer', ip		=> '192.168.0.1';
my $role2 = new MMM::Agent::Role:: name	=> 'writer', ip		=> '192.168.0.1';
my $role3 = new MMM::Agent::Role:: name	=> 'writer', ip		=> '192.168.0.2';
my $role4 = new MMM::Agent::Role:: name	=> 'reader', ip		=> '192.168.0.1';

isa_ok($role1, 'MMM::Agent::Role');

# Test comparison operators - positive
ok($role1 == $role2, '"full" equal operator (true)');
ok($role1 != $role3, '"full" not equal operator (true)');
ok($role1 eq $role3, '"name only" equal operator (true)');
ok($role1 ne $role4, '"name only" not equal operator (true)');

ok(!($role1 != $role2), '"full" equal operator (false)');
ok(!($role1 == $role3), '"full" not equal operator (false)');
ok(!($role1 ne $role3), '"name only" equal operator (false)');
ok(!($role1 eq $role4), '"name only" not equal operator (false)');


