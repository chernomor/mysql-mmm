#!/usr/bin/env perl
use strict;
use SVG;

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
		rx		=> 4,
		ry		=> 4,
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

package MMM::SVG;
sub connect {
	my $o1 = shift;
	my $o2 = shift;

	my $xo1 = $o1->center_x;
	my $yo1 = $o1->center_y;
	my $xo2 = $o2->center_x;
	my $yo2 = $o2->center_y;
	if ($xo1 == $xo2) {
		return $o1->connector('b'), $o2->connector('t') if ($yo1 < $yo2);
		return $o1->connector('t'), $o2->connector('b');
	}
	my $slope = abs(($yo2 - $yo1) / ($xo2 - $xo1));
#	print "$o1->{id}, $o2->{id}: $slope\n";
	if ($slope > 0.75) {
		return $o1->connector('b'), $o2->connector('t') if ($yo1 < $yo2);
		return $o1->connector('t'), $o2->connector('b');
	}
	return $o1->connector('r'), $o2->connector('l') if ($xo1 < $xo2);
	return $o1->connector('l'), $o2->connector('r');
}

package main;

my $svg = new SVG width => 450, height => 450;
my $bordercolor	= 'rgb(0,0,0)';
my $background	= $svg->gradient(
	id		=> 'bg_gradient',
	-type	=> 'linear',
	x1 => '0%',
	x2 => '0%',
	y1 => '0%',
	y2 => '100%'
);
$background->stop(
	offset		=> '20%',
	'stop-color'=> 'rgb(255,255,255)',
);
$background->stop(
	offset		=> '100%',
	'stop-color'=> 'rgb(220,220,220)',
);

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

my $master1 = new MMM::SVG::Host id => 'master1', x =>  20, y => 150, width => 120, height => 30, text => 'Master 1';
my $master2 = new MMM::SVG::Host id => 'master2', x => 310, y => 150, width => 120, height => 30, text => 'Master 2';

my $app     = new MMM::SVG::Host id => 'app',     x =>  (450 - 120) / 2, y => 280, width => 120, height => 30, text => 'Application';
$master1->draw($hosts, $svg);
$master2->draw($hosts, $svg);
$monitor->draw($hosts, $svg);
$app->draw($hosts, $svg);


my ($x1, $y1, $x2, $y2) = MMM::SVG::connect($master1, $master2);
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black','marker-start' => 'url(#arrow2)', 'marker-end' => 'url(#arrow1)');

($x1, $y1, $x2, $y2) = MMM::SVG::connect($master2, $monitor);
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '5, 9');
($x1, $y1, $x2, $y2) = MMM::SVG::connect($master1, $monitor);
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '5, 9');

($x1, $y1, $x2, $y2) = MMM::SVG::connect($app, $master1);
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '7, 2, 2, 2');
($x1, $y1, $x2, $y2) = MMM::SVG::connect($app, $master2);
$svg->line(x1 => $x1, y1 => $y1, x2 => $x2, y2 => $y2, 'stroke' => 'black', 'stroke-dasharray' => '7, 2, 2, 2');

$svg->line(x1 => 20, y1 => 380, x2 => 70, y2 => 380, 'stroke' => 'black','marker-start' => 'url(#arrow2)', 'marker-end' => 'url(#arrow1)');
$svg->line(x1 => 20, y1 => 400, x2 => 70, y2 => 400, 'stroke' => 'black', 'stroke-dasharray' => '7, 2, 2, 2');
$svg->line(x1 => 20, y1 => 420, x2 => 70, y2 => 420, 'stroke' => 'black', 'stroke-dasharray' => '5, 9');

$svg->text(x => 90, y => 384, 'font-size' => '12', font => 'Verdana', fill => 'black', 'text-anchor' => 'left')->cdata('Replication');
$svg->text(x => 90, y => 404, 'font-size' => '12', font => 'Verdana', fill => 'black', 'text-anchor' => 'left')->cdata('MySQL');
$svg->text(x => 90, y => 424, 'font-size' => '12', font => 'Verdana', fill => 'black', 'text-anchor' => 'left')->cdata('MMM');

open(SVGFILE, '>', 'mmm-sample-setup-1.svg');
print SVGFILE $svg->xmlify;
close(SVGFILE);
