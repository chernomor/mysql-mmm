package MMM::Agent::Role;

use strict;
use warnings;

our $VERSION = '0.01';

use Class::Struct;

use overload
	'==' => \&is_equal_full,
	'eq' => \&is_equal_name,
	'!=' => sub { return !MMM::Agent::Role::is_equal_full($_[0], $_[1]); },
	'ne' => sub { return !MMM::Agent::Role::is_equal_name($_[0], $_[1]); };
		

struct 'MMM::Agent::Role' => {
	name	=> '$',
	ip		=> '$',
};

#-------------------------------------------------------------------------------
sub check($) {
	my $self = shift;

	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::allow_write(
			$main::agent->ip,
			$main::agent->mysql_port,
			$main::agent->mysql_user,
			$main::agent->mysql_password
		);
	}

	MMM::Agent::Helpers::check_ip($self->ip, $main::agent->interface);
}

#-------------------------------------------------------------------------------
sub add($) {
	my $self = shift;
	
	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::sync_with_master();
		MMM::Agent::Helpers::allow_write(
			$main::agent->ip,
			$main::agent->mysql_port,
			$main::agent->mysql_user,
			$main::agent->mysql_password
		);
	}

	MMM::Agent::Helpers::check_ip($self->ip, $main::agent->interface);
}

#-------------------------------------------------------------------------------
sub del($) {
	my $self = shift;
	
	MMM::Agent::Helpers::clear_ip($self->ip, $main::agent->interface);

	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::deny_write(
			$main::agent->ip,
			$main::agent->mysql_port,
			$main::agent->mysql_user,
			$main::agent->mysql_password
		);
	}
}


#-------------------------------------------------------------------------------
# NOTE: takes a role object as param
sub is_equal_full($$) {
	my $self	= shift;
	my $other	= shift;
	
	return 0 if ($self->name ne $other->name);
	return 0 if ($self->ip   ne $other->ip);
	return 1;
}

#-------------------------------------------------------------------------------
# NOTE: takes a role object as param
sub is_equal_name($$) {
	my $self	= shift;
	my $other	= shift;
	
	return ($self->name eq $other->name);
}

1;
