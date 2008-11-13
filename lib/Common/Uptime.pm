package MMM::Common::Uptime;

use strict;
use warnings;
use English qw( OSNAME );
use Log::Log4perl qw(:easy);

require Exporter;
our @ISA = qw( Exporter );
our @EXPORT_OK = qw( uptime );

our $VERSION = '0.01';

# FIXME Solaris

if ($OSNAME eq 'linux') {
	use constant UPTIME => "/proc/uptime";
}
else {
	LOGDIE "Unsupported platform - can't get uptime!";
}

sub uptime {
	my $log = get_logger();

	if ($OSNAME eq 'linux') {

		TRACE "Fetching uptime from ", UPTIME;
		open(FILE, UPTIME) || LOGDIE "Unable to get uptime from ", UPTIME;
		my $line = <FILE>;
		my ($uptime, $idle) = split(/\s+/, $line);
		close(FILE);

		TRACE "Uptime is ", $uptime;
		return $uptime;
	}

	$log->logdie("Unsupported platform - can't get uptime!");
}

1;
