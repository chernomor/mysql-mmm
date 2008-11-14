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

Check if the IP $ip is configured on interface $if. If not, configure it and
send arp requests to notify other hosts.

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

Remove the IP address $ip from interface $if.

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

Allow writes on local MySQL server. Sets global read_only to 0.

=cut

sub mysql_allow_write() {
	print _mysql_set_read_only(0);
	exit(0);
}


=item mysql_deny_write( )

Deny writes on local MySQL server. Sets global read_only to 1.

=cut

sub mysql_deny_write() {
	print _mysql_set_read_only(1);
	exit(0);
}


sub _mysql_set_read_only($) {
	my $read_only_new	= shift;
	my ($host, $port, $user, $password)	= _get_connection_info();
	return "ERROR: No connection info" unless defined($host);

	# connect to server
	my $dbh = _mysql_connect($host, $port, $user, $password);
	return "ERROR: Can't connect to MySQL (host = $host:$port, user = $user)!" unless ($dbh);
	
	# check old read_only state
	(my $read_only_old) = $dbh->selectrow_array('select @@read_only');
	return "ERROR: SQL Query Error: " . $dbh->errstr unless (defined $read_only_old);
	return "OK" if ($read_only_old == $read_only_new);

	my $res = $dbh->do("set global read_only=$read_only_new");
	return "ERROR: SQL Query Error: " . $dbh->errstr unless($res);
	
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
	my $dbh = _mysql_connect($host, $port, $user, $password);
	return "ERROR: Can't connect to MySQL (host = $host:$port, user = $user)!" unless ($dbh);
	
	# execute query
	my $res = $dbh->do($query);
	return "ERROR: SQL Query Error: " . $dbh->errstr unless($res);
	return 'OK';
}


=item sync_with_master( )

Try to sync up a (soon active) master with his peer (old active master) when the I<active_writer_role> is moved. If the peer is reachable it syncs with the master log. If not reachable, syncs with the relay log.

=cut

sub sync_with_master() {

	my ($this_host, $this_port, $this_user, $this_password)	= _get_connection_info();
	return "ERROR: No local connection info" unless defined($this_host);

	my $peer = $main::config->{host}->{$main::config->{this}}->{peer};
	return "ERROR No peer defined" unless defined($peer);

	my ($peer_host, $peer_port, $peer_user, $peer_password)	= _get_connection_info($peer);
	return "ERROR: No peer connection info" unless defined($peer_host);

	# Connect to local server
	my $this_dbh = _mysql_connect($this_host, $this_port, $this_user, $this_password);
	return "ERROR: Can't connect to MySQL (host = $this_host:$this_port, user = $this_user)!" unless ($this_dbh);

	# Connect to peer
	my $peer_dbh = _mysql_connect($peer_host, $peer_port, $peer_user, $peer_password);
	
	# Determine wait log and wait pos
	my $wait_log;
	my $wait_pos;
	if ($peer_dbh) {
		my $master_status = $peer_dbh->selectrow_hashref('SHOW MASTER STATUS');
		if (defined($master_status)) {
			$wait_log = $master_status->{File};
			$wait_pos = $master_status->{Position};
		}
		$peer_dbh->disconnect;
	} 
	unless (defined($wait_log)) {
		my $slave_status = $this_dbh->selectrow_hashref('SHOW SLAVE STATUS');
		return "ERROR: SQL Query Error: " . $this_dbh->errstr unless defined($slave_status);
		$wait_log = $slave_status->{Master_Log_File};
		$wait_pos = $slave_status->{Read_Master_Log_Pos};
	}

	# Sync with logs
	my $res = $this_dbh->do("SELECT MASTER_POS_WAIT('$wait_log', $wait_pos)");
	return "ERROR: SQL Query Error: " . $this_dbh->errstr unless($res);
	
	return 'OK';
	
}



=item set_active_master($new_master)

Try to catch up with the old master as far as possible and change the master to the new host.
(Syncs to the master log if the old master is reachable. Otherwise syncs to the relay log.)

=cut

