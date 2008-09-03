# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides a customized subclass of LWP::UserAgent.

package Bibliotech::UserAgent;
use strict;
use base 'LWPx::ParanoidAgent';
use Bibliotech::Util;
use Bibliotech::Config;

our $SITE_NAME 	= Bibliotech::Config->get('SITE_NAME');
our $STRING    	= Bibliotech::Config->get('AGENT', 'STRING');
our $TIMEOUT   	= Bibliotech::Config->get('AGENT', 'TIMEOUT') || 180;
our $WHITE_LIST = Bibliotech::Config->get('AGENT', 'WHITE_LIST') || [];
our $BLACK_LIST = Bibliotech::Config->get('AGENT', 'BLACK_LIST') || [];

sub _make_qr {
  local $_ = shift;
  /^((\d+\.){1,3})$/ and return qr/^$1/;
  return $_;
}

sub _make_qrs {
  map { ref($_) ? $_ : _make_qr($_) } @_;
}

# create normal object but override sitename and add log object
sub new {
  my ($class, %options) = @_;
  my ($bibliotech_sitename,
      $bibliotech_log) = do { my $bibliotech = delete $options{bibliotech};
			      defined $bibliotech ? ($bibliotech->sitename, $bibliotech->log) : () };
  my $self = $class->SUPER::new(%options);
  $self->timeout($TIMEOUT);
  $self->agent($STRING || ($bibliotech_sitename || $SITE_NAME).' ');  # trailing space ensures LWP will add version info
  $self->blocked_hosts(_make_qrs(@{$BLACK_LIST}))     if $BLACK_LIST and @{$BLACK_LIST};
  $self->whitelisted_hosts(_make_qrs(@{$WHITE_LIST})) if $WHITE_LIST and @{$WHITE_LIST};
  $self->cookie_jar({});
  $self->{log} = $bibliotech_log;
  return $self;
}

# LWP::UserAgent handles _foreign gracefully but LWPx::ParanoidAgent
# doesn't - although it is a subclass so just pass it back
sub request_handle_foreign {
  my ($self, $req, $arg, $size, $previous) = @_;
  return LWP::UserAgent::request($self, $req, $arg, $size, $previous)
      if UNIVERSAL::isa($req->uri, 'URI::_foreign');
  return $self->SUPER::request($req, $arg, $size, $previous);
}

# perform request as normal but afterwards log it and rebless response
sub request {
  my ($self, $request, $arg, $size, $previous) = @_;
  my $response = $self->request_handle_foreign($request, $arg, $size, $previous);
  $self->log_objects($request, $response);
  return bless $response, 'Bibliotech::HTTP::Response';
}

sub log_objects {
  my ($self, $request, $response) = @_;
  $self->log_message(join(' ',
			  'useragent', $request->method, $request->uri,
			  'yields', $response->status_line));
}

sub log_message {
  my ($self, $str) = @_;
  $self->{log}->info($str) if defined $self->{log};
}

sub system_hosts_file {
  open HOSTS, '</etc/hosts' or die 'unable to open /etc/hosts: '.$!;
  my @hosts = <HOSTS>;
  close HOSTS;
  return @hosts;
}

# look in /etc/hosts
sub _resolve {
  my ($self, $host, $request, $timeout, $depth) = @_;
  unless ($host =~ /^\d+\.\d+\.\d+\.\d+$/) {
    foreach (system_hosts_file()) {
      if (/^(\d+\.\d+\.\d+\.\d+)(\s+[\w\.]+)+$/) {
	my ($ip, @names) = ($1, grep { $_ } split(/\s+/, $2));
	if (grep { $host eq $_ } @names) {
	  return $self->SUPER::_resolve($ip, $request, $timeout, $depth);
	}
      }
    }
  }
  return $self->SUPER::_resolve($host, $request, $timeout, $depth);
}


# override the user agent used for HTTP::OAI as well
require HTTP::OAI::UserAgent;
@HTTP::OAI::UserAgent::ISA = ('Bibliotech::UserAgent');


package Bibliotech::HTTP::Response;
use base 'HTTP::Response';

# supplemented by document-based character set designations
sub decoded_content {
  my $response = shift;
  my $content = $response->content;
  my @types = ($response->header('Content-Type'));

  # pick up a couple extra non-header variants:
  my ($first_5_lines) = $content =~ /^((?:.*\n){0,5})/;
  # you wouldn't think it was necessary to limit to the top lines but cnn.com as one prominent
  # example has embedded XML in their home page
  if ($first_5_lines and $first_5_lines =~ /<?xml[^>]+encoding=\"([^\"]+)\"/) {
    push @types, 'application/xml;charset='.$1;
  }
  else {
    my ($head) = $content =~ m|^.*?(<head.*</head>)|si;
    # same issue here - limit to <head> where it is supposed to be!
    if ($head and $head =~ /<meta\s+http-equiv=\"Content-Type\"\s+content=\"([^\"]+)\"/is) {
      push @types, $1;
    }
  }

  # break apart type and charset:
  my ($type, $charset);
  foreach (@types) {
    if (m|^(\w+/[\w+]+)(?:\s*;\s*(?:charset=)?([\w\-]+))|i) {
      $type = $1;
      ($charset = $2) =~ s/^UTF-8$/utf8/ if $2;
    }
  }

  # offer default for charset based on type if necessary:
  $charset ||= ($type && $type =~ /(?:xml|xhtml|rss|rdf)/ ? 'utf8' : 'iso-8859-1');

  my $decoded = eval { $response->SUPER::decoded_content
			   ($content, charset => $charset, raise_error => 1) || $content; };
  if (my $e = $@) {
    return $content if $e =~ /unknown encoding/i or  # usually not our fault
	               $e =~ /unrecognised bom/i;    # not helpful to die on this
    die $e;
  }
  return $decoded;
}

1;
__END__
