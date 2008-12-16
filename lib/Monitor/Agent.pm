package MMM::Monitor::Agent;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);

our $VERSION = '0.01';

use Class::Struct;


struct 'MMM::Monitor::Agent' => {
	host		=> '$',
	mode		=> '$',
	ip			=> '$',
	port		=> '$',

	state		=> '$',
	roles		=> '@',
	uptime		=> '$',
	last_uptime	=> '$'
};

sub _send_command {
	my $self	= shift;
	my $cmd		= shift;
	my @params	= @_;


	my $checks_status = MMM::Monitor::ChecksStatus->instance();
	unless ($checks_status->ping($self->host) && $checks_status->mysql($self->host)) {
		return 0;
	}

	DEBUG sprintf("Sending command '$cmd(%s)' to %s (%s:%s)", join(', ', @params), $self->host, $self->ip, $self->port);

	my $socket = MMM::Common::Socket::create_sender($self->ip, $self->port, 10);
	return 0 unless ($socket && $socket->connected);


	print $socket join('|', $cmd, main::MMM_PROTOCOL_VERSION, $self->host, @params), "\n";

	my $res;
READ: {
	$res = <$socket>;
	redo READ if !$res && $!{EINTR};
}
	close($socket);

	return 0 unless (defined($res));

	DEBUG "Received Answer: $res";

	if ($res =~ /(.*)\|UP:(.*)/) {
		$res = $1;
		my $uptime = $2;
		$self->uptime($uptime);
		$self->last_uptime($uptime) if ($self->state eq 'ONLINE');
	}
	
	return $res;
}

sub cmd_ping($) {
	my $self	= shift;
	return $self->_send_command('PING');
}

sub cmd_set_status($$) {
	my $self	= shift;
	my $master	= shift;

	return $self->_send_command('SET_STATUS', $self->state, join(',', sort(@{$self->roles})), $master);
}

sub cmd_get_agent_status($) {
	my $self	= shift;
	return $self->_send_command('GET_AGENT_STATUS');
}

sub cmd_get_system_status($) {
	my $self	= shift;
	return $self->_send_command('GET_SYSTEM_STATUS');
}

1;
