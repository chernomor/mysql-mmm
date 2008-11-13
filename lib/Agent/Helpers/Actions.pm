package MMM::Agent::Helpers::Actions;

use strict;
use warnings;

our $VERSION = '0.01';

=head1 NAME

MMM::Agent::Helpers::Actions - functions for the B<mmmd_agent> helper programs

=cut

use DBI;


=head1 FUNCTIONS

=over 4

=item check_ip($if, $ip)

TODO

=cut

sub check_ip($$) {
	my $if	= shift;
	my $ip	= shift;
	
	if (MMM::Agent::Helpers::Network::check_ip($if, $ip)) {
		print 'OK: IP address is configured';
		exit(0);
	}

	MMM::Agent::Helpers::Network::add_ip($if, $ip);
	MMM::Agent::Helpers::Network::send_arp($if, $ip);
	exit(0);
}


=item clear_ip($if, $ip)

TODO

=cut

sub clear_ip($$) {
	my $if	= shift;
	my $ip	= shift;
	
	if (!MMM::Agent::Helpers::Network::check_ip($if, $ip)) {
		print 'OK: IP address is not configured';
		exit(0);
	}

	MMM::Agent::Helpers::Network::clear_ip($if, $ip);
	exit(0);
}


=item mysql_allow_write( )

TODO

=cut

sub mysql_allow_write() {
	print _mysql_set_read_only(0);
	exit(0);
}


=item mysql_deny_write( )

TODO

=cut

sub mysql_deny_write() {
	print _mysql_set_read_only(1);
	exit(0);
}


=item mysql_set_read_only($state)

TODO

=cut

sub _mysql_set_read_only($) {
	my $read_only_new	= shift;
	my ($host, $port, $user, $password)	= _get_connection_info();
	return "ERROR: No connection info" unless defined($host);

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
	
	return 'OK';
}


=item toggle_slave($state)

Toggle slave state. Starts slave if $state != 0. Stops it otherwise.

=cut

sub toggle_slave($) {
	my $state = shift;

	my ($host, $port, $user, $password)	= _get_connection_info();
	return "ERROR: No connection info" unless defined($host);

	my $query = $state ? 'START SLAVE' : 'STOP SLAVE';

    # connect to server
    my $dsn = "DBI:mysql:host=$host;port=$port";
    my $dbh = DBI->connect($dsn, $user, $password, { PrintError => 0 });
    return "ERROR: Can't connect to MySQL (host = $host:$port, user = $user)!" unless ($dbh);
    
	# execute query
    my $sth = $dbh->prepare($query);
    my $res = $sth->execute;
    return "ERROR: SQL Query Error: " . $dbh->errstr unless($res);
    $sth->finish;
    
    $dbh->disconnect();
    $dbh = undef;
    
    return 'OK';
}


=item _get_connection_info([$host])

Get connection info for host $host || local host.

=cut


sub _get_connection_info($) {
	my $host = shift;
	unless (defined($main::config)) {
		print "ERROR: No config present\n";
		exit(0);
	}
	$host = $main::config->{this} unless defined($host);
 	unless (defined($main::config->{host}->{$host})) {
		print "ERROR: No config present\n";
		exit(0);
	}

	return (
		$main::config->{host}->{$host}->{ip},
		$main::config->{host}->{$host}->{mysql_port},
		$main::config->{host}->{$host}->{agent_user},
		$main::config->{host}->{$host}->{agent_password}
	);
}

1;
