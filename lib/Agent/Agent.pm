package MMM::Agent;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use Data::Dumper;
use Algorithm::Diff;

our $VERSION = '0.01';

use Class::Struct;

struct 'MMM::Agent' => {
	name				=> '$',
	ip					=> '$',
	port				=> '$',
	interface			=> '$',
	mode				=> '$',
	mysql_port			=> '$',
	mysql_user			=> '$',
	mysql_password		=> '$',
	writer_role			=> '$',
	bin_path			=> '$',

	active_master		=> '$',
	state				=> '$',
	roles				=> '@'
};

sub main($) {
	my $self	= shift;
	my $socket	= MMM::Common::Socket::create_listener($self->ip, $self->port);

	while (!$main::shutdown) {

		TRACE "Listener: Waiting for connection...";
		my $client = $socket->accept();
		next unless ($client);

		TRACE "Listener: Connect!";
		while (my $cmd = <$client>) {
			chomp($cmd);
			TRACE "Daemon: Command = '$cmd'";

			my $res = $self->handle_command($cmd);
			my $uptime = MMM::Common::Uptime::uptime();

			print $client "$res|UP:$uptime\n";
			TRACE "Daemon: Answer = '$res'";

			return 0 if ($main::shutdown);
		}
		close($client);

		TRACE("Listener: Disconnect!");
		
		$self->check_roles();
	}
}

sub handle_command($$) {
	my $self	= shift;
	my $cmd		= shift;
	my ($cmd_name, $version, $host, @params) = split(':', $cmd);

	return "ERROR: Invalid hostname in command ($host)! My name is '" . $self->name . '"' if ($host ne $self->name);
	
	if ($version > main::MMM_PROTOCOL_VERSION) {
		WARN "Version in command '$cmd_name' ($version) is greater than mine (", main::MMM_PROTOCOL_VERSION, ")"
	}
	
	if		($cmd_name eq 'PING')		{ return command_ping				();			}
	elsif	($cmd_name eq 'SET_STATUS')	{ return $self->command_set_status	(@params);	}
	elsif	($cmd_name eq 'GET_STATUS')	{ return $self->command_get_status	();			}

	return "ERROR: Invalid command '$cmd_name'!";
}

sub command_ping() {
	return 'OK: Pinged!';
}

sub command_get_status($) {
	my $self	= shift;
	
	my $answer = join (':', (
		$self->state,
		join(',', @{$self->roles}),
		$self->active_master
	));
	return "OK: Returning status!|$answer";
}

sub command_set_status($$) {
	my $self	= shift;
	my ($new_state, $new_roles_str, $new_master) = @_;

	# Change master if we are a slave
	if ($new_master ne $self->active_master && $self->mode eq 'slave' && $new_state eq 'ONLINE' && $new_master != '') {
		INFO "Changing active master to '$new_master'";
		my $res = MMM::Agent::Helpers::set_active_master($new_master);
		TRACE "Result: $res";
		if ($res =~ /^OK/) {
			$self->active_master($new_master);
		}
	}

	# Parse roles
	my @new_roles_arr = sort(split(/\,/, $new_roles_str));
	my @new_roles;
	foreach my $role_str (@new_roles_arr) {
		my $role = MMM::Agent::Role->from_string($role_str);
		if (defined($role)) {
			push @new_roles, $role;
		}
	}

	TRACE 'Old roles: ', Dumper([$self->roles]);
	TRACE 'New roles: ', Dumper(\@new_roles);
	
	# Process roles
	my @added_roles = ();
	my @deleted_roles = ();
	my $changes_count = 0;

	# Determine changes
	my $diff = Algorithm::Diff->new($self->roles, \@new_roles);#, keyGen => \&MMM::Agent::Role::to_string);
	while ($diff->Next) {
		next if ($diff->Same);

		$changes_count++;
		push (@deleted_roles,	$diff->Items(1)) if ($diff->Items(1));
		push (@added_roles,		$diff->Items(2)) if ($diff->Items(2));
	}

	# Apply changes
	if ($changes_count) {
		INFO 'We have some new roles added or old rules deleted!';
		INFO 'Deleted: ', Dumper(\@deleted_roles)	if (scalar(@deleted_roles));
		INFO 'Added:   ', Dumper(\@added_roles)		if (scalar(@added_roles));

		foreach my $role (@deleted_roles)	{ $role->del(); }
		foreach my $role (@added_roles)		{ $role->add(); }

		$self->roles(\@new_roles);
	}
	
	# Process state change
	if ($new_state ne $self->state) {
		if ($new_state		eq 'ADMIN_OFFLINE') { MMM::Agent::Helpers::turn_off_slave();	}
		if ($self->state	eq 'ADMIN_OFFLINE') { MMM::Agent::Helpers::turn_on_slave();		}
		$self->state($new_state);
	}

	return 'OK: Status applied successfully!';
}

sub check_roles($) {
	my $self	= shift;

	foreach my $role ($self->roles) {
		$role->check();	
	}
}

sub from_config($%) {
	my $self	= shift;
	my $config	= shift;

	my $host = $config->{host}->{$config->{this}};

	$self->name				($config->{this});
	$self->ip				($host->{ip});
	$self->port				($host->{agent_port});
	$self->interface		($host->{cluster_interface});
	$self->mode				($host->{mode});
	$self->mysql_port		($host->{mysql_port});
	$self->mysql_user		($host->{agent_user});
	$self->mysql_password	($host->{agent_password});
	$self->writer_role		($config->{active_master_role});
	$self->bin_path			($host->{bin_path});
}

1;
