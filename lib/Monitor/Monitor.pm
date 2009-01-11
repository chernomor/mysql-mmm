package MMM::Monitor::Monitor;

use strict;
use warnings FATAL => 'all';
use threads;
use threads::shared;
use Log::Log4perl qw(:easy);
use Thread::Queue;
use Data::Dumper;
use Algorithm::Diff;
use MMM::Monitor::Agents;
use MMM::Monitor::Checker;
use MMM::Monitor::ChecksStatus;
use MMM::Monitor::Commands;
use MMM::Monitor::NetworkChecker;
use MMM::Monitor::Role;
use MMM::Monitor::Roles;

=head1 NAME

MMM::Monitor::Monitor - single instance class with monitor logic

=cut

our $VERSION = '0.01';

use Class::Struct;

sub instance() {
	return $main::monitor;
}

struct 'MMM::Monitor::Monitor' => {
	agents				=> 'MMM::Monitor::Agents',
	checker_queue		=> 'Thread::Queue',
	checks_status		=> 'MMM::Monitor::ChecksStatus',
	command_queue		=> 'Thread::Queue',
	result_queue		=> 'Thread::Queue',
	roles				=> 'MMM::Monitor::Roles',
	passive				=> '$',
	passive_info		=> '$'
};


=head1 FUNCTIONS

=over 4

=item init

Init queues, single instance classes, ... and try to determine status.

=cut

