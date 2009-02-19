package MMM::Agent::Role;
use base 'MMM::Common::Role';

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
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

	my $ret;

	if ($self->name eq $main::agent->writer_role) {
		$ret = MMM::Agent::Helpers::allow_write();
		if ($ret !~ /^OK/) {
			FATAL "Couldn't allow writes: $ret";
			return;
		}
	}

	$ret = MMM::Agent::Helpers::configure_ip($main::agent->interface, $self->ip);
	if ($ret !~ /^OK/) {
		FATAL sprintf("Couldn't configure IP '%s' on interface '%s': %s", $self->ip, $main::agent->interface, $ret);
		return;
	}
}

=item add()

Add a role to the local host.

=cut
sub add($) {
	my $self = shift;
	
	my $ret;

	if ($self->name eq $main::agent->writer_role) {
		$ret = MMM::Agent::Helpers::sync_with_master();
		if ($ret !~ /^OK/) {
			FATAL "Couldn't sync with master: $ret";
			return;
		}
		$ret = MMM::Agent::Helpers::allow_write();
		if ($ret !~ /^OK/) {
			FATAL "Couldn't allow writes: $ret";
			return;
		}
	}

	$ret = MMM::Agent::Helpers::configure_ip($main::agent->interface, $self->ip);
	if ($ret !~ /^OK/) {
		FATAL sprintf("Couldn't configure IP '%s' on interface '%s': %s", $self->ip, $main::agent->interface, $ret);
		return;
	}
}

=item del()

Delete a role from the local host.

=cut
sub del($) {
	my $self = shift;

	my $ret;
	
	if ($self->name eq $main::agent->writer_role) {
		$ret = MMM::Agent::Helpers::deny_write();
		if ($ret !~ /^OK/) {
			FATAL "Couldn't deny writes: $ret";
		}
	}

	$ret = MMM::Agent::Helpers::clear_ip($main::agent->interface, $self->ip);
	if ($ret !~ /^OK/) {
		FATAL sprintf("Couldn't clear IP '%s' from interface '%s': %s", $self->ip, $main::agent->interface, $ret);
	}
}

1;
