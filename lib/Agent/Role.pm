package MMM::Agent::Role;

use strict;
use warnings;

our $VERSION = '0.01';
our @ISA = qw(MMM::Common::Role);

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

1;
