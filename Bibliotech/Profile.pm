# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Profile class contains helpful profiling
# routines.

package Bibliotech::Profile;
use strict;
use Time::HR;
use Carp;

our $ON = 0;
our %START;

sub activate {
  $ON = 1;
}

sub deactivate {
  $ON = 0;
}

# accepts a string to describe the act about to be started
# alternatively you can pass in a code reference - this lets you avoid
# expensive description calculations if profiling is off
sub start {
  return 0 unless $ON;
  my $note_str_or_sub = shift or croak 'no note';
  my $note = ref($note_str_or_sub) eq 'CODE' ? $note_str_or_sub->(\%START) : $note_str_or_sub;
  warn "- START $note\n";
  my $caller = caller;
  $START{$caller} ||= [];
  push @{$START{$caller}}, [gethrtime, $note];
  return 1;
}

# time how long something took since start() and warn of it
# start() and stop() are nestable
sub stop {
  return 0 unless $ON;
  my $end = gethrtime;
  my $caller = caller;
  my $stack = $START{$caller} || do { carp "caller not recognized (\"$caller\")"; [[$end, '?']]; };
  my ($start, $note) = @{pop @{$stack}};
  my $elapsed = sprintf('%0.4f', ($end - $start) / 1000000000);
  warn "- STOP  $note [$elapsed]\n";
  delete $START{$caller} unless @{$stack};
  return 1;
}

1;
__END__
