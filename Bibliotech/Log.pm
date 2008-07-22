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
our %LOG_LEVEL  = (none => 0, critical => 1, error => 2, notice => 3, info => 4, debug => 5);
our $LOG_LEVEL  = _interpret_log_level(Bibliotech::Config->get('LOG_LEVEL') || 'info');

sub _interpret_log_level {
  my $level = shift;
  my $word_to_num = $LOG_LEVEL{$level};
  return $word_to_num if $word_to_num;
  my $num = int($level);
  return $num if $num and $num >= 0 and grep { $num == $_ } (values %LOG_LEVEL);
  return;
}

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
  return if $LOG_LEVEL < $LOG_LEVEL{debug};
  shift->Log(debug => @_);
}

sub info {
  return if $LOG_LEVEL < $LOG_LEVEL{info};
  shift->Log(info => @_);
}

sub notice {
  return if $LOG_LEVEL < $LOG_LEVEL{notice};
  shift->Log(notice => @_);
}

sub error {
  return if $LOG_LEVEL < $LOG_LEVEL{error};
  shift->Log(err => @_);
}

sub critical {
  return if $LOG_LEVEL < $LOG_LEVEL{critical};
  shift->Log(crit => @_);
}

1;
__END__