sub init($) {
	my $self = shift;
	my $agents = MMM::Monitor::Agents->instance();
	$self->checker_queue(new Thread::Queue::);
	$self->checks_status(MMM::Monitor::ChecksStatus->instance());
	$self->command_queue(new Thread::Queue::);
	$self->result_queue(new Thread::Queue::);
	$self->roles(MMM::Monitor::Roles->instance());
	$self->passive_info('');

	# Go into passive mode if we have no network connection at startup
	$self->passive(!$main::have_net);
	$self->passive_info('No network connection during start up.') unless ($main::have_net);


	# Figure out current status. Go into passive mode if there are discrepancies
	$agents->load_status();

	my $system_status	= {};
	my $agent_status	= {};
	my $status			= 1;
	my $res;
	foreach my $host (keys(%{$main::config->{host}})) {
		my $agent = $agents->get($host);
		$res = $agent->cmd_get_agent_status();
		if ($res =~ /^OK/) {
			my ($msg, $state, $roles_str, $master) = split('\|', $res);
			my @roles_str_arr = sort(split(/\,/, $roles_str));
			my @roles;
			foreach my $role_str (@roles_str_arr) {
				my $role = MMM::Monitor::Role->from_string($role_str);
				if (defined($role)) {
					push @roles, $role;
				}
			}
			$agent_status->{$host} = {
				state	=> $state,
				roles	=> \@roles,
				master	=> $master
			};
		}
		else {
			FATAL "Could not get agent status for host '$host'. Will switch to passive mode: $res";
			$status = 0;
		}
		
		$res = $agent->cmd_get_system_status();
		if ($res =~ /^OK/) {
			my ($msg, $writable, $roles_str) = split('\|', $res);
			my @roles_str_arr = sort(split(/\,/, $roles_str));
			my @roles;
			foreach my $role_str (@roles_str_arr) {
				my $role = MMM::Monitor::Role->from_string($role_str);
				if (defined($role)) {
					push @roles, $role;
				}
			}
			$system_status->{$host} = {
				writable	=> $writable,
				roles		=> \@roles
			};
		}
		else {
			FATAL "Could not get system status for host '$host'. Will switch to passive mode: $res";
			$status = 0;
		}
		next unless (defined($agent_status->{$host}));
		next unless (defined($system_status->{$host}));

		if ($agent_status->{$host}->{state} ne 'UNKNOWN' && $agent_status->{$host}->{state} ne $agent->state) {
			FATAL "Agent state '", $agent_status->{$host}->{state}, "' differs from stored one '", $agent->state, "' for host '$host'. Will switch to passive mode";
			$status = 0;
			next;
		}

		# Determine if roles differ 
		my $changes	= 0;
		my $diff	= new Algorithm::Diff:: (
			$system_status->{$host}->{roles},
			$agent->roles,
			{ keyGen => \&MMM::Common::Role::to_string }
		);
		while ($diff->Next) {
			next if ($diff->Same);
			FATAL sprintf(
				"Switching to passive mode: Roles of host '$host' [%s] differ from stored ones [%s]",
				join(', ', @{$system_status->{$host}->{roles}}),
				join(', ', @{$agent->roles})
			);
			$status = 0;
			last;
		}
		
		# TODO check "writable" if host has master role
	}

	DEBUG "STATE INFO\n", Data::Dumper->Dump([$agents, $agent_status, $system_status], ['Stored status', 'Agent status', 'System status']);

	unless ($status) {
		$self->passive(1);
		my $agent_status_str = '';
		foreach my $host (sort(keys(%{$agent_status}))) {
			$agent_status_str .= sprintf(
				"  %s %s. Roles: %s. Master: %s\n",
				$host,
				$agent_status->{$host}->{state},
				scalar(@{$agent_status->{$host}->{roles}}) > 0 ? join(', ', sort(@{$agent_status->{$host}->{roles}})) : 'none',
				$agent_status->{$host}->{master} ? $agent_status->{$host}->{master} : 'unknown'
			);
		}
		my $system_status_str = '';
		foreach my $host (sort(keys(%{$system_status}))) {
			$system_status_str .= sprintf(
				"  %s %s. Roles: %s\n",
				$host,
				$system_status->{$host}->{writable} ? 'writable' : 'readonly',
				scalar(@{$system_status->{$host}->{roles}}) > 0 ? join(', ', sort(@{$system_status->{$host}->{roles}})) : 'none'
			);
		}
		my $status_str = sprintf("\nStored status:\n%s\nAgent status:\n%s\nSystem status:\n%s", $agents->get_status_info(), $agent_status_str, $system_status_str);
		$self->passive_info("Discrepancies between stored status, agent status and system status during startup.\n" . $status_str);
		FATAL "Switching to PASSIVE MODE!!! $status_str";
		foreach my $host (keys(%{$main::config->{host}})) {
			my $agent = $agents->get($host);

			# Set unknown hosts to AWAITING_RECOVERY
			$agent->state('AWAITING_RECOVERY') if ($agent->state eq 'UNKNOWN');
		}
		return;
	}

	# Everything is okay, apply roles from status file.
	foreach my $host (keys(%{$main::config->{host}})) {
		my $agent = $agents->get($host);

		# Set new hosts to AWAITING_RECOVERY
		if ($agent->state eq 'UNKNOWN') {
			FATAL "Detected new host '$host': Setting its initial state to 'AWAITING_RECOVERY'.";
			$agent->state('AWAITING_RECOVERY');
		}

		# Apply roles loaded from status file
		foreach my $role (@{$agent->roles}) {
			unless ($self->roles->exists_ip($role->name, $role->ip)) {
				FATAL "Detected change in role definitions: Role '$role' was removed.";
				next;
			}
			unless ($self->roles->can_handle($role->name, $host)) {
				FATAL "Detected change in role definitions: Host '$host' can't handle role '$role' anymore.";
				next;
			}
			$self->roles->set_role($role->name, $role->ip, $host);
		}
	}

}


=item main

Main thread

