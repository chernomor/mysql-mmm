package MMM::Agent::Helpers::Network;

use strict;
use warnings;
use English qw( OSNAME );

our $VERSION = '0.01';

=head1 NAME

MMM::Agent::Helpers::Network - network related functions for the B<mmmd_agent> helper programs

=cut


=head1 FUNCTIONS

=over 4

=item check_ip($if, $ip)

Check if the IP $ip is configured on interface $if. Returns 0 if not, 1 otherwise.

=cut

sub check_ip($$) {
	my $if = shift;
	my $ip = shift;
	
	my $output;
	if ($OSNAME eq 'linux') {
		$output = `/sbin/ip addr show dev $if`;
	}
	elsif ($OSNAME eq 'solaris') {
		# FIXME $if is not used here
		$output = `/usr/sbin/ifconfig -a | grep inet`;
	}
	else {
		print "ERROR: Unsupported platform!\n";
		exit(1);
	}

	return ($output =~ /$ip/) ? 1 : 0;
}


=item add_ip($if, $ip)

Add IP $ip to the interface $if.

=cut

sub add_ip($$) {
	my $if = shift;
	my $ip = shift;
	
	if ($OSNAME eq 'linux') {
		`/sbin/ip addr add $ip/32 dev $if`;
	}
	elsif ($OSNAME eq 'solaris') {
		`/usr/sbin/ifconfig $if addif $ip`;
		my $logical_if = _solaris_find_logical_if($ip);
		unless ($logical_if) {
			print "ERROR: Can't find logical interface with IP = $ip\n";
			exit(1);
		}
		`/usr/sbin/ifconfig $logical_if up`;
	}
	else {
		print "ERROR: Unsupported platform!\n";
		exit(1);
	}
}


=item clear_ip($if, $ip)

Remove the IP $ip from the interface $if.

=cut

sub clear_ip($$) {
	my $if = shift;
	my $ip = shift;
	
	if ($OSNAME eq 'linux') {
		`/sbin/ip addr del $ip/32 dev $if`;
	}
	elsif ($OSNAME eq 'solaris') {
		`/usr/sbin/ifconfig $if removeif $ip`;
	}
	else {
		print "ERROR: Unsupported platform!\n";
		exit(1);
	}
}


=item send_arp($if, $ip)

Send arp requests for the IP $ip to the broadcast address on network interface $if.

=cut

sub send_arp($$) {
	my $if = shift;
	my $ip = shift;

	
	if ($OSNAME eq 'linux') {
		# Get path to arping
		my $arp_util = `which arping`;
		chomp($arp_util);

		if ($arp_util eq '') {
			print "ERROR: Could not find arping!\n";
			exit(1);
		}

		# Get broadcast for arping
		my $output = `/sbin/ifconfig $if`;
		$output =~ /Bcast:\s*([\d\.]+)/i;	# TODO error check?
		my $if_bcast = $1;

		# Execute the arping command
		my $arp_param = '';
		# Check parameters for arping
		if (`$arp_util 2>&1` =~ /\[ -S <host\/ip> \]/) {
			$arp_param = "-i $if -S $ip";
		}
		elsif (`$arp_util 2>&1` =~ /\[-s source\]/) {
			$arp_param = "-I $if -s $ip";
		} else {
			print "ERROR: Unknown arping version!\n";
			exit(1);
		}
		`$arp_util -c 1 $arp_param $if_bcast`
	}
	elsif ($OSNAME eq 'solaris') {
		# Get params for send_arp
		my $ipaddr = `/usr/sbin/ifconfig $if`;

		# Get broadcast address and netmask
		$ipaddr =~ /netmask\s*([0-9a-f]+)\s*broadcast\s*([\d\.]+)/i;
		my $if_bcast = $1;
		my $if_mask = $2;
		`$main::SELF_DIR/bin/sys/send_arp -i 100 -r 5 -p /tmp/send_arp $if $ip auto $if_bcast $if_mask`;
	}
	else {
		print "ERROR: Unsupported platform!\n";
		exit(1);
	}
}

#-------------------------------------------------------------------------------
sub _solaris_find_logical_if($) {
	my $ip = shift;
	my $ifconfig = `/usr/sbin/ifconfig -a`;
	$ifconfig =~ s/\n/ /g;

	while ($ifconfig =~ s/([a-z0-9\:]+)(\:\s+.*?)inet\s*([0-9\.]+)//) {
		return $1 if ($3 eq $ip);
	}
	return undef;
}
