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

sub send_command($$@) {
	my $self = shift;
	my $cmd_name = shift;
	my @params = @_;

	$socket = $self->_connect();

	DEBUG "Sending command '$cmd(",  ,")' to $self->{host} ($self->{ip}:$self->{port})";

	my $socket = MMM::Common::Socket::create_sender($self->{ip}, $self->{port}, 10);
	return 0 unless ($socket && $socket->connected);


	print $socket join(':', $cmd, main::MMM_PROTOCOL_VERSION, $host, @params), "\n";
	my $res = <$socket>;
	close($socket);
	
	return $res;
}
