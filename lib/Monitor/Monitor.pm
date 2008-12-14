package MMM::Monitor;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use Thread::Queue;

our $VERSION = '0.01';

use Class::Struct;

sub instance() {
	return $main::monitor;
}

struct 'MMM::Monitor' => {
	agents				=> 'MMM::Monitor::Agents',
	checker_queue		=> 'Thread::Queue',
	checks_status		=> 'MMM::Monitor::ChecksStatus',
	command_queue		=> 'Thread::Queue',
	result_queue		=> 'Thread::Queue',
	roles				=> 'MMM::Monitor::Roles',
	passive				=> '$'
};

sub init($) {
	my $self = shift;
	$self->agents(MMM::Monitor::Agents->instance());
	$self->checker_queue(new Thread::Queue::);
	$self->checks_status(MMM::Monitor::ChecksStatus->instance());
	$self->command_queue(new Thread::Queue::);
	$self->result_queue(new Thread::Queue::);
	$self->roles(MMM::Monitor::Roles->instance());
	$self->passive(0);
}

sub main($) {
	my $self	= shift;

	# Delay execution so we can reap all childs before spawning the checker threads.
	# This prevents a segfault if a SIGCHLD arrives during creation of a thread.
	sleep(3);

	# Spawn checker threads
	my @checks	= keys(%{$main::config->{check}});
	my @threads;

	push(@threads, new threads(\&MMM::Monitor::NetworkChecker::main));
	push(@threads, new threads(\&MMM::Monitor::Commands::main, $self->result_queue, $self->command_queue));

	foreach my $check_name (@checks) {
		push(@threads, new threads(\&MMM::Monitor::Checker::main, $check_name, $self->checker_queue));
	}
	
	while (!$main::shutdown) {
		$self->_process_check_results();
		$self->_check_server_states();
		$self->_handle_commands();
		$self->_distribute_roles();
		sleep(1);
	}

	foreach my $thread (@threads) {
		$thread->join();
	}
}


=item _process_check_results

Process the results of the checker thread and change checks_status accordingly. Reads from check_queue.

=cut

sub _process_check_results($) {
	my $self = shift;

	my $cnt = 0;
	while (my $result = $self->checker_queue->dequeue_nb) {
		$cnt++ if $self->checks_status->handle_result($result);
	}
	return $cnt;
}

sub _check_server_states($) {
	my $self = shift;

	my $checks	= $self->checks_status;
	my $agents	= $self->agents;

	foreach my $host (keys(%{$main::config->{host}})) {
		my $state	= $agents->state($host);

		my $peer	= $main::config->{host}->{$host}->{peer};
		if (!$peer && $main::config->{host}->{$host}->{mode} eq 'slave') {
			$peer	= $self->roles->get_active_master();
		}

		my $peer_state = '';
		$peer_state = $agents->state($peer) if ($peer);

		# Simply skip this host. It is offlined by admin
		next if ($state eq 'ADMIN_OFFLINE');

		if ($state eq 'ONLINE') {

			# ONLINE -> HARD_OFFLINE
			unless ($checks->ping($host) && $checks->mysql($host)) {
				FATAL "State of host '$host' changed from $state to HARD_OFFLINE";
				$agents->set_state($host, 'HARD_OFFLINE');
				# TODO send state to agent
				# clear roles
				$self->send_agent_status($host);
				# TODO kill host (remove ips, drop connections, iptable connections, ...) if sending state was not ok
			}

			# TODO
			# ONLINE -> REPLICATION_FAIL
			# ping mysql !rep_threads UND peer==online -> REPLICATION_FAIL
				FATAL "State of host '$host' changed from $state to REPLICATION_FAIL";
				$agents->set_state($host, 'REPLICATION_FAIL');
				# TODO clear roles
				$self->send_agent_status($host);
			
			# TODO
			# ONLINE -> REPLICATION_DELAY
			# alles ok ausser rep_backlog UND peer==online -> REPLICATION_DELAY
				FATAL "State of host '$host' changed from $state to REPLICATION_DELAY";
				$agents->set_state($host, 'REPLICATION_DELAY');
				# TODO clear roles
				$self->send_agent_status($host);
			next;
		}

		if ($state eq 'AWAITING_RECOVERY') {

			# AWAITING_RECOVERY -> HARD_OFFLINE
			unless ($checks->ping($host) && $checks->mysql($host)) {
				FATAL "State of host '$host' changed from $state to HARD_OFFLINE";
				$agents->set_state($host, 'HARD_OFFLINE');
				# $self->send_agent_status($host); TODO
				next;
			}

			# AWAITING_RECOVERY -> ONLINE (if host was offline for a short period)
			if ($checks->ping($host) && $checks->mysql($host) && $checks->rep_backlog($host) && $checks->rep_threads($host)) {
				# TODO if uptime is small set to online and inform agent. Log fatal
				# WAIT until peer replication is ok if we are a master
				FATAL "State of host '$host' changed from $state to ONLINE";
				$agents->set_state($host, 'ONLINE');
				$self->send_agent_status($host);
				next;
			}
			next;
		}

		if ($state eq 'HARD_OFFLINE') {

			# HARD_OFFLINE -> AWAITING_RECOVERY
			if ($checks->ping($host) && $checks->mysql($host)) {
				FATAL "State of host '$host' changed from $state to AWAITING_RECOVERY";
				$agents->set_state($host, 'AWAITING_RECOVERY');
				$self->send_agent_status($host);
				next;
			}
		}

        # REPLICATION_FAIL -> REPLICATION_DELAY
        # REPLICATION_DELAY -> REPLICATION_FAIL

		if ($state eq 'REPLICATION_DELAY' || $state eq 'REPLICATION_FAIL') {
			# REPLICATION_DELAY || REPLICATION_FAIL -> ONLINE
			if ($checks->ping($host) && $checks->mysql($host)
				&& (($checks->rep_backlog($host) && $checks->rep_threads($host)) || $peer_state ne 'ONLINE')
			) {
				FATAL "State of host '$host' changed from $state to ONLINE";
				$agents->set_state($host, 'ONLINE');
				$self->send_agent_status($host);
				next;
			}

	        # REPLICATION_DELAY || REPLICATION_FAIL -> HARD_OFFLINE
			unless ($checks->ping($host) && $checks->mysql($host)) {
				FATAL "State of host '$host' changed from $state to HARD_OFFLINE";
				$agents->set_state($host, 'HARD_OFFLINE');
				$self->send_agent_status($host);
				# TODO kill host (remove ips, drop connections, iptable connections, ...) if sending state was not ok
			}
		}
	}
}

