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

sub _normalized_value {
  local $_ = shift;
  return 0 if m/^(no|off|false|0)$/i;
  return 1 if m/^(yes|on|true|1)$/i;
  return $_;
}

sub _simple_get {
  unshift @_, 'GENERAL' if @_ == 1;
  my $value;
  while (my $next = shift) {
    $value = ($value||$CONFIG)->{$next};
  }
  return $value;
}

sub get {
  shift if ref $_[0] or $_[0] eq 'Bibliotech::Config';
  return _normalized_value(_simple_get(@_));
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


package Bibliotech::Config::Util;

# For Bibliotech::CitationSource and Bibliotech::Component base
# classes: any configuration variable you need can be retrieved by
# cfg('KEYWORD') and this method will translate the call to the
# Bibliotech::Config module under a CITATION (or COMPONENT) block with
# the name of your module in caps (it uses cfgname(), name(), or the
# ending class name).
sub _cfg {
  my $obj = shift;
  my $method = shift;
  die "bad method: $method" unless $method =~ /^get/;
  my $name = sub { return $obj->cfgname if $obj->can('cfgname');
		   return $obj->name    if $obj->can('name');
		   (my $name = ref $obj || $obj) =~ s/^.*:://;
		   return $name;
		 };
  my $type = sub { return $obj->cfgtype if $obj->can('cfgtype');
		   (ref $obj || $obj) =~ /::(CitationSource|Component)::/;
		   return $1 eq 'CitationSource' ? 'Citation' : 'Component';
		 };
  return Bibliotech::Config->$method(uc($type->()), uc($name->()), @_);
}

# the callable version of _cfg()
sub cfg {
  my $self = shift;
  return _cfg($self, 'get', @_);
}

# same as cfg() but die with an error instead of returning undef
sub cfg_required {
  my $self = shift;
  return _cfg($self, 'get_required', @_);
}

1;
__END__
