#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy :no_extra_logdie_message);
Log::Log4perl->easy_init($WARN);

use Test::More tests => 8;


require '../PidFile.pm';

my $pidfilename = 'test.pid';


my $pidfile = new MMM::Common::PidFile:: $pidfilename;
isa_ok($pidfile, 'MMM::Common::PidFile');

unlink $pidfilename;

ok(!$pidfile->exists(), 'pidfile does not exist');
ok(!$pidfile->is_running(), 'process is not running');
$pidfile->create();
ok($pidfile->exists(), 'pidfile exists after create');
ok($pidfile->is_running(), 'process is running after create');

$pidfile->remove();
ok(!$pidfile->exists(), 'pidfile does not exist after remove');

my $pid = fork();
if ($pid == 0) {
	$pidfile->create();
	exit(0);
}
wait();

ok($pidfile->exists(), 'pidfile exists after fork');
ok(!$pidfile->is_running(), 'process is not running after fork');

# clean up
$pidfile->remove();
