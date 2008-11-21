#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
# use Data::Dumper;

use Test::More tests => 1;

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