=cut

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
	

	my $command_queue = $self->command_queue;

	while (!$main::shutdown) {
		$self->_process_check_results();
		$self->_check_host_states();
		$self->_process_commands();
		$self->_distribute_roles();
		$self->send_status_to_agents();

		# sleep 3 seconds, wake up if command queue gets filled
		lock($command_queue);
		cond_timedwait($command_queue, time() + 3); 
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


=item _check_host_states

Check states of hosts and change status/roles accordingly.

=cut

sub _check_host_states($) {
	my $self = shift;

	# Don't do anything if we have no network connection
	return if (!$main::have_net);

	my $checks	= $self->checks_status;
	my $agents	= MMM::Monitor::Agents->instance();

	foreach my $host (keys(%{$main::config->{host}})) {

		$agents->save_status() unless ($self->passive);

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
			if ($ping && $mysql && !$rep_threads && $peer_state eq 'ONLINE' && $checks->ping($peer) && $checks->mysql($peer)) {
				FATAL "State of host '$host' changed from $state to REPLICATION_FAIL";
				$agent->state('REPLICATION_FAIL');
				$self->roles->clear_host_roles($host);
				$self->send_agent_status($host);
				next;
			}

			# ONLINE -> REPLICATION_DELAY
			if ($ping && $mysql && !$rep_backlog && $rep_threads && $peer_state eq 'ONLINE' && $checks->ping($peer) && $checks->mysql($peer)) {
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
				next unless ($agent->last_uptime > 0 && $uptime_diff > 0 && $uptime_diff < 60);
				next if ($agent->flapping);
				if ($agent->mode eq 'master') {
					next unless ($peer_state eq 'ONLINE' && $checks->rep_backlog($peer) && $checks->rep_threads($peer));
				}
				FATAL "State of host '$host' changed from $state to ONLINE because it was down for only $uptime_diff seconds";
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
			if ($ping && $mysql && (($rep_backlog && $rep_threads) || $peer_state ne 'ONLINE')
			) {

				# REPLICATION_DELAY || REPLICATION_FAIL -> AWAITING_RECOVERY
				if ($agent->flapping) {
					FATAL "State of host '$host' changed from $state to AWAITING_RECOVERY (because it's flapping)";
					$agent->state('AWAITING_RECOVERY');
					$self->send_agent_status($host);
					next;
				}

				# REPLICATION_DELAY || REPLICATION_FAIL -> ONLINE
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
	$agents->save_status() unless ($self->passive);
}


=item _distribute_roles

Distribute roles among the hosts.

=cut

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


=item send_status_to_agents

Send status information to all agents.

=cut

sub send_status_to_agents($) {
	my $self	= shift;

	# Send status to all hosts
	my $master	= $self->roles->get_active_master();
	foreach my $host (keys(%{$main::config->{host}})) {
		$self->send_agent_status($host, $master);
	}
}


=item notify_slaves

Notify all slave hosts (used when master changes).

=cut

sub notify_slaves($$) {
	my $self		= shift;
	my $new_master	= shift;

	# Send status to all hosts with mode = 'slave'
	foreach my $host (keys(%{$main::config->{host}})) {
		next unless ($main::config->{host}->{$host}->{mode} eq 'slave');
		$self->send_agent_status($host, $new_master);
	}
}


=item send_agent_status($host[, $master])

Send status information to agent on host $host.

=cut

sub send_agent_status($$$) {
	my $self	= shift;
	my $host	= shift;
	my $master	= shift;

	# Never send anything to agents if we are in PASSIVE mode
	# Never send anything to agents if we have no network connection
	return if ($self->passive || !$main::have_net);

	# Determine active master if it was not passed
	$master = $self->roles->get_active_master() unless (defined($master));

	my $agent = MMM::Monitor::Agents->instance()->get($host);

	# Determine and set roles
	my @roles = sort($self->roles->get_host_roles($host));
	$agent->roles(\@roles);

	# Finally send command
	return $agent->cmd_set_status($master);
}


=item _process_commands

Process commands received from the command thread.

=cut

sub _process_commands($) {
	my $self		= shift;

	# Handle all queued commands
	while (my $cmdline = $self->command_queue->dequeue_nb) {

		# Parse command
		my @args	= split(/\s+/, $cmdline);
		my $command	= shift @args;
		my $arg_cnt	= scalar(@args);
		my $res;

		# Execute command
		if    ($command eq 'ping'			&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::ping();			}
		elsif ($command eq 'show'			&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::show();			}
		elsif ($command eq 'mode'			&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::mode();			}
		elsif ($command eq 'set_active'		&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::set_active();	}
		elsif ($command eq 'set_passive'	&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::set_passive();	}
		elsif ($command eq 'set_online'		&& $arg_cnt == 1) { $res = MMM::Monitor::Commands::set_online ($args[0]);	}
		elsif ($command eq 'set_offline'	&& $arg_cnt == 1) { $res = MMM::Monitor::Commands::set_offline($args[0]);	}
		elsif ($command eq 'move_role'		&& $arg_cnt == 2) { $res = MMM::Monitor::Commands::move_role($args[0], $args[1]);	}
		elsif ($command eq 'set_ip'			&& $arg_cnt == 2) { $res = MMM::Monitor::Commands::set_ip($args[0], $args[1]);		}
		else { $res = "Invalid command '$cmdline'\n\n" . MMM::Monitor::Commands::help(); }

		# Enqueue result
		$self->result_queue->enqueue($res);
	}
}

1;

