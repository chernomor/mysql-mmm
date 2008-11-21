package MMM::Monitor;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use Thread::Queue;

our $VERSION = '0.01';

use Class::Struct;

struct 'MMM::Monitor' => {
	checker_queue			=> 'Thread::Queue',
	checks_status		=> 'MMM::Monitor::ChecksStatus',
	servers_status		=> 'MMM::Monitor::ServersStatus',
	roles				=> '@',

	protocol_version	=> '$'
};

sub init($) {
	my $self = shift;
	$self->checks_status(new MMM::Monitor::ChecksStatus::);
	$self->checker_queue(new Thread::Queue::);
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

1;

# MMM::Monitor::ChecksStatus setResult MMM::Monitor::CheckResult
