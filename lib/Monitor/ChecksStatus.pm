package MMM::Monitor::ChecksStatus;

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy);

our $VERSION = '0.01';

sub new($) {
	my $class = shift;

	my $data = {};

	my @checks		= keys(%{$main::config->{check}});
	my @hosts		= keys(%{$main::config->{host}});

	foreach my $host_name (@hosts) {
		$data->{$host_name} = {};
	}

	# Perform initial checks
	INFO 'Performing initial checks...';
	foreach my $check_name (@checks) {

		# Spawn checker
		my $checker = new MMM::Monitor::Checker::($check_name);

		# Check all hosts
		foreach my $host_name (@hosts) {
			DEBUG "Trying initial check '$check_name' on host '$host_name'";
			my $res = $checker->check($host_name);
			DEBUG "$check_name($host_name) = '$res'";
			$data->{$host_name}->{$check_name} = ($res =~ /^OK/)? 1 : 0;
		}

		# Shutdown checker
		$checker->shutdown();
	}
	return bless $data, $class; 
}


=item handle_result(MMM::Monitor::CheckResult $result)

handle the results of a check and change state accordingly

=cut

sub handle_result($$) {
	my $self = shift;
	my $result = shift;

	$self->{$result->{host}}->{$result->{check}} = $result->{result};
}

1;
