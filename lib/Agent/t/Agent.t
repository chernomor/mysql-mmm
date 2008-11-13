#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
# use Data::Dumper;

use Test::More tests => 5;

require '../Agent.pm';
require '../Role.pm';

my $role1 = new MMM::Agent::Role:: name	=> 'writer', ip		=> '192.168.0.100';
my $role2 = new MMM::Agent::Role:: name	=> 'writer', ip		=> '192.168.0.101';
my $role3 = new MMM::Agent::Role:: name	=> 'reader', ip		=> '192.168.0.100';
my $role4 = new MMM::Agent::Role:: name	=> 'reader', ip		=> '192.168.0.101';
my $agent  = new MMM::Agent
	name		=> 'db1',
	ip			=> '192.168.0.1',
	port		=> 3306,
	user		=> 'mmm_agent',
	password	=> 'MMMAgent',
	roles		=> [new MMM::Agent::Role::(name => 'reader', ip => '192.168.0.101')];

isa_ok($agent, 'MMM::Agent');

# print Data::Dumper->Dump([ $agent, $role1, $role2, $role3, $role4], [qw(agent role1 role2 role3 role4)]);

# Test comparison operators - positive
ok(!$agent->has_role($role1), 'has role (only ip equal)');
ok(!$agent->has_role($role2), 'has role (nothing equal)');
ok(!$agent->has_role($role3), 'has role (only name equal)');
ok($agent->has_role($role4), 'has role (equal)');

