package MMM::Monitor::Roles;
use base 'Class::Singleton';

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);

our $VERSION = '0.01';

=head1 NAME

MMM::Monitor::Roles - holds information for all roles

=cut

sub _new_instance($) {
	my $class = shift;

	my $self = {};

	# create list of roles - each role will be orphaned by default
	foreach my $role (keys(%{$main::config->{role}})) {
		my $role_info = $main::config->{role}->{$role};
		my $ips = {};
		foreach my $ip (@{$role_info->{ips}}) {
			$ips->{$ip} = { 'assigned_to'	=> '' }
		}
		$self->{$role} = {
			mode	=> $role_info->{mode},
			hosts	=> $role_info->{hosts},
			ips		=> $ips
		};
	}

	return bless $self, $class; 
}

=over 4

=item assign($role, $host)

Assign role $role to host $host

=cut

sub assign($$$) {
	my $self	= shift;
	my $role	= shift;
	my $host	= shift;

	LOGDIE "Can't assign role '$role' - no host given" unless (defined($host));

	# Check if the ip is still configured for this role
	unless (defined($self->{$role->name}->{ips}->{$role->ip})) {
		WARN sprintf("Detected configuration change: ip '%s' was removed from role '%s'", $role->ip, $role->name);
		return;
	}
	INFO sprintf("Adding role '%s' with ip '%s' to host '%s'", $role->name, $role->ip, $host);

	$self->{$role->name}->{ips}->{$role->ip}->{assigned_to} = $host;
}


=item get_host_roles($host)

Get all roles assigned to host $host

=cut

sub get_host_roles($$) {
	my $self	= shift;
	my $host	= shift;

	return () unless (defined($host));

	my @roles	= ();
	foreach my $role (keys(%$self)) {
		my $role_info = $self->{$role};
		foreach my $ip (keys(%{$role_info->{ips}})) {
			my $ip_info = $role_info->{ips}->{$ip};
			next unless ($ip_info->{assigned_to} eq $host);
			push(@roles, new MMM::Monitor::Role::(name => $role, ip => $ip));
		}
	}
	return @roles;
}


=item count_host_roles($host)

Count all roles assigned to host $host

=cut

sub count_host_roles($$) {
	my $self	= shift;
	my $host	= shift;

	return 0 unless (defined($host));

	my $cnt	= 0;
	foreach my $role (keys(%$self)) {
		my $role_info = $self->{$role};
		foreach my $ip (keys(%{$role_info->{ips}})) {
			my $ip_info = $role_info->{ips}->{$ip};
			$cnt++ if ($ip_info->{assigned_to} eq $host);
		}
	}
	return $cnt;
}


=item get_active_master

Get the host with the active master-role

=cut

sub get_active_master($) {
	my $self	= shift;

	my $role = $self->{$main::config->{active_master_role}};
	return '' unless $role;

	my @ips = keys( %{ $role->{ips} } );
	return $role->{ips}->{$ips[0]}->{assigned_to};
}


=item get_exclusive_role_owner($role)

Get the host which has the exclusive role $role assigned

=cut

sub get_exclusive_role_owner($$) {
	my $self	= shift;
	my $role	= shift;

	my $role_info = $self->{$role};
	return '' unless $role_info;

	my @ips = keys( %{ $role_info->{ips} } );
	return $role_info->{ips}->{$ips[0]}->{assigned_to};
}


=item clear_host_roles($host)

Remove all roles from host $host.

=cut

sub clear_host_roles($$) {
	my $self	= shift;
	my $host	= shift;

	INFO "Removing all roles from host '$host':";

	my $orphaned_master_role = 0;
	foreach my $role (keys(%$self)) {
		my $role_info = $self->{$role};
		foreach my $ip (keys(%{$role_info->{ips}})) {
			my $ip_info = $role_info->{ips}->{$ip};
			next unless ($ip_info->{assigned_to} eq $host);
			INFO "    Removed role '$role($ip)' from host '$host'";
			$ip_info->{assigned_to} = '';
			$orphaned_master_role = 1 if ($role eq $main::config->{active_master_role});
		}
	}
	return $orphaned_master_role;
}


=item find_eligible_host($role)

find host which can take over the role $role

=cut

