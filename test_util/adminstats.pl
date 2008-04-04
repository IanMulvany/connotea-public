#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use lib '..';
use Bibliotech::Fake;
use Bibliotech::Component::AdminStats;
use Bibliotech::Util qw(hrtime);

my $give_interval = '24 hour';
my $show_sql = 0;
my $show_time = 0;
my $print_csv = 0;
my $printer_class = 'NormalPrint';

GetOptions('interval|i=s' => \$give_interval,
	   'show-sql|s'   => \$show_sql,
	   'show-time|t'  => \$show_time,
	   'csv|c'        => \$print_csv);

$printer_class = 'CSVPrint' if $print_csv;

my $bibliotech = Bibliotech::Fake->new;
my $component = Bibliotech::Component::AdminStats->new({bibliotech => $bibliotech});

my %stats = %{$component->stat_vars};
my $printer = $printer_class->new;
$printer->setup({show_key => 1, show_interval => 1, show_sql => $show_sql, show_value => 1, show_time => $show_time});
$printer->open;
foreach my $key (sort keys %stats) {
  my $need_interval = $key =~ /^new_/;
  my $calc_action = $stats{$key};
  my $action = sub { $calc_action->($need_interval ? $give_interval : undef, 1) };
  $printer->start;
  $printer->key($key);
  $printer->interval($need_interval ? $give_interval : undef);
  my ($aref, $time) = hrtime($action);
  my ($value, $sql) = @{$aref};
  $printer->sql($sql) if $show_sql;
  $printer->value($value);
  $printer->time($time) if $show_time;
  $printer->end;
}
$printer->close;

package Printer;

sub new { shift }
sub setup {};
sub open {};
sub start {};
sub key {};
sub interval {};
sub sql {};
sub value {};
sub time {};
sub end {};
sub close {};

package NormalPrint;
use base 'Printer';

sub open {
  $| = 1;
}

sub key {
  my $key = pop;
  print $key;
}

sub interval {
  my $interval = pop;
  print '(\'', $interval, '\')' if $interval;
  print ' = ';
}

sub sql {
  my $sql = pop;
  print '\'', $sql, '\' = ' if $sql;
}

sub value {
  my $value = pop;
  print (defined $value ? $value : 'undef');
}

sub time {
  my $time = pop;
  print ' (', $time, ')' if $time;
}

sub end {
  print "\n";
}

package CSVPrint;
use base 'Printer';

sub key {
  my $key = pop;
  print '"', $key, '"';
}

sub interval {
  my $interval = pop;
  print ',"', (defined $interval ? $interval : ''), '"';
}

sub sql {
  my $sql = pop;
  print ',"', $sql, '"' if $sql;
}

sub value {
  my $value = pop;
  print ',"', (defined $value ? $value : ''), '"';
}

sub time {
  my $time = pop;
  print ',"', $time, '"' if $time;
}

sub end {
  print "\n";
}
