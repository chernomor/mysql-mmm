#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 14;

require '../../Common/Role.pm';
require '../Role.pm';
require '../Roles.pm';
require '../ServersStatus.pm';

#my $role2 = new MMM::Monitor::Role:: name	=> 'writer', ip		=> '192.168.0.1';
#my $role3 = new MMM::Monitor::Role:: name	=> 'reader', ip		=> '192.168.0.3';
#my $role4 = new MMM::Monitor::Role:: name	=> 'reader', ip		=> '192.168.0.4';

our $config = {
#	monitor => {
#		status_path => 'status.tmp'
#	},
	host	=> {
		db1 => {},
		db2 => {},
		db3 => {}
	},
	active_master_role => 'writer',
	role	=> {
		writer => {
			mode	=> 'exclusive',
			ips		=> ['192.168.0.100'],
			hosts	=> ['db1', 'db2']
		},
		reader => {
			mode	=> 'balanced',
			ips		=> ['192.168.0.1', '192.168.0.2', '192.168.0.3'],
			hosts	=> ['db1', 'db2', 'db3']
		}
	}
};

my $roles = _new_instance MMM::Monitor::Roles;

my $role_writer	= new MMM::Monitor::Role:: name	=> 'writer', ip		=> '192.168.0.100';
my $role_reader1= new MMM::Monitor::Role:: name	=> 'reader', ip		=> '192.168.0.1';
my $role_reader2= new MMM::Monitor::Role:: name	=> 'reader', ip		=> '192.168.0.2';
my $role_reader3= new MMM::Monitor::Role:: name	=> 'reader', ip		=> '192.168.0.3';

isa_ok($roles, 'MMM::Monitor::Roles');

is($roles->get_active_master(), '', 'No active master with no assigned roles');

$roles->assign($role_writer, 'db1');
is($roles->get_active_master(), 'db1', 'Active master after assigning writer role');

$roles->clear_host_roles($roles->get_active_master());
is($roles->get_active_master(), '', 'No active master with active master host cleared');

$roles->assign($role_writer, 'db2');
$roles->assign($role_writer, 'db1');
is($roles->count_host_roles('db1'), 1, 'count host roles (4)');
is($roles->count_host_roles('db2'), 0, 'count host roles (5)');
is_deeply(\[$roles->get_host_roles('db1')], \[$role_writer], 'get host roles (1)');

$roles->assign($role_writer, 'db2');
is($roles->count_host_roles('db1'), 0, 'count host roles (6)');
is($roles->count_host_roles('db2'), 1, 'count host roles (7)');

$roles->assign($role_reader1, 'db2');
$roles->assign($role_reader2, 'db2');
$roles->assign($role_reader3, 'db2');
is($roles->count_host_roles('db2'), 4, 'count host roles (8)');
is_deeply(\[$roles->get_host_roles('db2')], \[$role_reader1, $role_reader2, $role_reader3, $role_writer], 'get host roles (2)');

my $servers_status = MMM::Monitor::ServersStatus->instance();
$servers_status->{db1}->{state} = 'ONLINE';
$servers_status->{db2}->{state} = 'ONLINE';

$roles->balance();

is($roles->count_host_roles('db1'), 2, 'balance roles (role count db1)');
is($roles->count_host_roles('db2'), 2, 'balance roles (role count db2)');

$servers_status->{db2}->{state} = 'HARD_OFFLINE';
$roles->clear_host_roles('db2');
$roles->process_orphans();
is($roles->count_host_roles('db1'), 4, 'process orphans assigns all orphaned roles');

# XXX
#use Data::Dumper;
#print Data::Dumper->Dump([$roles]);