sub _distribute_roles($) {
	my $self = shift;

	# Never change roles if we are in PASSIVE mode
	return if ($self->passive);

	my $old_active_master = $self->roles->get_active_master();
	
	# Process orphaned roles
	$self->roles->process_orphans();

	# Balance roles
	$self->roles->balance();

	my $new_active_master = $self->roles->get_active_master();

	# notify slaves first, if master host has changed
	unless ($new_active_master eq $old_active_master) {
		$self->notify_slaves($new_active_master);
	}
}

sub notify_slaves($$) {
	my $self		= shift;
	my $new_master	= shift;

	foreach my $host (keys(%{$main::config->{host}})) {
		next unless ($main::config->{host}->{$host}->{mode} eq 'slave');
		$self->send_agent_status($host);
	}
}

sub send_agent_status($$$) {
	my $self	= shift;
	my $host	= shift;
	my $master	= shift;

	# Never send anything to agents if we are in PASSIVE mode
	return if ($self->passive);

	$master = $self->roles->get_active_master() unless (defined($master));

	my @roles		= sort(@{$self->roles->get_host_roles($host)});
	my $agent = $self->agents->get($host);
	$agent->roles(@roles);
	return $agent->cmd_set_status($master);
}

sub _handle_commands($) {
	my $self		= shift;
	while (my $cmdline = $self->command_queue->dequeue_nb) {
		my @args	= split(/\s+/, $cmdline);
		my $command	= shift @args;
		my $arg_cnt	= scalar(@args);
		if    ($command eq 'ping'			&& $arg_cnt == 0) { $self->result_queue->enqueue(MMM::Monitor::Commands::ping       ());                    }
		elsif ($command eq 'show'			&& $arg_cnt == 0) { $self->result_queue->enqueue(MMM::Monitor::Commands::show       ());                    }
		elsif ($command eq 'set_active'		&& $arg_cnt == 0) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_active ());                    }
		elsif ($command eq 'set_passive'	&& $arg_cnt == 0) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_passive());					}
		elsif ($command eq 'move_role'		&& $arg_cnt == 2) { $self->result_queue->enqueue(MMM::Monitor::Commands::move_role  ($args[0], $args[1]));	}
		elsif ($command eq 'set_ip'			&& $arg_cnt == 2) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_ip     ($args[0], $args[1]));	}
		elsif ($command eq 'set_online'		&& $arg_cnt == 1) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_online ($args[0]));            }
		elsif ($command eq 'set_offline'	&& $arg_cnt == 1) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_offline($args[0]));            }
		else { $self->result_queue->enqueue("Invalid command '$cmdline'\n"); }
	}
}

1;

