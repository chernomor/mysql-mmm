package MMM::Monitor::Agents;
use base 'Class::Singleton';

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use IO::Handle;




=head1 NAME

MMM::Monitor::Agents - holds status information for all agent hosts

=head1 SYNOPSIS

	my $agents = MMM::Monitor::Agents->instance();

=cut

sub _new_instance($) {
	my $class = shift;
	my $data = {};

	my @hosts		= keys(%{$main::config->{host}});

	foreach my $host (@hosts) {
		$data->{$host} = new MMM::Monitor::Agent:: (
			host		=> $host,
			mode		=> $main::config->{host}->{$host}->{mode},
			ip			=> $main::config->{host}->{$host}->{ip},
			port		=> $main::config->{host}->{$host}->{agent_port},
			state		=> 'UNKNOWN',
			roles		=> [],
			uptime		=> 0,
			last_uptime => 0
		);
	}
	return bless $data, $class;
}


=pod

	# Save status information into status file
	$status->save();

=cut

sub save_status($) {
	my $self	= shift;
	
	my $filename = $main::config->{monitor}->{status_path};
	my $tempname = $filename . '.tmp';

	open(STATUS, ">" . $tempname) || LOGDIE "Can't open temporary status file '$tempname' for writing!";

	keys (%$self); # reset iterator
	while (my ($host, $agent) = each(%$self)) {
		next unless $agent;
		printf(STATUS "%s|%s|%s\n", $host, $agent->state, join(',', sort(@{$agent->roles})));
	}
	IO::Handle::flush(*STATUS);
	IO::Handle::sync(*STATUS);
	close(STATUS);
	rename($tempname, $filename) || LOGDIE "Can't savely overwrite status file '$filename'!";
	return;
}


=pod

	# Load status information from status file
	$agents->load_status();

=cut

sub load_status($) {
	my $self	= shift;

	my $filename = $main::config->{monitor}->{status_path};
	
	open(STATUS, $filename) || return;

	while (my $line = <STATUS>) {
		chomp($line);
		my ($host, $state, $roles) = split(/\|/, $line);
		unless (defined($self->{$host})) {
			WARN "Ignoring saved status information for unknown host '$host'";
			next;
		}

		# Parse roles
		my @saved_roles_str = sort(split(/\,/, $roles));
		my @saved_roles = ();
		foreach my $role_str (@saved_roles_str) {
			my $role = MMM::Monitor::Role->from_string($role_str);
			push (@saved_roles, $role) if defined($role);
		}

		$self->{$host}->state($state);
		$self->{$host}->roles(\@saved_roles);
	}
	close(STATUS);
	return;
}


=pod

	# Fetch status information for host 'db2' from agent
	$status->load_from_agent('db2');

=cut

sub load_from_agent($$) {
	my $self		= shift;
	my $host_name	= shift;

	my $agent	= new MMM::Monitor::Agent::($host_name);

	# Check if host is reachable
	my $checks_status = MMM::Monitor::ChecksStatus->instance();
	unless ($checks_status->ping($host_name) && $checks_status->mysql($host_name)) {
		FATAL "No saved state for unreachable host $host_name - setting state to HARD_OFFLINE";
		$self->{$host_name}->{state} = 'HARD_OFFLINE';
		return;
	}

	# Get status information from agent
	my $res = $agent->send_command('GET_STATUS');
	if (!$res || $res !~ /(.*)\|(.*)?\|.*UP\:(.*)/) {
		FATAL "No saved state and unreachable agent on host $host_name - setting state to HARD_OFFLINE";
		$self->{$host_name}->{state} = 'HARD_OFFLINE';
		return;
	}

	my ($state, $roles, $master) = split(':', $2);

	# skip if agent doesn't know his state
	if ($state eq "UNKNOWN") {
		FATAL "No saved state and agent on host $host_name reportet state UNKNOWN - setting state to HARD_OFFLINE";
		$self->{$host_name}->{state} = 'HARD_OFFLINE';
		return;
	}

	# Restore status from agent data
	my @restored_roles_str = sort(split(/\,/, $roles));
	my @restored_roles;
	foreach my $role_str (@restored_roles_str) {
		my $role = MMM::Monitor::Role->from_string($role_str);
		push (@restored_roles, $role) if defined($role);
	}
	$self->{$host_name}->{state} = $state;
	@{$self->{$host_name}->{roles}} = @restored_roles;

	# TODO maybe we should somehow prevent a role _change_ of the "active_master"-role?

	FATAL "Restored state $state and roles from agent on host $host_name";
	return;
}

sub get_status_info($) {
	my $self	= shift;
	my $res		= '';

	keys (%$self); # reset iterator
	while (my ($host, $agent) = each(%$self)) {
		next unless $agent;
		$res .= sprintf("  %s(%s) %s/%s. Roles: %s\n", $host, $agent->ip, $agent->mode, $agent->state, join(',', sort(@{$agent->roles})));
	}
	return $res;
}

sub set_state($$$) {
	my $self	= shift;
	my $host	= shift;
	my $state	= shift;

	LOGDIE "Can't set state of invalid host '$host'" if (!defined($self->{$host}));
	$self->{$host}->state($state);
}

sub state($$) {
	my $self	= shift;
	my $host	= shift;
	LOGDIE "Can't get state of invalid host '$host'" if (!defined($self->{$host}));
	return $self->{$host}->state;
}

sub exists($$) {
	my $self	= shift;
	my $host	= shift;
	return defined($self->{$host});
}

sub get($$) {
	my $self	= shift;
	my $host	= shift;
	return $self->{$host};
}


# a server status contains
#	state
#	roles (array of type MMM::Monitor::Role with to_string operator overloaded)
#	uptime
#	last_uptime

1;
