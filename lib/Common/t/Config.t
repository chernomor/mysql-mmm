#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy :no_extra_logdie_message);
Log::Log4perl->easy_init($WARN);
#Log::Log4perl->easy_init($TRACE);
#Log::Log4perl->easy_init({ 'level' => $WARN, 'layout' => '%C %p %d %m%n'});

#use Test::More tests => 46;
use Test::More qw(no_plan);
use Test::Output;

die("These tests do not work at the moment. They need to handle the logdie in Config.pm correctly.");

require '../Config.pm';

use Cwd;
use File::Basename;
our $SELF_DIR = dirname(dirname(Cwd::abs_path(__FILE__)));

use Data::Dumper; # XXX

# START UTILITY FUNCTIONS
# test config
sub test_config {
	my $program = shift;
	my $config = new MMM::Common::Config::;
	$config->read('mmm_common_config_test');
#print Data::Dumper->Dump([$config]);
	$config->check($program);
#print Data::Dumper->Dump([$config]);
	return $config;
}

# write config file
sub write_config_file ($$) {
	my $file = shift;
	my $content = shift;
	open (TESTCONF, ">$file") || LOGDIE "Could not open $file";
	print TESTCONF $content;
	close(TESTCONF);
}
# END UTILITY FUNCTIONS

my $config = new MMM::Common::Config::;
isa_ok($config, 'MMM::Common::Config');


my $test_conf = "$SELF_DIR/mmm_common_config_test.conf";
write_config_file($test_conf, '');

#$config->read('mmm_common_config_test');
#$config->check();
#print Data::Dumper->Dump([$config]);
#exit(1);

`touch $SELF_DIR/resolv.conf`;
is($config->_get_filename('mmm_common_config_test'), $test_conf, '_get_filename finds ./mmm_common_config_test.conf');
stderr_like 
	{ is($config->_get_filename('mmm_does_not_exist'), undef, '_get_filename does not find non existing file mmm_does_not_exist.conf'); } 
	qr/mmm_does_not_exist\.conf/, '_get_filename prints a message because it could not find the file';
is($config->_get_filename('resolv'), '/etc/resolv.conf', '_get_filename finds /etc/resolv.conf instead of ./resolv.conf');

###

$MMM::Common::Config::RULESET = { 'required_1_var' => { 'required' => 1 } };
write_config_file($test_conf, '');
stderr_like { test_config(); } qr/required_1_var/, 'Error if required variable is not there';

###

$MMM::Common::Config::RULESET = { 'required_1_var' => { 'required' => 1 } };
write_config_file($test_conf, 'required_1_var some_value');
stderr_like { test_config(); } qr/^\s*$/, 'No error if required variable is there';

###

$MMM::Common::Config::RULESET = { 'required_1_var' => { 'required' => 1 } };
write_config_file($test_conf, '');
stderr_like { test_config('PROG1'); } qr/required_1_var/, 'Error if required variable is not there (with program)';

###

$MMM::Common::Config::RULESET = { 'required_1_var' => { 'required' => 1 } };
write_config_file($test_conf, 'required_1_var some_value');
stderr_like { test_config('PROG1'); } qr/^\s*$/, 'No error if required variable is there (with program)';

###

$MMM::Common::Config::RULESET = { 'required_prog1_var' => { 'required' => [ 'PROG1' ] } };
write_config_file($test_conf, '');
stderr_like { test_config('PROG1'); } qr/required_prog1_var/, 'Error if required variable for specific program is not there';

###

$MMM::Common::Config::RULESET = { 'required_prog1_var' => { 'required' => [ 'PROG1' ] } };
write_config_file($test_conf, 'required_prog1_var some_value');
stderr_like { test_config('PROG1'); } qr/^\s*$/, 'No error if required variable for specific program is there';

###

$MMM::Common::Config::RULESET = { 'required_prog1_var' => { 'required' => [ 'PROG1' ] } };
write_config_file($test_conf, '');
stderr_like { test_config('PROG2'); } qr/^\s*$/, 'No error if required variable for different program is not there';

###

$MMM::Common::Config::RULESET = { 'required_prog1_var' => { 'required' => [ 'PROG1' ] } };
write_config_file($test_conf, '');
stderr_like { test_config(); } qr/required_prog1_var/, 'Error if required variable for any program is not there';

###

$MMM::Common::Config::RULESET = { 'required_prog1_var' => { 'required' => [ 'PROG1' ] } };
write_config_file($test_conf, 'required_prog1_var some_value');
stderr_like { test_config(); } qr/^\s*$/, 'No error if required variable for any program is there';

###

$MMM::Common::Config::RULESET = { 'default_var' => { 'default' => 'mydefault' } };
write_config_file($test_conf, '');
stderr_like 
	{ $config = test_config(); is($config->{default_var}, 'mydefault', 'default value is used if var is not specified'); } 
	qr/^\s*$/, 'No error if variable with default is missing';

