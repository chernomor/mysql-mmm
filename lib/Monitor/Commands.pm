package MMM::Monitor::Commands;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use threads;
use threads::shared;
use MMM::Common::Socket;
use MMM::Monitor::Agents;
use MMM::Monitor::ChecksStatus;
use MMM::Monitor::Monitor;
use MMM::Monitor::Roles;

our $VERSION = '0.01';


sub main($$) {
	my $queue_in	= shift;
	my $queue_out	= shift;

	my $socket	= MMM::Common::Socket::create_listener($main::config->{monitor}->{ip}, $main::config->{monitor}->{port});

	while (!$main::shutdown) {
		DEBUG 'Listener: Waiting for connection...';
		my $client = $socket->accept();
		next unless ($client);

		DEBUG 'Listener: Connect!';
		while (my $cmd = <$client>) {	
			chomp($cmd);
			last if ($cmd eq 'quit');

			$queue_out->enqueue($cmd);
			my $res;
			until ($res) {
				lock($queue_in);
				cond_timedwait($queue_in, time() + 1); 
				$res = $queue_in->dequeue_nb();
				return 0 if ($main::shutdown);
			}
			print $client $res;
			return 0 if ($main::shutdown);
		}

		close($client);
		DEBUG 'Listener: Disconnect!';

	}	
}

sub ping() {
	return 'OK: Pinged successfully!';
}


sub show() {
	my $agents	= MMM::Monitor::Agents->instance();
	my $monitor	= MMM::Monitor::Monitor->instance();
	my $ret = '';
	if ($monitor->passive) {
		$ret .= "--- Monitor is in PASSIVE MODE ---\n";
		$ret .= sprintf("Cause: %s\n", $monitor->passive_info);
		$ret =~ s/^/# /mg;
	}
	$ret .= $agents->get_status_info();
	return $ret;
}

sub set_online($) {
	my $host	= shift;

	my $agents	= MMM::Monitor::Agents->instance();

	return "ERROR: Unknown host name '$host'!" unless (defined($main::config->{host}->{$host}));

	my $host_state = $agents->state($host);
	return "OK: This host is already ONLINE. Skipping command." if ($host_state eq 'ONLINE');

	unless ($host_state eq 'ADMIN_OFFLINE' || $host_state eq 'AWAITING_RECOVERY') {
		return "ERROR: Host '$host' is '$host_state' at the moment. It can't be switched to ONLINE.";
	}

	my $checks	= MMM::Monitor::ChecksStatus->instance();

	if ((!$checks->ping($host) || !$checks->mysql($host))) {
		return "ERROR: Checks ping and/or mysql are not ok for host '$host'. It can't be switched to ONLINE.";
	}

	# Check peer replication state
	if ($main::config->{host}->{$host}->{peer}) {
		my $peer = $main::config->{host}->{$host}->{peer};
		if ($agents->state($peer) eq 'ONLINE' && (!$checks->rep_threads($peer) || !$checks->rep_backlog($peer))) {
			return "ERROR: Some replication checks failed on peer '$peer'. We can't set '$host' online now. Please, wait some time.";
		}
	}

	my $agent = MMM::Monitor::Agents->instance()->get($host);
	if (!$agent->cmd_ping()) {
		return "ERROR: Can't reach agent daemon on '$host'! Can't switch its state!";
	}

	FATAL "Admin changed state of '$host' from $host_state to ONLINE";
	$agents->set_state($host, 'ONLINE');
	$agent->flapping(0);
	MMM::Monitor::Monitor->instance()->send_agent_status($host);

    return "OK: State of '$host' changed to ONLINE. Now you can wait some time and check its new roles!";
}

sub set_offline($) {
	my $host	= shift;

	my $agents	= MMM::Monitor::Agents->instance();

	return "ERROR: Unknown host name '$host'!" unless (defined($main::config->{host}->{$host}));

	my $host_state = $agents->state($host);
	return "OK: This host is already ADMIN_OFFLINE. Skipping command." if ($host_state eq 'ADMIN_OFFLINE');

	unless ($host_state eq 'ONLINE' || $host_state eq 'REPLICATION_FAIL' || $host_state eq 'REPLICATION_BACKLOG') {
		return "ERROR: Host '$host' is '$host_state' at the moment. It can't be switched to ADMIN_OFFLINE.";
	}

	my $agent = MMM::Monitor::Agents->instance()->get($host);
	return "ERROR: Can't reach agent daemon on '$host'! Can't switch its state!" unless ($agent->cmd_ping());

	FATAL "Admin changed state of '$host' from $host_state to ADMIN_OFFLINE";
	$agents->set_state($host, 'ADMIN_OFFLINE');
	MMM::Monitor::Roles->instance()->clear_host_roles($host);
	MMM::Monitor::Monitor->instance()->send_agent_status($host);

    return "OK: State of '$host' changed to ADMIN_OFFLINE. Now you can wait some time and check all roles!";
}

