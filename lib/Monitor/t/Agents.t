#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 2;

require '../../Common/Role.pm';
require '../Role.pm';
require '../Agents.pm';
require '../Agent.pm';

use constant MMM_PROTOCOL_VERSION => 1;

my $role1 = new MMM::Monitor::Role:: name	=> 'reader', ip		=> '192.168.0.2';
my $role2 = new MMM::Monitor::Role:: name	=> 'writer', ip		=> '192.168.0.1';
my $role3 = new MMM::Monitor::Role:: name	=> 'reader', ip		=> '192.168.0.3';
my $role4 = new MMM::Monitor::Role:: name	=> 'reader', ip		=> '192.168.0.4';

our $config = {
	monitor => {
		status_path => 'status.tmp'
	},
	host	=> {
		db1 => {},
		db2 => {}
	}
};

my $agents1 = _new_instance MMM::Monitor::Agents;
my $agents2 = _new_instance MMM::Monitor::Agents;

$agents1->{db1} = new MMM::Monitor::Agent (
	host	=> 'db1',
	state	=> 'ONLINE',
	roles	=> [$role1, $role2],
	uptime	=> '0',
	last_uptime	=> '0',
);
$agents1->{db2} = new MMM::Monitor::Agent (
	host	=> 'db2',
	state	=> 'ONLINE',
	roles	=> [$role3, $role4],
	uptime	=> '0',
	last_uptime	=> '0',
);

isa_ok($agents1, 'MMM::Monitor::Agents');

$agents1->save_status();
$agents2->load_status();
#use Data::Dumper;
#print Data::Dumper->Dump([$agents1, $agents2]);
is_deeply($agents1, $agents2);

unlink('status.tmp');
