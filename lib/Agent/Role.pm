package MMM::Agent::Role;
use base 'MMM::Common::Role';

use strict;
use warnings FATAL => 'all';
use MMM::Agent::Helpers;

our $VERSION = '0.01';

=head1 NAME

MMM::Agent::Role - role class (agent)

=cut


=head1 METHODS

=over 4

=item check()

Check (=assure) that the role is configured on the local host.

=cut
sub check($) {
	my $self = shift;

	# TODO debug output
	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::allow_write();
	}

	MMM::Agent::Helpers::configure_ip($main::agent->interface, $self->ip);
}

=item add()

Add a role to the local host.

=cut
sub add($) {
	my $self = shift;
	
	# TODO debug output
	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::sync_with_master();
		MMM::Agent::Helpers::allow_write();
	}

	MMM::Agent::Helpers::configure_ip($main::agent->interface, $self->ip);
}

=item del()

Delete a role from the local host.

=cut
sub del($) {
	my $self = shift;
	
	# TODO debug output
	MMM::Agent::Helpers::clear_ip($main::agent->interface, $self->ip);

	if ($self->name eq $main::agent->writer_role) {
		MMM::Agent::Helpers::deny_write();
	}
}

1;
