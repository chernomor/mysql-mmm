package MMM::Monitor::ServersStatus;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);

sub new($) {
	my $class = shift;
	my $data = {};

	my @hosts		= keys(%{$main::config->{host}});

	foreach my $host_name (@hosts) {
		$data->{$host_name} = {};
	}
	return bless $data, $class;
}

sub save($\%) {
	my $self	= shift;
	my $roles	= shift;
	
	my $filename = $main::config->{monitor}->{status_path};
	my $tempname = $filename . '.tmp';

	open(STATUS, ">" . $tempname) || LOGDIE "Can't open temporary status file '$tempname' for writing!";

	while (my ($server, $status) = each(%$self)) {
		next unless $status;
		printf(STATUS "%s|%s|%s\n", $server, $status->{state}, join(',', sort(@{$status->{roles}})));
	}

	close(STATUS);
	rename($tempname, $filename) || LOGDIE "Can't savely overwrite status file '$filename'!";
}

sub load($) {
	my $self	= shift;

	my $filename = $main::config->{monitor}->{status_path};
	
	open(STATUS, $filename) || return;

	while (my $line = <STATUS>) {
		chomp($line);
		my ($server, $state, $roles) = split(/\|/, $line);
		unless (defined($self->{$server})) {
			WARN "Ignoring saved status information for unknown host '$server'";
			next;
		}

		# Parse roles
		my @saved_roles_arr = sort(split(/\,/, $roles));
		my @saved_roles;
		foreach my $role_str (@saved_roles_arr) {
			my $role = MMM::Monitor::Role->from_string($role_str);
			if (defined($role)) {
				push @saved_roles, $role;
			}
		}

		$self->{$server}->{state} = $state;
		@{$self->{$server}->{roles}} = @saved_roles;
	}
	close(STATUS);
}

# status must contain
#	state
#	roles (array of type MMM::Monitor::Role with to_string operator overloaded)
#	uptime
#	last_uptime

1;
