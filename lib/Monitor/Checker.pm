package MMM::Monitor::Checker;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use IPC::Open2;

our $VERSION = '0.01';


sub main($$) {
	my $check_name	= shift;
	my $queue		= shift;

	# Some shortcuts
	my @checks		= keys(%{$main::config->{check}});
	my @hosts		= keys(%{$main::config->{host}});
	my $options		= $main::config->{check}->{$check_name};

	my $max_failures = $options->{trap_period} / $options->{check_period};

	# Create checker
	my $checker = new MMM::Monitor::Checker::($check_name);

	# Initialize failure counters
	my $failures = {};
	foreach my $host_name (@hosts) {
		$failures->{$host_name} = 0;
	}

	my $current_state = -1;

	# Perform checks until shutdown
	while (!$main::shutdown) {
		foreach my $host_name (@hosts) {
			last if ($main::shutdown);

			# Ping checker
			$checker->spawn() unless $checker->ping();

			# Check service ...
			my $res = $checker->check($host_name);

			# If success
			if ($res =~ /^OK/) {
				$failures->{$host_name} = 0;
				next if ($current_state == 1);
				$current_state = 1;
				FATAL "Check '$check_name' on '$host_name' is ok!";
				$queue->enqueue(new MMM::Monitor::CheckResult::($host_name, $check_name, 1));
				next;
			}
			
			# If failed
			if ($res =~ /^ERROR/) {
				if (!$failures->{$host_name}) {
					$failures->{$host_name} = time();
				}
				my $failure_age = time() - $failures->{$host_name};
				
				if ($failure_age >= $max_failures) {
					next if ($current_state == 0);
					$current_state = 0;
					FATAL "Check '$check_name' on '$host_name' has failed for $failure_age seconds!";
					$queue->enqueue(new MMM::Monitor::CheckResult::($host_name, $check_name, 0));
				}
				next;
			}
		}

		sleep($options->{check_period});
	}
	$checker->shutdown();
}


sub new($$) {
	my $class	= shift;
	my $name	= shift;

	my $data = {};

	$data->{name} = $name;
	bless $data, $class; 
	$data->spawn();
	return $data;
}

sub spawn($) {
	my $self	= shift;
	my $name	= $self->{name};

	my $reader;		# STDOUT of checker
	my $writer;		# STDIN  of checker

	INFO "Spawning checker '$name'...";

	# TODO cluster
	my $pid = open2($reader, $writer, "$main::SELF_DIR/bin/monitor/checker $name");
	if (!$pid) {
		LOGDIE "Can't spawn checker! Error: $!";
	}

	$self->{pid}	= $pid;
	$self->{reader}	= $reader;
	$self->{writer}	= $writer;
}

sub shutdown($) {
	my $self	= shift;
	my $name	= $self->{name};

	INFO "Shutting down checker '$name'...";

	my $reader = $self->{reader};
	my $writer = $self->{writer};

	my $send_res = print $writer "quit\n";
	my $recv_res = <$reader>;
	chomp($recv_res) if defined($recv_res);
}

sub ping($) {
	my $self	= shift;
	my $name	= $self->{name};

	TRACE "Pinging checker '$name'...";

	my $reader = $self->{reader};
	my $writer = $self->{writer};
	
	my $send_res = print $writer "ping\n";
	my $recv_res = <$reader>;
	chomp($recv_res) if defined($recv_res);

	if (!$send_res || !$recv_res || !($recv_res =~ /^OK/)) {
		WARN "Checker '$name' is dead!";
		return 0;
	}

	TRACE "Checker '$name' is OK ($recv_res)";
	return 1;
}

sub check($$) {
	my $self	= shift;
	my $host	= shift;

	my $name	= $self->{name};

	my $reader = $self->{reader};
	my $writer = $self->{writer};
	
	my $send_res = print $writer "check $host\n";
	my $recv_res = <$reader>;
	chomp($recv_res) if defined($recv_res);

	return "UNKNOWN: Checker '$name' is dead!" unless ($send_res && $recv_res);
	return $recv_res;
}
