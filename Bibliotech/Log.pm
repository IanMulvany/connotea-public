# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

package Bibliotech::Log;
use strict;
use base 'Net::Daemon::Log';
use IO::File;
use Fcntl qw(:flock :seek);
use Carp;
use Bibliotech::Config;

our $SITE_NAME  = Bibliotech::Config->get_required('SITE_NAME');
our $LOG_FILE   = Bibliotech::Config->get('LOG_FILE') || '/var/log/bibliotech.log';
our $LOG_FORMAT = "$SITE_NAME\[%d\] \%s";

sub import {
  my ($class, %options) = @_;
  $LOG_FILE   = $options{file}   if $options{file};
  $LOG_FORMAT = $options{format} if $options{format};
}

sub new {
  my $class = shift;
  my $self = bless {}, ref $class || $class;
  if (my $file = shift || $LOG_FILE) {
    if ($file eq '1') {
      $self->{logfile} = 1;
    }
    else {
      $self->{logfile} = IO::File->new($file => 'a') or croak "cannot open $file as log: $!";
    }
  }
  return $self;
}

sub open {
  shift->OpenLog;
}

sub close {
  my $file = shift->{logfile};
  $file->close if UNIVERSAL::can($file, 'close');
}

sub flush {
  my $file = shift->{logfile};
  $file->flush if UNIVERSAL::can($file, 'flush');
}

sub Log {
  my ($self, $level, $msg) = @_;
  my $file = $self->{logfile}
    or croak 'log file handle undefined (did you call '.__PACKAGE__.'->new() and ->open()?)';
  flock $file, LOCK_EX;
  seek  $file, 0, SEEK_END;
  my $ret = $self->SUPER::Log($level, $LOG_FORMAT, $$, $msg);
  flock $file, LOCK_UN;
  return $ret;
}

sub debug {
  shift->Log(debug => @_);
}

sub info {
  shift->Log(info => @_);
}

sub notice {
  shift->Log(notice => @_);
}

sub error {
  shift->Log(err => @_);
}

sub critical {
  shift->Log(crit => @_);
}

1;
__END__
