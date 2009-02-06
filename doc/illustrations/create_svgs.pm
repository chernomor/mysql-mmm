#!/usr/bin/env perl
use strict;
use SVG;
use Math::Complex;
use Math::Trig;
use Data::Dumper;

package MMM::SVG::Host;
sub new {
	my $class = shift;
	my $self = bless {@_}, $class;
	$self;
}

sub draw {
	my $self	= shift;
	my $hosts	= shift;
	my $texts	= shift;
	$hosts->rectangle(
		id		=> $self->{id},
		y		=> $self->{y},
		x		=> $self->{x},
		width	=> $self->{width},
		height	=> $self->{height},
		rx		=> 3,
		ry		=> 3,
	);
	$texts->text(
		'font-size' => '16',
		font => 'Verdana',
		fill => 'black',
		x => $self->center_x,
		y => $self->center_y + 5,
		'text-anchor' => 'middle'
	)->cdata($self->{text});
}

sub center_x {
	my $self	= shift;
	return int($self->{x} + $self->{width} / 2);
}

sub center_y {
	my $self	= shift;
	return int($self->{y} + $self->{height} / 2);
}

sub connector {
	my $self	= shift;
	my $side	= shift;
	return ($self->{x}                           , int($self->{y} + $self->{height} / 2))	if ($side eq 'l');
	return ($self->{x} + $self->{width}          , int($self->{y} + $self->{height} / 2))	if ($side eq 'r');
	return (int($self->{x} + $self->{width}  / 2), $self->{y})								if ($side eq 't');
	return (int($self->{x} + $self->{width}  / 2), $self->{y} + $self->{height})			if ($side eq 'b');
}

package MMM::SVG::Line;
sub new {
	my $class = shift;
	my $self = bless {@_}, $class;
	$self;
}


package main;

my $svg = new SVG width => 475, height => 250;
my $bordercolor	= 'rgb(0,0,0)';
my $background	= 'rgb(255,255,255)';
#my $background	= $svg->gradient(
#	id		=> 'bg_gradient',
#	-type	=> 'linear',
#	x1 => '0%',
#	x2 => '0%',
#	y1 => '0%',
#	y2 => '100%'
#);
#$background->stop(
#	offset		=> '20%',
#	'stop-color'=> 'rgb(255,255,255)',
#);
#$background->stop(
#	offset		=> '100%',
#	'stop-color'=> 'rgb(220,220,220)',
#);

my $arrow1 = $svg->marker(
	id		=> "arrow1",
	viewBox	=> "0 0 10 10",
	refX	=> "10",
	refY	=> "5",
	markerUnits	=> "strokeWidth",
	orient		=> "auto",
	markerWidth	=> "10",
	markerHeight=> "10",
);
my $arrow2 = $svg->marker(
	id		=> "arrow2",
	viewBox	=> "0 0 10 10",
	refX	=> "0",
	refY	=> "5",
	markerUnits	=> "strokeWidth",
	orient		=> "auto",
	markerWidth	=> "10",
	markerHeight=> "10",
);

$arrow1->polyline(points => '0,0 10,5 0,10 1,5');
$arrow2->polyline(points => '10,0 0,5 10,10 9,5');


my $hosts = $svg->group(id => 'hosts', stroke => $bordercolor, fill => 'url(#bg_gradient)', 'stroke-width' => 1);

my $monitor = new MMM::SVG::Host id => 'monitor', x => (450 - 120) / 2, y => 20, width => 120, height => 30, text => 'Monitor';

my $master1 = new MMM::SVG::Host id => 'master1', x =>  20, y => 80, width => 120, height => 30, text => 'Master 1';
my $master2 = new MMM::SVG::Host id => 'master2', x => 310, y => 80, width => 120, height => 30, text => 'Master 2';

my $app     = new MMM::SVG::Host id => 'app',     x =>  (450 - 120) / 2, y => 200, width => 120, height => 30, text => 'Application';
$master1->draw($hosts, $svg);
$master2->draw($hosts, $svg);
$monitor->draw($hosts, $svg);
$app->draw($hosts, $svg);


# Replication
my ($x1, $y1, $x2, $y2);
($x1, $y1) = $master1->connector('r');
($x2, $y2) = $master2->connector('l');
$svg->line(x1 => $x1, y1 => $y1 + 2, x2 => $x2, y2 => $y2 + 2, 'stroke' => 'black');
$svg->line(x1 => $x1, y1 => $y1 - 2, x2 => $x2, y2 => $y2 - 2, 'stroke' => 'black');

# Monitor
($x1, $y1) = $master1->connector('t');
($x2, $y2) = $monitor->connector('l');
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '5, 9');
($x1, $y1) = $master2->connector('t');
($x2, $y2) = $monitor->connector('r');
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '5, 9');

# MySQL
($x1, $y1) = $app->connector('t');
($x2, $y2) = $master1->connector('b');
$svg->line(x1 => $x1 - 30, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '7, 2, 2, 2');
($x1, $y1) = $app->connector('t');
($x2, $y2) = $master2->connector('b');
$svg->line(x1 => $x1 + 30, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '7, 2, 2, 2');

# Caption - arrows
$svg->line(x1 => 330, y1 => 195, x2 => 380, y2 => 195, 'stroke' => 'black');
$svg->line(x1 => 330, y1 => 215, x2 => 380, y2 => 215, 'stroke' => 'black', 'stroke-dasharray' => '7, 2, 2, 2');
$svg->line(x1 => 330, y1 => 235, x2 => 380, y2 => 235, 'stroke' => 'black', 'stroke-dasharray' => '5, 9');

# Caption - text
$svg->text(x => 395, y => 199, 'font-size' => '12', font => 'Verdana', fill => 'black', 'text-anchor' => 'left')->cdata('Replication');
$svg->text(x => 395, y => 219, 'font-size' => '12', font => 'Verdana', fill => 'black', 'text-anchor' => 'left')->cdata('MySQL');
$svg->text(x => 395, y => 239, 'font-size' => '12', font => 'Verdana', fill => 'black', 'text-anchor' => 'left')->cdata('MMM');


open(SVGFILE, '>', 'mmm-sample-setup-1.svg');
print SVGFILE $svg->xmlify;
close(SVGFILE);


# Slave
my $slave = new MMM::SVG::Host id => 'slave', x =>  (450 - 120) / 2, y => 120, width => 120, height => 30, text => 'Slave(s)';
$slave->draw($hosts, $svg);

# Slave replication
($x1, $y1) = $slave->connector('t');

($x2, $y2) = $master1->connector('r');
$svg->line(x1 => $x1 - 30, y1 => $y1, x2 => $x2, y2 => $y2 + 4, 'stroke' => 'black');
($x2, $y2) = $master2->connector('l');
$svg->line(x1 => $x1 + 30, y1 => $y1, x2 => $x2, y2 => $y2 + 4, 'stroke' => 'lightgrey');

# Slave monitoring
($x2, $y2) = $monitor->connector('b');
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '5, 9');

# Slave MySQL
($x1, $y1) = $slave->connector('b');
($x2, $y2) = $app->connector('t');
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '7, 2, 2, 2');

open(SVGFILE, '>', 'mmm-sample-setup-2.svg');
print SVGFILE $svg->xmlify;
close(SVGFILE);


