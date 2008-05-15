# Copyright 2007 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::ReadOnly class contains helper routines for
# Bibliotech::Apache.

package Bibliotech::ReadOnly;
use strict;
use Bibliotech::Config;
use List::MoreUtils qw/none/;

# _is...     - purely functional routines, same output for same input, no side effects
# is...      - side effects ok if done by calling in passed in code refs, look up global vars ok
# do...      - perform all side effects necessary

our $SERVICE_READ_ONLY 		  = Bibliotech::Config->get('SERVICE_READ_ONLY');
our $SERVICE_READ_ONLY_SEARCH_TOO = Bibliotech::Config->get('SERVICE_READ_ONLY_SEARCH_TOO');
our $SERVICE_NEVER_READ_ONLY_FOR  = Bibliotech::Config->get('SERVICE_NEVER_READ_ONLY_FOR');
our $SERVICE_READ_ONLY_SILENT     = Bibliotech::Config->get('SERVICE_READ_ONLY_SILENT');

our @WRITE_PAGES =
    ('addcommentpopup',
     'addcomment',
     'addgroup',
     'editgroup',
     'addtagnote',
     'edittagnote',
     'addpopup',
     'editpopup',
     'add',
     'edit',
     'remove',
     'retag',
     'upload',
     'register',
     'verify',
     'advanced',
     'forgotpw',
     'resendreg',
     'reportspam',
     'killspammer',
     'adminrenameuser');

our @SEARCH_PAGES =
    ('search');

our @COMBINED = (@WRITE_PAGES, @SEARCH_PAGES);

sub list_from_undef_scalar_or_arrayref {
  local $_ = shift;
  return () unless defined $_;
  return ($_) unless ref $_;
  return @{$_};
}

sub _is_service_read_only {
  my ($config_switch, $page, $config_write_pages_list, $config_exemption_list,
      $freematch, $config_ban_freematch, $remote_ip) = @_;
  return unless $config_switch;
  return 1 if $freematch and $config_ban_freematch;
  my @write_pages = list_from_undef_scalar_or_arrayref($config_write_pages_list) or return;
  return if none { $page eq $_ } @write_pages;
  my @exempt = list_from_undef_scalar_or_arrayref($config_exemption_list) or return 1;
  return none { $remote_ip eq $_ } @exempt;
}

sub is_service_read_only {
  my ($page, $freematch, $remote_ip) = @_;
  return _is_service_read_only($SERVICE_READ_ONLY,
			       $page,
			       $SERVICE_READ_ONLY_SEARCH_TOO ? \@COMBINED : \@WRITE_PAGES,
			       $SERVICE_NEVER_READ_ONLY_FOR,
			       $freematch,
			       $SERVICE_READ_ONLY_SEARCH_TOO,
			       $remote_ip);
}

sub do_service_read_only {
  my $self = shift;
  my $command = $self->command;
  my $request = $self->request;
  return is_service_read_only($command->page_or_inc, $command->freematch, $request->connection->remote_ip);
}

sub is_service_read_only_at_all {
  return $SERVICE_READ_ONLY;
}

sub is_service_read_only_silent {
  return $SERVICE_READ_ONLY_SILENT;
}