###

$MMM::Common::Config::RULESET = { 'default_var' => { 'default' => 'mydefault' } };
write_config_file($test_conf, 'default_var othervalue');
$config = test_config();
is($config->{default_var}, 'othervalue', 'default value is not used if var is specified');

###

$MMM::Common::Config::RULESET = { 'def_req_1_var' => { 'default' => 'mydef', 'required' => '1' } };
write_config_file($test_conf, '');
stderr_like { test_config(); } qr/required/i, 'Error if required variable has a default and is missing';

###

$MMM::Common::Config::RULESET = { 'host' => { 'multiple' => 1, 'section' => { } } };
write_config_file($test_conf, "<host db1/>");
$config = test_config();
is(ref($config->{host}), "HASH", 'named section without variables is recognized as section');

###

$MMM::Common::Config::RULESET = { 'debug' => { 'values' => ['1', '0', 'yes', 'no'] } };
write_config_file($test_conf, 'debug 0');
stderr_like { test_config(); } qr/^\s*$/, 'No error if value of variable is in list';

###

$MMM::Common::Config::RULESET = { 'debug' => { 'values' => ['1', '0', 'yes', 'no'] } };
write_config_file($test_conf, 'debug activated');
stderr_like { test_config(); } qr/activated/, 'Error if value of variable is not in list';

###

$MMM::Common::Config::RULESET = { 'this' => { 'refvalues' => 'host' }, 'host' => { 'multiple' => 1, 'section' => { } } };
write_config_file($test_conf, "this db1\n<host db1/>\n<host db2/>");
stderr_like { test_config(); } qr/^\s*$/, 'No error if value of variable is in referenced list';

###

$MMM::Common::Config::RULESET = { 'this' => { 'refvalues' => 'host' }, 'host' => { 'multiple' => 1, 'section' => { } } };
write_config_file($test_conf, "this db3\n<host db1/>\n<host db2/>");
stderr_like { test_config(); } qr/db3/, 'Error if value of variable is not in referenced list';

###

$MMM::Common::Config::RULESET = { 'host' => { 'multiple' => 1, 'section' => { 'peer' => { 'refvalues' => 'host' } } } };
write_config_file($test_conf, "<host db1/>\n<host db2>\npeer db1\n</host>");
stderr_like { test_config(); } qr/^\s*$/, 'No error if value of variable is in referenced list (self reference)';

###

$MMM::Common::Config::RULESET = { 'check' => { 'multiple' => 1, 'values' => ['ping', 'mysql', 'replication'], 'section' => { } } };
write_config_file($test_conf, "<check replication/>");
stderr_like { test_config(); } qr/^\s*$/, 'No error if name of section is in list';


###

$MMM::Common::Config::RULESET = { 'check' => { 'multiple' => 1, 'values' => ['ping', 'mysql', 'replication'], 'section' => { } } };
write_config_file($test_conf, "<check blood_pressure/>");
stderr_like { test_config(); } qr/blood_pressure/, 'Error if name of section is not in list';

### UNIQUE SECTIONS

$MMM::Common::Config::RULESET = { 'section' => { 'section' => { 'section_var' => { 'required' => 1 } } } };
write_config_file($test_conf, "<section>\nsection_var somevalue\n</section>");
stderr_like { test_config(); } qr/^\s*$/, 'No error if required section variable is there (unique section)';

###

$MMM::Common::Config::RULESET = { 'monitor' => { 'section' => { 'ip' => { 'required' => 1 } } } };
write_config_file($test_conf, "<monitor/>");
stderr_like { test_config(); } qr/required/i, 'Error if required section variable is not there (unique section)';

###
#$config = test_config();
#print Data::Dumper->Dump([$config]);
#exit (1);

$MMM::Common::Config::RULESET = { 'monitor' => { 'section' => { 'port' => { 'default' => '9988' } } } };
write_config_file($test_conf, "<monitor/>");
$config = test_config();
is($config->{monitor}->{port}, '9988', 'default value is used if section var is not specified (unique section)');

###

$MMM::Common::Config::RULESET = { 'monitor' => { 'section' => { 'port' => { 'default' => '9988', 'required' => 1 } } } };
write_config_file($test_conf, "<monitor/>");
stderr_like { test_config(); } qr/default/i, 'Warning if required section variable has a default and is missing';
stderr_like { test_config(); } qr/required/i, 'Error if required section variable has a default and is missing';

###

$MMM::Common::Config::RULESET = { 'section' => { 'section' => { 'section_var' => { 'default' => 'mydefault' } } } };
write_config_file($test_conf, "<section>\nsection_var othervalue\n</section>");
$config = test_config();
is($config->{section}->{section_var}, 'othervalue', 'default value is not used if section var is specified (unique section)');

