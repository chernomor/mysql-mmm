package MMM::Agent::Helpers::Actions;

use strict;
use warnings;

our $VERSION = '0.01';

use DBI;

#-------------------------------------------------------------------------------
sub check_ip($$) {
	my $if	= shift;
	my $ip	= shift;
	
	if (MMM::Agent::Helpers::Network::check_ip($if, $ip)) {
		print "OK: IP address is configured";
		exit(0);
	}

	MMM::Agent::Helpers::Network::add_ip($if, $ip);
	MMM::Agent::Helpers::Network::send_arp($if, $ip);
	exit(0);
}

#-------------------------------------------------------------------------------
sub clear_ip($$) {
	my $if	= shift;
	my $ip	= shift;
	
	if (!MMM::Agent::Helpers::Network::check_ip($if, $ip)) {
		print "OK: IP address is not configured";
		exit(0);
	}

	MMM::Agent::Helpers::Network::clear_ip($if, $ip);
	exit(0);
}

#-------------------------------------------------------------------------------
sub mysql_allow_write($$$$) {
	my $host			= shift;
	my $port			= shift;
	my $user			= shift;
	my $password		= shift;

	print _mysql_set_read_only(0, $host, $port, $user, $password);

	exit(0);
}

#-------------------------------------------------------------------------------
sub mysql_deny_write($$$$) {
	my $host			= shift;
	my $port			= shift;
	my $user			= shift;
	my $password		= shift;

	print _mysql_set_read_only(1, $host, $port, $user, $password);

	exit(0);
}

sub _mysql_set_read_only($$$$$) {
	my $read_only_new	= shift;
	my $host			= shift;
	my $port			= shift;
	my $user			= shift;
	my $password		= shift;

	# connect to server
	my $dsn = "DBI:mysql:host=$host;port=$port";
	my $dbh = DBI->connect($dsn, $user, $password, { PrintError => 0 });
	return "ERROR: Can't connect to MySQL (host = $host:$port, user = $user)!" unless ($dbh);
	
	# check old read_only state
	(my $read_only_old) = $dbh->selectrow_array(q{select @@read_only});
	return "ERROR: SQL Query Error: " . $dbh->errstr unless (defined $read_only_old);
	return "OK" if ($read_only_old == $read_only_new);

	my $sth = $dbh->prepare("set global read_only=$read_only_new");
	my $res = $sth->execute;
	return "ERROR: SQL Query Error: " . $dbh->errstr unless($res);
	$sth->finish;
	
	$dbh->disconnect();
	$dbh = undef;
	
	return "OK";
}
1;
