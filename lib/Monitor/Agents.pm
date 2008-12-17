package MMM::Monitor::Agents;
use base 'Class::Singleton';

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use IO::Handle;




=head1 NAME

MMM::Monitor::Agents - single instance class holding status information for all agent hosts

=head1 SYNOPSIS

	# Get the instance
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


=head1 FUNCTIONS

=over 4

=item exists($host)

Check if host $host exists.

=cut

sub exists($$) {
	my $self	= shift;
	my $host	= shift;
	return defined($self->{$host});
}


=item get($host)

Get agent for host $host.

=cut

sub get($$) {
	my $self	= shift;
	my $host	= shift;
	return $self->{$host};
}


=item state($host)

Get state of host $host.

=cut

sub state($$) {
	my $self	= shift;
	my $host	= shift;
	LOGDIE "Can't get state of invalid host '$host'" if (!defined($self->{$host}));
	return $self->{$host}->state;
}


=item set_state($host, $state)

Set state of host $host to $state.

=cut

sub set_state($$$) {
	my $self	= shift;
	my $host	= shift;
	my $state	= shift;

	LOGDIE "Can't set state of invalid host '$host'" if (!defined($self->{$host}));
	$self->{$host}->state($state);
}


=item get_status_info

Get string containing status information.

=cut

sub get_status_info($) {
	my $self	= shift;
	my $res		= '';

	keys (%$self); # reset iterator
	foreach my $host (sort(keys(%$self))) {
		my $agent = $self->{$host};
		next unless $agent;
		$res .= sprintf("  %s(%s) %s/%s. Roles: %s\n", $host, $agent->ip, $agent->mode, $agent->state, join(', ', sort(@{$agent->roles})));
	}
	return $res;
}


=item save_status

Save status information into status file.

=cut

sub save_status($) {
	my $self	= shift;
	
	my $filename = $main::config->{monitor}->{status_path};
	my $tempname = $filename . '.tmp';

	open(STATUS, '>', $tempname) || LOGDIE "Can't open temporary status file '$tempname' for writing!";

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


=item load_status

Load status information from status file

=cut

sub load_status($) {
	my $self	= shift;

	my $filename = $main::config->{monitor}->{status_path};
	
	# Open status file
	unless (open(STATUS, '<', $filename)) {
		FATAL "Couldn't open status file '$filename': Starting up without status information.";
		return;
	}

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

1;