###

$MMM::Common::Config::RULESET = { 'section' => { 'section' => { 'section_var1' => { 'deprequired' => { 'section_var2' => 'need' } }, 'section_var2' => { } } } };
write_config_file($test_conf, "<section>\nsection_var2 need\n</section>");
stderr_like { test_config(); } qr/required/i, 'Error if deprequired section variable is needed but not specified (unique section)';

###

$MMM::Common::Config::RULESET = { 'section' => { 'section' => { 'section_var1' => { 'deprequired' => { 'section_var2' => 'need' } }, 'section_var2' => { } } } };
write_config_file($test_conf, "<section>\nsection_var2 dont_need</section>");
stderr_like { test_config(); } qr/^\s*$/, 'No error if deprequired section variable is not needed and not specified (unique section)';

### NON UNIQUE SECTIONS

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'section' => { 'section_var' => { 'required' => 1 } } } };
write_config_file($test_conf, "<section name1>\nsection_var somevalue\n</section>");
stderr_like { test_config(); } qr/^\s*$/, 'No error if required section variable is there';

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'section' => { 'section_var' => { 'required' => 1 } } } };
write_config_file($test_conf, "<section name1/>");
stderr_like { test_config(); } qr/section_var/, 'Error if required section variable is not there';

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'section' => { 'section_var' => { 'default' => 'mydefault' } } } };
write_config_file($test_conf, "<section name1/>");
$config = test_config();
is($config->{section}->{name1}->{section_var}, 'mydefault', 'default value is used if section var is not specified');

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'section' => { 'section_var' => { 'default' => 'mydefault' } } } };
write_config_file($test_conf, "<section name1>\nsection_var othervalue\n</section>");
$config = test_config();
is($config->{section}->{name1}->{section_var}, 'othervalue', 'default value is not used if section var is specified');

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'section' => { 'section_var' => { 'default' => 'mydefault', 'required' => 1 } } } };
write_config_file($test_conf, "<section name1/>");
stderr_like { test_config(); } qr/required/i, 'Error if required section variable has a default and is missing';

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'template' => 'default', 'section' => { 'section_var' => { 'default' => 'mydefault' } } } };
write_config_file($test_conf, "<section default>\nsection_var othervalue\n</section>\n<section name1/>");
$config = test_config();
is($config->{section}->{default}, undef, 'template section is undefined');
is($config->{section}->{name1}->{section_var}, 'othervalue', 'default value is not used if section var is specified in template');

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'template' => 'default', 'section' => { 'section_var' => { 'default' => 'mydefault' } } } };
write_config_file($test_conf, "<section default/>\n<section name1/>");
$config = test_config();
is($config->{section}->{name1}->{section_var}, 'mydefault', 'default value is used if section var is not specified in template');

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'template' => 'default', 'section' => { 'section_var' => { 'required' => 1 } } } };
write_config_file($test_conf, "<section default>\nsection_var othervalue\n</section>\n<section name1>");
stderr_like { test_config(); } qr/^\s*$/, 'No Error if required section variable is only specified in template';

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'section' => { 'section_var1' => { 'deprequired' => { 'section_var2' => 'need' } }, 'section_var2' => { } } } };
write_config_file($test_conf, "<section name1>\nsection_var2 need\n</section>");
stderr_like { test_config(); } qr/required/i, 'Error if deprequired section variable is needed but not specified';

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'section' => { 'section_var1' => { 'deprequired' => { 'section_var2' => 'need' } }, 'section_var2' => { } } } };
write_config_file($test_conf, "<section name1>\nsection_var2 dont_need\n</section>");
stderr_like { test_config(); } qr/^\s*$/, 'No error if deprequired section variable is not needed and not specified';

###

$MMM::Common::Config::RULESET = { 'section' => { 'multiple' => 1, 'template' => 'default', 'section' => { 'section_var1' => { 'deprequired' => { 'section_var2' => 'need' } }, 'section_var2' => { } } } };
write_config_file($test_conf, "<section default>\nsection_var2 need\n</section>\n<section name1/>");
stderr_like { test_config(); } qr/required/i, 'Error if deprequired section variable is needed because of template but not specified';

#print Data::Dumper->Dump([$config]);

###

my $data =<< "EOL";
EOL
#$config->read('mmm_common_config_test');
#$config->check('LVMTOOLS');
#$config->check('AGENT');
#$config->check();
#print Data::Dumper->Dump([$MMM::Common::Config::RULESET]);
#print Data::Dumper->Dump([$config]);
#use Data::Dumper;
#print Data::Dumper->Dump([$config]);

# clean up
unlink("$SELF_DIR/resolv.conf");
unlink("$SELF_DIR/mmm_common_config_test.conf");

