package MMM::Monitor::Agent;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);

our $VERSION = '0.01';

sub new($$) {
	my $class	= shift;
	my $host	= shift;

	my $self  = {
		host	=> $host,
		ip		=> $main::config->{host}->{$host}->{ip},
		port	=> $main::config->{host}->{$host}->{agent_port}
	};

	return bless $self, $class;
}

sub _send_command {
	my $self = shift;
	my $cmd_name = shift;
	my @params = @_;


	my $checks_status = MMM::Monitor::ChecksStatus->instance();
	unless ($checks_status->{$self->{host}}->{ping} && $checks_status->{$self->{host}}->{mysql}) {
		return 0;
	}

	$socket = $self->_connect();

	DEBUG "Sending command '$cmd(",  ,")' to $self->{host} ($self->{ip}:$self->{port})";

	my $socket = MMM::Common::Socket::create_sender($self->{ip}, $self->{port}, 10);
	return 0 unless ($socket && $socket->connected);


	print $socket join(':', $cmd, main::MMM_PROTOCOL_VERSION, $host, @params), "\n";
	my $res = <$socket>;
	close($socket);
	
	return $res;
}

sub set_status($$$$) {
	my $self	= shift;
	my $state	= shift;
	my $roles	= shift;
	my $master	= shift;

	return $agent->send_command('SET_STATUS', $state, join(',', sort(@$roles)), $master);
}

sub get_agent_status($) {
	my $self	= shift;
	return $agent->send_command('GET_AGENT_STATUS');
}

sub get_system_status($) {
	my $self	= shift;
	return $agent->send_command('GET_SYSTEM_STATUS');
}
