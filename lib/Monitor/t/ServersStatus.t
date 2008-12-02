#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 2;

require '../../Common/Role.pm';
require '../Role.pm';
require '../ServersStatus.pm';

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

my $sstatus1 = _new_instance MMM::Monitor::ServersStatus;
my $sstatus2 = _new_instance MMM::Monitor::ServersStatus;

$sstatus1->{db1} = {
	state	=> 'ONLINE',
	roles	=> [$role1, $role2],
};
$sstatus1->{db2} = {
	state	=> 'ONLINE',
	roles	=> [$role3, $role4],
};

isa_ok($sstatus1, 'MMM::Monitor::ServersStatus');

$sstatus1->save();
$sstatus2->load();
is_deeply($sstatus1, $sstatus2);

unlink('status.tmp');
