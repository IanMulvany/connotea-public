# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

package Bibliotech::Config;
use strict;
use Cwd qw/abs_path/;

our $NAME = 'bibliotech.conf';
our $FILE;
our $CONFIG;
our $REQUIRED_SUB;

# allows you to say: use Bibliotech::Config file => '/tmp/test';
sub import {
  init(@_);
}

sub reload {
  init(@_, reload => 1);
}

sub load {
  my $file = pop;
  my $config = eval { Bibliotech::Config::Config::Scoped->new(file => $file)->parse };
  die "error from configuration reader ($file): $@" if $@;
  return $config;
}

sub find_file {
  my $name = pop;
  my $file = __FILE__;                                      # Perl symbol for **this** file
  $file = abs_path($file) unless $file =~ m|^/|;            # often relative, convert to full path
  $file =~ s|/[^/]*/[^/]*$|/$name|;                         # strip filename and one directory
  -e $file or $file = '/etc/'.$name;                        # if nothing, try /etc instead
  -e $file or die "no $name file one dir back or in /etc";  # otherwise give up
  return $file;
}

sub init {
  my ($class, %options) = @_;
  return if $options{noinit};
  return $CONFIG if $CONFIG && !$options{reload};
  $NAME = $options{name} if $options{name};
  $FILE = $options{file} || find_file($NAME);
  $REQUIRED_SUB = $options{required} if defined $options{required};
  return $CONFIG = load($FILE);
}

sub get {
  my $self = shift if ref $_[0] or $_[0] eq 'Bibliotech::Config';
  unshift @_, 'GENERAL' if @_ == 1;
  my $value;
  while (my $next = shift) {
    $value = ($value||$CONFIG)->{$next};
  }
  $value = 0 if $value =~ /^(NO|OFF|FALSE)$/i;
  return $value;
}

sub last_calling_class {
  my $i = 0;
  while (my @caller = caller($i)) {
    return $caller[0] if $caller[0] !~ /^Bibliotech::(?:Config|Util|Component|CitationSource)$/;
    ++$i;
  }
  return;
}

sub get_required {
  my $self = shift;
  my $value = $self->get(@_);
  return $value if defined $value;
  return $REQUIRED_SUB->(@_) if defined $REQUIRED_SUB;
  die 'Configuration variable '.join(' > ', @_).' required by '.last_calling_class()." but not found.\n";
}

package Bibliotech::Config::Config::Scoped;
use base 'Config::Scoped';

sub permissions_validate {
  1;
}

1;
__END__
