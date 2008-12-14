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

	# Go into passive mode if we have no network connection at startup
	$self->passive(!$main::have_net);
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
		$self->send_status_to_agents();
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

	# Don't do anything if we have no network connection
	return if (!$main::have_net);

	my $checks	= $self->checks_status;
	my $agents	= $self->agents;

	foreach my $host (keys(%{$main::config->{host}})) {
		my $agent		= $agents->get($host);
		my $state		= $agent->state;
		my $ping		= $checks->ping($host);
		my $mysql		= $checks->mysql($host);
		my $rep_backlog	= $checks->rep_backlog($host);
		my $rep_threads	= $checks->rep_threads($host);

		my $peer	= $main::config->{host}->{$host}->{peer};
		if (!$peer && $agent->mode eq 'slave') {
			$peer	= $self->roles->get_active_master();
		}

		my $peer_state = '';
		$peer_state = $agents->state($peer) if ($peer);

		# Simply skip this host. It is offlined by admin
		next if ($state eq 'ADMIN_OFFLINE');

		########################################################################

		if ($state eq 'ONLINE') {

			# ONLINE -> HARD_OFFLINE
			unless ($ping && $mysql) {
				FATAL "State of host '$host' changed from $state to HARD_OFFLINE";
				$agent->state('HARD_OFFLINE');
				$self->roles->clear_host_roles($host);
				$self->send_agent_status($host);
				# TODO kill host (remove ips, drop connections, iptable connections, ...) if sending state was not ok
				next;
			}

			# ONLINE -> REPLICATION_FAIL
			if ($ping && $mysql && !$rep_threads && $peer_state eq 'ONLINE') {
				FATAL "State of host '$host' changed from $state to REPLICATION_FAIL";
				$agent->state('REPLICATION_FAIL');
				$self->roles->clear_host_roles($host);
				$self->send_agent_status($host);
				next;
			}

			# ONLINE -> REPLICATION_DELAY
			if ($ping && $mysql && !$rep_backlog && $rep_threads && $peer_state eq 'ONLINE') {
				FATAL "State of host '$host' changed from $state to REPLICATION_DELAY";
				$agent->state('REPLICATION_DELAY');
				$self->roles->clear_host_roles($host);
				$self->send_agent_status($host);
				next;
			}
			next;
		}

		########################################################################

		if ($state eq 'AWAITING_RECOVERY') {

			# AWAITING_RECOVERY -> HARD_OFFLINE
			unless ($ping && $mysql) {
				FATAL "State of host '$host' changed from $state to HARD_OFFLINE";
				$agent->state('HARD_OFFLINE');
				next;
			}

			# AWAITING_RECOVERY -> ONLINE (if host was offline for a short period)
			if ($ping && $mysql && $rep_backlog && $rep_threads) {
				my $uptime_diff = $agent->uptime - $agent->last_uptime;
				next unless ($host->{last_uptime} > 0 && $uptime_diff > 0 && $uptime_diff < 60);
				next unless ($agent->mode eq 'master' && $peer_state eq 'ONLINE' && $checks->rep_backlog($peer) && $checks->rep_threads($peer));
				FATAL "State of host '$host' changed from $state to ONLINE";
				$agent->state('ONLINE');
				$self->send_agent_status($host);
				next;
			}
			next;
		}

		########################################################################

		if ($state eq 'HARD_OFFLINE') {

			# HARD_OFFLINE -> AWAITING_RECOVERY
			if ($ping && $mysql) {
				FATAL "State of host '$host' changed from $state to AWAITING_RECOVERY";
				$agent->state('AWAITING_RECOVERY');
				$self->send_agent_status($host);
				next;
			}
		}

		########################################################################

		if ($state eq 'REPLICATION_FAIL') {
        	# REPLICATION_FAIL -> REPLICATION_DELAY
			if ($ping && $mysql && !$rep_backlog && $rep_threads) {
				FATAL "State of host '$host' changed from $state to REPLICATION_DELAY";
				$agent->state('REPLICATION_DELAY');
				next;
			}
		}
		if ($state eq 'REPLICATION_DELAY') {
	        # REPLICATION_DELAY -> REPLICATION_FAIL
			if ($ping && $mysql && $rep_backlog && !$rep_threads) {
				FATAL "State of host '$host' changed from $state to REPLICATION_FAIL";
				$agent->state('REPLICATION_FAIL');
				next;
			}
		}

		########################################################################

		if ($state eq 'REPLICATION_DELAY' || $state eq 'REPLICATION_FAIL') {
			# REPLICATION_DELAY || REPLICATION_FAIL -> ONLINE
			if ($ping && $mysql && (($rep_backlog && $rep_threads) || $peer_state ne 'ONLINE')
			) {
				FATAL "State of host '$host' changed from $state to ONLINE";
				$agent->state('ONLINE');
				$self->send_agent_status($host);
				next;
			}

	        # REPLICATION_DELAY || REPLICATION_FAIL -> HARD_OFFLINE
			unless ($ping && $mysql) {
				FATAL "State of host '$host' changed from $state to HARD_OFFLINE";
				$agent->state('HARD_OFFLINE');
				$self->send_agent_status($host);
				# TODO kill host (remove ips, drop connections, iptable connections, ...) if sending state was not ok
				next;
			}
			next;
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

sub send_status_to_agents($) {
	my $self	= shift;
	my $master	= $self->roles->get_active_master();
	foreach my $host (keys(%{$main::config->{host}})) {
		$self->send_agent_status($host, $master);
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
	# Never send anything to agents if we have no network connection
	return if ($self->passive || !$main::have_net);

	$master = $self->roles->get_active_master() unless (defined($master));

	my @roles		= sort($self->roles->get_host_roles($host));
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

