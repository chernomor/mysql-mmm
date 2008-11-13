package MMM::Agent;

use strict;
use warnings;

our $VERSION = '0.01';

use Class::Struct;

struct 'MMM::Agent' => {
	name			=> '$',
	ip				=> '$',
	port			=> '$',
	interface		=> '$',
	mysql_port		=> '$',
	mysql_user		=> '$',
	mysql_password	=> '$',
	writer_role		=> '$',
	roles			=> '@'
};

sub from_config($%) {
	my $self	= shift;
	my $config	= shift;

	my $host = $config->{host}->{$config->{this}};

	$self->name				($config->{this});
	$self->ip				($host->{ip});
	$self->port				($host->{agent_port});
	$self->interface		($host->{cluster_interface});
	$self->mysql_port		($host->{mysql_port});
	$self->mysql_user		($host->{agent_user});
	$self->mysql_password	($host->{agent_password});
	$self->writer_role		($config->{active_writer_role});
}

# NOTE: takes a role object as param
sub has_role($$) {
	my $self = shift;
	my $role = shift;
	
	foreach my $a_role ( @{ $self->roles } ) {
		return 1 if ($a_role == $role);
	}
	return 0;
}

1;
