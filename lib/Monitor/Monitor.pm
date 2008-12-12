package MMM::Monitor;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);
use Thread::Queue;

our $VERSION = '0.01';

use Class::Struct;

sub instance() {
	return $main::monitor;
}

struct 'MMM::Monitor' => {
	checker_queue		=> 'Thread::Queue',
	checks_status		=> 'MMM::Monitor::ChecksStatus',
	command_queue		=> 'Thread::Queue',
	result_queue		=> 'Thread::Queue',
	roles				=> 'MMM::Monitor::Roles',
	servers_status		=> 'MMM::Monitor::ServersStatus',
	passive				=> '$'
};

sub init($) {
	my $self = shift;
	$self->checker_queue(new Thread::Queue::);
	$self->checks_status(MMM::Monitor::ChecksStatus->instance());
	$self->command_queue(new Thread::Queue::);
	$self->result_queue(new Thread::Queue::);
	$self->roles(MMM::Monitor::Roles->instance());
	$self->servers_status(MMM::Monitor::ServersStatus->instance());
	$self->passive(0);
}

sub main($) {
	my $self	= shift;

	# Delay execution so we can reap all childs before spawning the checker threads.
	# This prevents a segfault if a SIGCHLD arrives during creation of a thread.
	sleep(3);

	# Spawn checker threads
	my @checks	= keys(%{$main::config->{check}});
	my @threads;

	push(@threads, new threads(\&MMM::Monitor::NetworkChecker::main));
	push(@threads, new threads(\&MMM::Monitor::Commands::main, $self->result_queue, $self->command_queue));

	foreach my $check_name (@checks) {
		push(@threads, new threads(\&MMM::Monitor::Checker::main, $check_name, $self->checker_queue));
	}
	
	while (!$main::shutdown) {
		$self->_process_check_results();
		$self->_check_server_states();
		$self->_handle_commands();
		$self->_distribute_roles();
		sleep(1);
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

sub _check_server_states($) {
	my $self = shift;
}

sub _distribute_roles($) {
	my $self = shift;

	# Never change roles if we are in PASSIVE mode
	return if ($self->passive);

	my $old_active_master = $self->roles->get_active_master();
	
	# Process orphaned roles
	$self->roles->process_orphans();

	# Balance roles
	$self->roles->balance();

	my $new_active_master = $self->roles->get_active_master();

	# notify slaves first, if master host has changed
	unless ($new_active_master eq $old_active_master) {
		$self->notify_slaves($new_active_master);
	}
}

sub notify_slaves($$) {
	my $self		= shift;
	my $new_master	= shift;

	foreach my $host (keys(%{$main::config->{host}})) {
		next unless ($main::config->{host}->{$host}->{mode} eq 'slave');
		$self->send_agent_status($host);
	}
}

sub send_agent_status($$$) {
	my $self	= shift;
	my $host	= shift;
	my $master	= shift;

	# Never send anything to agents if we are in PASSIVE mode
	return if ($self->passive);

	$master = $self->roles->get_active_master() unless (defined($master));

	my @roles		= sort(@{$self->roles->get_host_roles($host)});
	my $roles_str	= join(',', @roles);
	my $agent       = new MMM::Monitor::Agent::($host);
	my $res = $agent->set_status($self->servers_status->get_host_state($host), @roles, $master);

	$self->servers_status->set_host_roles($host, @roles);
}

sub _handle_commands($) {
	my $self		= shift;
	while (my $cmdline = $self->command_queue->dequeue_nb) {
		my @args	= split(/\s+/, $cmdline);
		my $command	= shift @args;
		my $arg_cnt	= scalar(@args);
		if ($command eq 'ping'			&& $arg_cnt == 0) { $self->result_queue->enqueue(MMM::Monitor::Commands::ping()); }
		if ($command eq 'show'			&& $arg_cnt == 0) { $self->result_queue->enqueue(MMM::Monitor::Commands::show()); }
		if ($command eq 'set_active'	&& $arg_cnt == 0) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_active()); }
		if ($command eq 'set_passive'	&& $arg_cnt == 0) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_passive()); }
		if ($command eq 'move_role'		&& $arg_cnt == 2) { $self->result_queue->enqueue(MMM::Monitor::Commands::move_role($args[0], $args[1])); }
		if ($command eq 'set_ip'		&& $arg_cnt == 2) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_ip($args[0], $args[1])); }
		if ($command eq 'set_online'	&& $arg_cnt == 1) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_online($args[0])); }
		if ($command eq 'set_offline'	&& $arg_cnt == 1) { $self->result_queue->enqueue(MMM::Monitor::Commands::set_offline($args[0])); }
		else { $self->result_queue->enqueue("Invalid command '$cmdline'\n"); }
	}
}

1;