sub set_ip($$) {
	my $ip		= shift;
	my $host	= shift;

	return "ERROR: This command is only allowed in passive mode" unless (MMM::Monitor::Monitor->instance()->passive);

	my $agents	= MMM::Monitor::Agents->instance();
	my $roles	= MMM::Monitor::Roles->instance();

	my $role = $roles->find_by_ip($ip);

	return "ERROR: Unknown ip '$ip'!" unless (defined($role));
	return "ERROR: Unknown host name '$host'!" unless ($agents->exists($host));

	unless ($roles->can_handle($role, $host)) {
		return "ERROR: Host '$host' can't handle role '$role'. Following hosts could: " . join(', ', @{ $roles->get_valid_hosts($role) });
	}

	my $host_state = $agents->state($host);
	unless ($host_state eq 'ONLINE') {
		return "ERROR: Host '$host' is '$host_state' at the moment. Can't move role with ip '$ip' there.";
	}

	FATAL "Admin set role '$role($ip)' to host '$host'";

	$roles->set_role($role, $ip, $host);

	# Determine all roles and propagate them to agent objects.
	foreach my $one_host (@{ $roles->get_valid_hosts($role) }) {
		my $agent = $agents->get($one_host);
		my @agent_roles = sort($roles->get_host_roles($one_host));
		$agent->roles(\@agent_roles);
	}
	return "OK: Set role '$role($ip)' to host '$host'.";
}

sub move_role($$) {
	my $role	= shift;
	my $host	= shift;
	
	return "ERROR: This command is only allowed in active mode" if (MMM::Monitor::Monitor->instance()->passive);

	my $agents	= MMM::Monitor::Agents->instance();
	my $roles	= MMM::Monitor::Roles->instance();

	return "ERROR: Unknown role name '$role'!" unless ($roles->exists($role));
	return "ERROR: Unknown host name '$host'!" unless ($agents->exists($host));
	return "ERROR: move_role may be used for exclusive roles only!" unless ($roles->is_exclusive($role));

	my $host_state = $agents->state($host);
	return "ERROR: Can't move role to host with state $host_state." unless ($host_state eq 'ONLINE');

	unless ($roles->can_handle($role, $host)) {
        return "ERROR: Host '$host' can't handle role '$role'. Only following hosts could: " . join(', ', @{ $roles->get_valid_hosts($role) });
	}
	
	my $old_owner = $roles->get_exclusive_role_owner($role);
	return "OK: Role is on '$host' already. Skipping command." if ($old_owner eq $host);

	my $agent = MMM::Monitor::Agents->instance()->get($host);
	return "ERROR: Can't reach agent daemon on '$host'! Can't move roles there!" unless ($agent->cmd_ping());

	my $ip = $roles->get_exclusive_role_ip($role);
	return "Error: Role $role has no IP." unless ($ip);

	FATAL "Admin moved role '$role' from '$old_owner' to '$host'";

	# Assign role to new host
	my $role_obj = new MMM::Common::Role(name => $role, ip => $ip);
	$roles->assign($role_obj, $host);

	# Notify old host (if is_active_master_role($role) this will make the host non writable)
	MMM::Monitor::Monitor->instance()->send_agent_status($old_owner);

	# Notify old host (this will make them switch the master)
	MMM::Monitor::Monitor->instance()->notify_slaves($host) if ($roles->is_active_master_role($role));

	# Notify new host (if is_active_master_role($role) this will make the host writable)
	MMM::Monitor::Monitor->instance()->send_agent_status($host);
	
	return "OK: Role '$role' has been moved from '$old_owner' to '$host'. Now you can wait some time and check new roles info!";
	
}


=item mode

Get information about current mode (active or passive)

=cut

sub mode() {
	return 'PASSIVE' if (MMM::Monitor::Monitor->instance()->passive);
	return 'ACTIVE';
}


=item set_active

Switch to active mode.

=cut

sub set_active() {
	return 'OK: Already in active mode.' unless (MMM::Monitor::Monitor->instance()->passive);


	# Send status to agents
	MMM::Monitor::Monitor->instance()->send_status_to_agents();

	# Clear 'bad' roles
	my $agents	= MMM::Monitor::Agents->instance();
	foreach my $host (keys(%{$main::config->{host}})) {
		my $agent = $agents->get($host);
		$agent->cmd_clear_bad_roles(); # TODO check result
	}


	MMM::Monitor::Monitor->instance()->passive(0);
	MMM::Monitor::Monitor->instance()->passive_info('');
	return 'OK: Switched into active mode.';
}


=item set_passive

Switch to passive mode.

=cut

sub set_passive() {
	return 'OK: Already in passive mode.' if (MMM::Monitor::Monitor->instance()->passive);

	MMM::Monitor::Monitor->instance()->passive(1);
	MMM::Monitor::Monitor->instance()->passive_info('Admin switched to passive mode.');
	return 'OK: Switched into passive mode.';
}

sub help() {
	return: "Valid commands are:
    help                         - show this message
    ping                         - ping monitor
    show                         - show status
    set_online <host>            - set host <host> online
    set_offline <host>           - set host <host> offline
    mode                         - print current mode.
    set_active                   - switch into active mode.
    set_passive                  - switch into passive mode.
    move_role <role> <host>      - move exclusive role <role> to host <host>
    set_ip <ip> <host>           - set role with ip <ip> to host <host>
";
}

1;