sub set_active_master($) {
	my $new_peer = shift;
	return "ERROR: Name of new master is missing\n" unless (defined($new_peer));

	# Get local connection info
	my ($this_host, $this_port, $this_user, $this_password)	= _get_connection_info();
	return "ERROR: No connection info for local host '$this_host'" unless defined($this_host);
	
	# Get connection info for new peer
	my ($new_peer_host, $new_peer_port, $new_peer_user, $new_peer_password)	= _get_connection_info($new_peer);
	return "ERROR: No connection info for new peer '$new_peer'" unless defined($new_peer_host);
	
	# Connect to local server
	my $this_dbh = _mysql_connect($this_host, $this_port, $this_user, $this_password);
	return "ERROR: Can't connect to MySQL (host = $this_host:$this_port, user = $this_user)!" unless ($this_dbh);

	# Get slave info
	my $slave_status = $this_dbh->selectrow_hashref('SHOW SLAVE STATUS');
	return "ERROR: SQL Query Error: " . $this_dbh->errstr unless defined($slave_status);

	my $wait_log	= $slave_status->{Master_Log_File};
	my $wait_pos	= $slave_status->{Read_Master_Log_Pos};

	my $old_peer_ip	= $slave_status->{Master_Host};
	return "ERROR: No ip for old peer" unless ($old_peer_ip);

	# Get connection info for old peer
	my $old_peer = _find_host_by_ip($old_peer_ip);
	return 'ERROR: Invalid master host in show slave status' unless ($old_peer);

	return 'OK: We are already a slave of the new master.' if ($old_peer eq $new_peer);
	
	my ($old_peer_host, $old_peer_port, $old_peer_user, $old_peer_password)	= _get_connection_info($old_peer);
	return "ERROR: No connection info for new peer '$old_peer'" unless defined($old_peer_host);
	
	my $old_peer_dbh = _mysql_connect($old_peer_host, $old_peer_port, $old_peer_user, $old_peer_password);
	if ($old_peer_dbh) {
		my $old_master_status = $old_peer_dbh->selectrow_hashref('SHOW MASTER STATUS');
		if (defined($old_master_status)) {
			$wait_log = $old_master_status->{File};
			$wait_pos = $old_master_status->{Position};
		}
		$old_peer_dbh->disconnect;
	}

	# Sync with logs
	my $res = $this_dbh->do($this_dbh, "SELECT MASTER_POS_WAIT('$wait_log', $wait_pos)");
	return "ERROR: SQL Query Error: " . $this_dbh->errstr unless($res);
	
	# Connect to new peer
	my $new_peer_dbh = _mysql_connect($new_peer_host, $new_peer_port, $new_peer_user, $new_peer_password);
	return "ERROR: Can't connect to MySQL (host = $new_peer_host:$new_peer_port, user = $new_peer_user)!" unless ($new_peer_dbh);

	# Get log position of new master
	my $new_master_status = $new_peer_dbh->selectrow_hashref('SHOW MASTER STATUS');
	return "ERROR: SQL Query Error: " . $this_dbh->errstr unless($new_master_status);

	my $master_log = $new_master_status->{File};
	my $master_pos = $new_master_status->{Position};

	$new_peer_dbh->disconnect;

	# Get replication credentials
	my ($repl_user, $repl_password) = _get_replication_credentials($new_peer);

	# Change master
	my $sql = "CHANGE MASTER TO " .
			  "  MASTER_HOST='$new_peer_host'," .
			  "  MASTER_PORT=$new_peer_port," .
			  "  MASTER_USER='$repl_user'," .
			  "  MASTER_PASSWORD='$repl_password'," .
			  "  MASTER_LOG_FILE='$master_log'," .
			  "  MASTER_LOG_POS=$master_pos";
	$res = $this_dbh->do($sql);
	return "ERROR: SQL Query Error: " . $this_dbh->errstr unless($res);

	# Start slave
	$res = $this_dbh->do('START SLAVE');
	return "ERROR: SQL Query Error: " . $this_dbh->errstr unless($res);

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

sub _mysql_connect($$$$) {
	my ($host, $port, $user, $password)	= @_;
	my $dsn = "DBI:mysql:host=$host;port=$port";
	return DBI->connect($dsn, $user, $password, { PrintError => 0 });
}

sub _find_host_by_ip($) {
	my $ip = shift;
	return undef unless ($ip);

	unless (defined($main::config)) {
		print "ERROR: No config present\n";
		exit(0);
	}

    my $hosts = $main::config->{host};
    foreach my $host (keys(%$hosts)) {
        return $host if ($hosts->{$host}->{ip} eq $ip);
    }
    
    return undef;
}

sub _get_replication_credentials($) {
	my $host = shift;
	return undef unless ($host);

	unless (defined($main::config)) {
		print "ERROR: No config present\n";
		exit(0);
	}

 	unless (defined($main::config->{host}->{$host})) {
		print "ERROR: No config present\n";
		exit(0);
	}

	return (
		$main::config->{host}->{$host}->{replication_user},
		$main::config->{host}->{$host}->{replication_password},
	);
}

1;
