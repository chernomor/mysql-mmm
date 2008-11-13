#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw(:easy :no_extra_logdie_message);
Log::Log4perl->easy_init($WARN);

use Test::More tests => 1;

require '../Uptime.pm';
import MMM::Common::Uptime qw( uptime );

isnt(uptime(), 0, 'Non-zero uptime');


