package MMM::Monitor;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use Thread::Queue;

our $VERSION = '0.01';

use Class::Struct;

struct 'MMM::Monitor' => {
	checker_queue		=> 'Thread::Queue',
	checks_status		=> 'MMM::Monitor::ChecksStatus',
	servers_status		=> 'MMM::Monitor::ServersStatus',
	roles				=> '@'
};

sub init($) {
	my $self = shift;
	$self->checks_status(MMM::Monitor::ChecksStatus->instance());
	$self->checker_queue(new Thread::Queue::);
	$self->roles(MMM::Monitor::Roles->instance());
}

sub main($) {
	my $self	= shift;

	# Delay execution so we can reap all childs before spawning the checker threads.
	# This prevents a segfault if a SIGCHLD arrives during creation of a thread.
	sleep(3);

	# Spawn checker threads
	my @checks	= keys(%{$main::config->{check}});
	my @threads;
	foreach my $check_name (@checks) {
		push(@threads, new threads(\&MMM::Monitor::Checker::main, $check_name, $self->checker_queue));
	}
	
	while (!$main::shutdown) {
		# Process check results from checker threads
		$self->_process_check_results();
		$self->_check_server_states();
		$self->_distribute_roles();
	}

	foreach my $thread (@threads) {
		$thread->join();
	}
}


=item _process_check_results

Process the results of the checker thread and change checks_status accordingly. Reads from check_queue.

=cut

sub _process_check_results($) {
	my $self = shift;

	my $cnt = 0;
	while (my $result = $self->checker_queue->dequeue_nb) {
		$cnt++ if $self->checks_status->handle_result($result);
	}
	return $cnt;
}


sub _distribute_roles($) {
	my $self = shift;


	my $old_active_master = $self->roles->get_active_master();
	
	# Process orphaned roles
	$self->roles->process_orphans();

	# Balance roles
	$self->roles->balance();

	my $new_active_master = $self->roles->get_active_master();

	# notify slaves first, if master host has changed
	unless ($new_active_master eq $old_active_master) {
		$self->_notify_slaves($new_active_master);
	}
}

sub _notify_slaves($$) {
	my $self		= shift;
	my $new_master	= shift;

	foreach my $host (keys(%{$main::config->{host}}) {
		next unless ($main::config->{host}->{$host}->{mode} eq 'slave');
	}
}

sub set_agent_status($$$) {
	my $self		= shift;
	my $host		= shift;
	my $new_master	= shift;

	my $roles		= sort(@{$self->roles->get_host_roles($host)});

	unless ($self->servers_status->get_host_status($host) eq 'HARD_OFFLINE') {
		my $roles_str	= join(',', @$roles);
		my $agent       = new MMM::Monitor::Agent::($host);
		my $res = $agent->send_command('SET_STATUS', $state, $roles, $new_master);
	}

	$self->servers_status->set_host_roles($host, $roles);
}

1;

