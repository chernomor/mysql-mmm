package MMM::Monitor::Monitor;

use strict;
use warnings FATAL => 'all';
use threads;
use threads::shared;
use Algorithm::Diff;
use Algorithm::Diff;
use Data::Dumper;
use DBI;
use Errno qw(EINTR);
use Log::Log4perl qw(:easy);
use Thread::Queue;
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

	my $checks	= $self->checks_status;

	#___________________________________________________________________________
	#
	# Go into passive mode if we have no network connection at startup
	#___________________________________________________________________________

	$self->passive(!$main::have_net);
	$self->passive_info('No network connection during startup.') unless ($main::have_net);

	
	#___________________________________________________________________________
	#
	# Check replication setup of master hosts
	#___________________________________________________________________________

	$self->check_master_configuration();


	#___________________________________________________________________________
	#
	# Figure out current status. Go into passive mode if there are discrepancies
	#___________________________________________________________________________

	$agents->load_status();

	my $system_status	= {};
	my $agent_status	= {};
	my $status			= 1;
	my $res;

	foreach my $host (keys(%{$main::config->{host}})) {

		my $agent		= $agents->get($host);
		my $host_status	= 1;


		#_______________________________________________________________________
		#
		# Get AGENT status
		#_______________________________________________________________________

		$res = $agent->cmd_get_agent_status(2);

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

			$agent_status->{$host} = { state => $state, roles => \@roles, master => $master };
		}
		elsif ($agent->state ne 'ADMIN_OFFLINE') {
			if ($checks->ping($host) && $checks->mysql($host) && !$agent->agent_down()) {
				ERROR "Can't reach agent on host '$host'";
				$agent->agent_down(1);
			}
			ERROR "Switching to passive mode: The status of the agent on host '$host' could not be determined (answer was: $res).";
			$status			= 0;
			$host_status	= 0;
		}
		

		#_______________________________________________________________________
		#
		# Get SYSTEM status
		#_______________________________________________________________________

		$res = $agent->cmd_get_system_status(2);
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
		elsif ($agent->state ne 'ADMIN_OFFLINE') {
			if ($checks->ping($host) && $checks->mysql($host) && !$agent->agent_down()) {
				ERROR "Can't reach agent on host '$host'";
				$agent->agent_down(1);
			}
			ERROR "Switching to passive mode: The status of the system '$host' could not be determined (answer was: $res).";
			$status			= 0;
			$host_status	= 0;

		}


		#_______________________________________________________________________
		#
		# Skip comparison, if we coult not fetch AGENT/SYSTEM status
		#_______________________________________________________________________
		
		next unless (defined($agent_status->{$host}));
		next unless (defined($system_status->{$host}));


		#_______________________________________________________________________
		#
		# Compare agent and system status ...
		#_______________________________________________________________________

		if ($agent_status->{$host}->{state} ne 'UNKNOWN' && $agent_status->{$host}->{state} ne $agent->state) {
			ERROR "Switching to passive mode: Agent state '", $agent_status->{$host}->{state}, "' differs from stored one '", $agent->state, "' for host '$host'.";
			$status			= 0;
			$host_status	= 0;
			next;
		}


		#_______________________________________________________________________
		#
		# ... determine if roles differ 
		#_______________________________________________________________________

		my $changes	= 0;
		my $diff	= new Algorithm::Diff:: (
			$system_status->{$host}->{roles},
			$agent->roles,
			{ keyGen => \&MMM::Common::Role::to_string }
		);

		while ($diff->Next) {
			next if ($diff->Same);

			ERROR sprintf(
				"Switching to passive mode: Roles of host '$host' [%s] differ from stored ones [%s]",
				join(', ', @{$system_status->{$host}->{roles}}),
				join(', ', @{$agent->roles})
			);
			$status			= 0;
			$host_status	= 0;
			last;
		}
		
		next unless ($host_status);
		foreach my $role (@{$agent->roles}) {
			next if ($self->roles->is_active_master_role($role));
			next if ($system_status->{$host}->{writable});
			WARN "Active master $host was not writable at monitor startup. (Don't mind, the host will be made writable soon)"
		}
		
	}

	DEBUG "STATE INFO\n", Data::Dumper->Dump([$agents, $agent_status, $system_status], ['Stored status', 'Agent status', 'System status']);


	#___________________________________________________________________________
	#
	# Maybe switch into passive mode?
	#___________________________________________________________________________

	unless ($status) {
		# Enter PASSIVE MODE
		$self->passive(1);
		my $agent_status_str = '';
		foreach my $host (sort(keys(%{$agent_status}))) {
			$agent_status_str .= sprintf(
				"  %s %s. Roles: %s. Master: %s\n",
				$host,
				$agent_status->{$host}->{state},
				scalar(@{$agent_status->{$host}->{roles}}) > 0 ? join(', ', sort(@{$agent_status->{$host}->{roles}})) : 'none',
				$agent_status->{$host}->{master} ? $agent_status->{$host}->{master} : '?'
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
		FATAL "Switching to passive mode now. See output of 'mmm_control show' for details.";
		INFO $status_str;

		foreach my $host (keys(%{$main::config->{host}})) {
			my $agent = $agents->get($host);

			# Set all unknown hosts to AWAITING_RECOVERY
			$agent->state('AWAITING_RECOVERY') if ($agent->state eq 'UNKNOWN');

			next unless ($system_status->{$host});
			next unless (scalar(@{$system_status->{$host}->{roles}}));
			# Set status restored from agent systems
			$agent->state('ONLINE');
			foreach my $role (@{$system_status->{$host}->{roles}}) {
				next unless ($self->roles->exists_ip($role->name, $role->ip));
				next unless ($self->roles->can_handle($role->name, $host));
				$self->roles->set_role($role->name, $role->ip, $host);
			}
		}

		# propagate roles to agent objects
		foreach my $host (keys(%{$main::config->{host}})) {
			my $agent = $agents->get($host);
			my @roles = sort($self->roles->get_host_roles($host));
			$agent->roles(\@roles);
		}

		WARN "Monitor started in passive mode.";

		return;
	}

	# Stay in ACTIVE MODE
	# Everything is okay, apply roles from status file.
	foreach my $host (keys(%{$main::config->{host}})) {
		my $agent = $agents->get($host);

		# Set new hosts to AWAITING_RECOVERY
		if ($agent->state eq 'UNKNOWN') {
			WARN "Detected new host '$host': Setting its initial state to 'AWAITING_RECOVERY'. Use 'mmm_control set_online $host' to switch it online.";
			$agent->state('AWAITING_RECOVERY');
		}

		# Apply roles loaded from status file
		foreach my $role (@{$agent->roles}) {
			unless ($self->roles->exists_ip($role->name, $role->ip)) {
				WARN "Detected change in role definitions: Role '$role' was removed.";
				next;
			}
			unless ($self->roles->can_handle($role->name, $host)) {
				WARN "Detected change in role definitions: Host '$host' can't handle role '$role' anymore.";
				next;
			}
			$self->roles->set_role($role->name, $role->ip, $host);
		}
	}

	INFO "Monitor started in active mode."  unless ($self->passive);
	WARN "Monitor started in passive mode." if ($self->passive);
}

sub check_master_configuration($) {
	my $self	= shift;

	# Get masters
	my @masters = $self->roles->get_role_hosts($main::config->{active_master_role});

	if (scalar(@masters) < 2) {
		WARN "Only one host configured which can handle the active master role. Skipping check of master-master configuration.";
		return;
	}
	if (scalar(@masters) > 2) {
		LOGDIE "There are more than two hosts configured which can handle the active master role.";
	}


	# Check status of masters
	my $checks	= $self->checks_status;
	foreach my $master (@masters) {
		next if ($checks->mysql($master));
		WARN "Check 'mysql' is in state 'failed' on host '$master'. Skipping check of master-master configuration.";
		return;
	}


	# Connect to masters
	my ($master1, $master2) = @masters;
	my $master1_info = $main::config->{host}->{$master1};
	my $master2_info = $main::config->{host}->{$master2};

	my $dsn1	= sprintf("DBI:mysql:host=%s;port=%s;mysql_connect_timeout=3", $master1_info->{ip}, $master1_info->{mysql_port});
	my $dsn2	= sprintf("DBI:mysql:host=%s;port=%s;mysql_connect_timeout=3", $master2_info->{ip}, $master2_info->{mysql_port});

	my $eintr	= EINTR;

	my $dbh1;
CONNECT1: {
	DEBUG "Connecting to master 1";
	$dbh1	= DBI->connect($dsn1, $master1_info->{monitor_user}, $master1_info->{monitor_password}, { PrintError => 0 });
	unless ($dbh1) {
		redo CONNECT1 if ($DBI::err == 2003 && $DBI::errstr =~ /\($eintr\)/);
		WARN "Couldn't connect to  '$master1'. Skipping check of master-master replication." . $DBI::err . " " . $DBI::errstr;
	}
}

	my $dbh2;
CONNECT2: {
	DEBUG "Connecting to master 2";
	$dbh2	= DBI->connect($dsn2, $master2_info->{monitor_user}, $master2_info->{monitor_password}, { PrintError => 0 });
	unless ($dbh2) {
		redo CONNECT2 if ($DBI::err == 2003 && $DBI::errstr =~ /\($eintr\)/);
		WARN "Couldn't connect to  '$master2'. Skipping check of master-master replication." . $DBI::err . " " . $DBI::errstr;
	}
}


	# Check replication peers
	my $slave_status1 = $dbh1->selectrow_hashref('SHOW SLAVE STATUS');
	my $slave_status2 = $dbh2->selectrow_hashref('SHOW SLAVE STATUS');

	WARN "$master1 is not replicating from $master2" if (!defined($slave_status1) || $slave_status1->{Master_Host} ne $master2_info->{ip});
	WARN "$master2 is not replicating from $master1" if (!defined($slave_status2) || $slave_status2->{Master_Host} ne $master1_info->{ip});


	# Check auto_increment_offset and auto_increment_increment
	my ($offset1, $increment1) = $dbh1->selectrow_array('select @@auto_increment_offset, @@auto_increment_increment');
	my ($offset2, $increment2) = $dbh2->selectrow_array('select @@auto_increment_offset, @@auto_increment_increment');

	unless (defined($offset1) && defined($increment1)) {
		WARN "Couldn't get value of auto_increment_offset/auto_increment_increment from host $master1. Skipping check of master-master replication.";
		return;
	}
	unless (defined($offset2) && defined($increment2)) {
		WARN "Couldn't get value of auto_increment_offset/auto_increment_increment from host $master2. Skipping check of master-master replication.";
		return;
	}
	
	WARN "auto_increment_increment should be identical on both masters ($master1: $increment1 , $master2: $increment2)" unless ($increment1 == $increment2);
	WARN "auto_increment_offset should be different on both masters ($master1: $offset1 , $master2: $offset2)" unless ($offset1 != $offset2);
	WARN "$master1: auto_increment_increment ($increment1) should be >= 2" unless ($increment1 >= 2);
	WARN "$master2: auto_increment_increment ($increment2) should be >= 2" unless ($increment2 >= 2);
	WARN "$master1: auto_increment_offset ($offset1) should not be greater than auto_increment_increment ($increment1)" unless ($offset1 <= $increment1);
	WARN "$master2: auto_increment_offset ($offset2) should not be greater than auto_increment_increment ($increment2)" unless ($offset2 <= $increment2);

}


=item main

Main thread

=cut

sub main($) {
	my $self	= shift;

	# Delay execution so we can reap all childs before spawning the checker threads.
	# This prevents a segfault if a SIGCHLD arrives during creation of a thread.
	# See perl bug #60724
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

	my $active_master = $self->roles->get_active_master();

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
			$peer	= $active_master
		}

		my $peer_state = '';
		my $peer_online_since = 0;
		if ($peer) {
			$peer_state			= $agents->state($peer);
			$peer_online_since	= $agents->online_since($peer);
		}

		# Simply skip this host. It is offlined by admin
		next if ($state eq 'ADMIN_OFFLINE');

		########################################################################

		if ($state eq 'ONLINE') {

			# ONLINE -> HARD_OFFLINE
			unless ($ping && $mysql) {
				FATAL sprintf("State of host '%s' changed from %s to HARD_OFFLINE (ping: %s, mysql: %s)", $host, $state, ($ping? 'OK' : 'not OK'), ($mysql? 'OK' : 'not OK'));
				$agent->state('HARD_OFFLINE');
				$self->roles->clear_host_roles($host);
				$self->send_agent_status($host);
				# TODO kill host (remove ips, drop connections, iptable connections, ...) if sending state was not ok
				next;
			}

			# replication failure on active master is irrelevant.
			next if ($host eq $active_master);

			# ignore replication failure, if peer got online recently (60 seconds, default value of master-connect-retry)
			next if ($peer_state eq 'ONLINE' && $peer_online_since >= time() - 60);

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
				FATAL sprintf("State of host '%s' changed from %s to ONLINE because it was down for only %d seconds", $host, $state, $uptime_diff);
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
			if ($ping && $mysql && !$rep_threads) {
				FATAL "State of host '$host' changed from $state to REPLICATION_FAIL";
				$agent->state('REPLICATION_FAIL');
				next;
			}
		}

		########################################################################

		if ($state eq 'REPLICATION_DELAY' || $state eq 'REPLICATION_FAIL') {
			if ($ping && $mysql && (($rep_backlog && $rep_threads) || $peer_state ne 'ONLINE')) {

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
				FATAL sprintf("State of host '%s' changed from %s to HARD_OFFLINE (ping: %s, mysql: %s)", $host, $state, ($ping? 'OK' : 'not OK'), ($mysql? 'OK' : 'not OK'));
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
	$self->roles->process_orphans('exclusive');
	$self->roles->process_orphans('balanced');

	# obey preferences
	$self->roles->obey_preferences();

	# Balance roles
	$self->roles->balance();

	my $new_active_master = $self->roles->get_active_master();

	# notify slaves first, if master host has changed
	unless ($new_active_master eq $old_active_master) {
		$self->send_agent_status($old_active_master, $new_active_master) if ($old_active_master);
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
	my $ret = $agent->cmd_set_status($master);

	unless ($ret) {
		# If mysql or ping is down, nothing will be send to agent. So this doesn't indicate that the agent is down.
		my $checks	= $self->checks_status;
		if ($checks->ping($host) && $checks->mysql($host) && !$agent->agent_down()) {
			FATAL "Can't reach agent on host '$host'";
			$agent->agent_down(1);
		}
	}
	elsif ($agent->agent_down) {
		FATAL "Agent on host '$host' is reachable again";
		$agent->agent_down(0);
	}
	return $ret;
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
		if    ($command eq 'ping'			&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::ping();							}
		elsif ($command eq 'show'			&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::show();							}
		elsif ($command eq 'mode'			&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::mode();							}
		elsif ($command eq 'set_active'		&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::set_active();					}
		elsif ($command eq 'set_passive'	&& $arg_cnt == 0) { $res = MMM::Monitor::Commands::set_passive();					}
		elsif ($command eq 'set_online'		&& $arg_cnt == 1) { $res = MMM::Monitor::Commands::set_online ($args[0]);			}
		elsif ($command eq 'set_offline'	&& $arg_cnt == 1) { $res = MMM::Monitor::Commands::set_offline($args[0]);			}
		elsif ($command eq 'move_role'		&& $arg_cnt == 2) { $res = MMM::Monitor::Commands::move_role($args[0], $args[1]);	}
		elsif ($command eq 'set_ip'			&& $arg_cnt == 2) { $res = MMM::Monitor::Commands::set_ip($args[0], $args[1]);		}
		else { $res = "Invalid command '$cmdline'\n\n" . MMM::Monitor::Commands::help(); }

		# Enqueue result
		$self->result_queue->enqueue($res);
	}
}

1;