sub find_eligible_host($$) {
	my $self	= shift;
	my $role	= shift;

	my $min_host	= '';
	my $min_count	= 0;

	my $agents = MMM::Monitor::Agents->instance();

	foreach my $host ( @{ $self->{$role}->{hosts} } ) {
		next unless ($agents->{$host}->state eq 'ONLINE');
		my $cnt = $self->count_host_roles($host);
		next unless ($cnt < $min_count || $min_host eq '');
		$min_host	= $host;
		$min_count	= $cnt;
	}
	
	return $min_host;
}


=item find_eligible_hosts($role)

find all hosts which can take over the role $role

=cut

sub find_eligible_hosts($$) {
	my $self	= shift;
	my $role	= shift;

	my $hosts	= {};

	my $agents = MMM::Monitor::Agents->instance();

	foreach my $host ( @{ $self->{$role}->{hosts} } ) {
		next unless ($agents->{$host}->state eq 'ONLINE');
		my $cnt = $self->count_host_roles($host);
		$hosts->{$host} = $cnt;
	}
	
	return $hosts;
}


sub process_orphans($) {
	my $self	= shift;
	
	foreach my $role (keys(%$self)) {
		my $role_info = $self->{$role};

		foreach my $ip (keys(%{$role_info->{ips}})) {
			my $ip_info = $role_info->{ips}->{$ip};
			next unless ($ip_info->{assigned_to} eq '');

			# Find host which can take over the role - skip if none found
			my $host = $self->find_eligible_host($role);
			last unless ($host);
			
			# Assign this ip to host
			$ip_info->{assigned_to} = $host;
			INFO "Orphaned role '$role($ip)' has been assigned to '$host'";
		}
	}
}


sub balance($) {
	my $self	= shift;
	
	foreach my $role (keys(%$self)) {
		my $role_info = $self->{$role};

		next unless ($role_info->{mode} eq 'balanced');

		my $hosts = $self->find_eligible_hosts($role);
		next if (scalar(keys(%$hosts)) < 2);

		while (1) {
			my $max_host = '';
			my $min_host = '';
			foreach my $host (keys(%$hosts)) {
				$max_host = $host if ($max_host eq '' || $hosts->{$host} > $hosts->{$max_host});
				$min_host = $host if ($min_host eq '' || $hosts->{$host} < $hosts->{$min_host});
			}
			
			if ($hosts->{$max_host} - $hosts->{$min_host} < 2) {
				last;
			}
			
			$self->move_one_ip($role, $max_host, $min_host);
			$hosts->{$max_host}--;
			$hosts->{$min_host}++;
		}
	}
}

sub move_one_ip($$$) {
	my $self	= shift;
	my $role	= shift;
	my $host1	= shift;
	my $host2	= shift;
	
	foreach my $ip (keys(%{$self->{$role}->{ips}})) {
		my $ip_info = $self->{$role}->{ips}->{$ip};
		next unless ($ip_info->{assigned_to} eq $host1);

		INFO sprintf("Moving role '$role' with ip '$ip' from host '$host1' to host '$host2'", $role, $ip, $host1);
		$ip_info->{assigned_to} = $host2;
		return;
	}
}

sub find_by_ip($$) {
	my $self	= shift;
	my $ip		= shift;

	foreach my $role (keys(%$self)) {
		return $role if (defined($self->{$role}->{ips}->{$ip}));
	}
	
	return undef;
}
sub set_role($$$$) {
	my $self	= shift;
	my $role	= shift;
	my $ip		= shift;
	my $host	= shift;

	# XXX no checks here - caller should check if:
	# - role is valid
	# - ip is valid
	# - host is valid
	# - host may handle role
	$self->{$role}->{ips}->{$ip}->{assigned_to} = $host;
}

sub exists($$) {
	my $self	= shift;
	my $role	= shift;
	return defined($self->{$role});
}

sub is_exclusive($$) {
	my $self	= shift;
	my $role	= shift;
	return 0 unless defined($self->{$role});
	return ($self->{$role}->{mode} eq 'exclusive');
}

sub get_valid_hosts($$) {
	my $self	= shift;
	my $role	= shift;
	return () unless defined($self->{$role});
	return $self->{$role}->{hosts};
}

sub can_handle($$) {
	my $self	= shift;
	my $role	= shift;
	my $host	= shift;
	return 0 unless defined($self->{$role});
	return grep({$_ eq $host} @{$self->{$role}->{hosts}});
}

sub is_active_master_role($$) {
	my $self	= shift;
	my $role	= shift;
	
	return ($role eq $main::config->{active_master_role});
}

1;
