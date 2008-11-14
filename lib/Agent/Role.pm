package MMM::Agent::Role;

use strict;
use warnings;

our $VERSION = '0.01';

use Class::Struct;

use overload
	'==' => \&is_equal_full,
	'eq' => \&is_equal_name,
	'!=' => sub { return !MMM::Agent::Role::is_equal_full($_[0], $_[1]); },
	'ne' => sub { return !MMM::Agent::Role::is_equal_name($_[0], $_[1]); },
	'""' => \&to_string;
		

struct 'MMM::Agent::Role' => {
	name	=> '$',
	ip		=> '$',
};

#-------------------------------------------------------------------------------
sub check($) {
	my $self = shift;

	# TODO debug output
	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::allow_write();
	}

	MMM::Agent::Helpers::check_ip($main::agent->interface, $self->ip);
}

#-------------------------------------------------------------------------------
sub add($) {
	my $self = shift;
	
	# TODO debug output
	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::sync_with_master();
		MMM::Agent::Helpers::allow_write();
	}

	MMM::Agent::Helpers::check_ip($main::agent->interface, $self->ip);
}

#-------------------------------------------------------------------------------
sub del($) {
	my $self = shift;
	
	# TODO debug output
	MMM::Agent::Helpers::clear_ip($main::agent->interface, $self->ip);

	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::deny_write();
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

sub to_string($) {
	my $self	= shift;
	return sprintf('%s(%s;)', $self->name, $self->ip);
}

sub from_string($$) {
	my $self	= shift;
	my $string	= shift;

	if (my ($name, $ip) = $string =~ /(.*)\((.*);.*\)/) {
		$self->name($name);
		$self->ip  ($ip);
		return 1;
	}
	return 0;
}

1;
