# Copyright 2005-2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::AdvancedForm class provides a form that
# allows users to modify advanced settings of their account.

package Bibliotech::Component::AdvancedForm;
use strict;
use base 'Bibliotech::Component';
use URI::Heuristic qw(uf_uristr);

sub last_updated_basis {
  ('NOW');  # not an oft-used page, just always load exactly correct registration details
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  return $self->saylogin('to set your advanced settings') unless $self->getlogin;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $user       = $bibliotech->user;

  $bibliotech->last_modified_no_cache;  # tell AOL etc to always reload

  # parameter cleaning - need this to keep utf-8 output from messing up on a reload
  foreach (qw/openurl_resolver openurl_name openid/) {
    my $value = $self->cleanparam($cgi->param($_));
    $cgi->param($_ => $value) if $value;
  }

  my $validation;
  my $button = $cgi->param('button');
  if ($button =~ /^(?:Update)$/i) {
    my $o;
    eval {
      die $self->validation_exception('', "You cannot update if you are not logged in.\n")
	  if $button eq 'Update' and !defined($user);
      my $openurl_resolver = $cgi->param('openurl_resolver');
      $openurl_resolver = undef if $openurl_resolver eq 'http://';
      my $openurl_name = $cgi->param('openurl_name');
      $self->validate_openurl($openurl_resolver, $openurl_name, sub { $cgi->param(openurl_resolver => $_[0]); });
      $user->openurl_resolver($openurl_resolver);
      $user->openurl_name($openurl_name);
      my $openid = $cgi->param('openid');
      $self->validate_openid($openid, sub { $cgi->param(openid => $_[0]); });
      $user->openid($openid);
      $user->mark_updated;
      $o = $self->tt('compadvancedthanks');
    };
    if ($@) {
      die $@ if $@ =~ /at .* line \d+/;
      $validation = $@;
    }
    else {
      return Bibliotech::Page::HTML_Content->simple($o);
    }
  }

  if ($user and !$validation) {
    my %user = $bibliotech->load_user($user->user_id);
    $cgi->param($_ => $user{$_}) foreach (keys %user);
  }

  my $o = $self->tt('compadvanced', undef, $validation);

  my $javascript_first_empty = $self->firstempty($cgi, 'advanced', [qw/openurl_resolver openurl_name openid/], $validation);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					      javascript_onload => ($main ? $javascript_first_empty : undef)});
}

sub validate_openurl {
  my ($self, $uri, $name, $suggestion_callback) = @_;
  $self->validate_tests('openurl_resolver', sub {
    return 1 if !$uri;
    length $uri <= 255 or die "Your OpenURL resolver address must be no more than 255 characters long.\n";
    my $uri_obj = URI->new($uri);
    unless ($uri_obj->scheme =~ /^https?$/) {
      my $suggestion = uf_uristr($uri_obj);
      die "Sorry, please use an http or https scheme for your OpenURL resolver address\n"
	  if !$suggestion or $suggestion eq $uri_obj;
      $suggestion_callback->($suggestion) if defined $suggestion_callback;
      die "The OpenURL resolver location you have entered doesn\'t look like a full URL. Perhaps you meant:<br />$suggestion<br />If so, please click Update.  If not, please edit the location, making sure you include http or https.\n";
    }
    $uri_obj->host or die "Sorry, your OpenURL resolver address appears to have no host name.\n";
  });
}

sub validate_openid {
  my ($self, $uri, $suggestion_callback) = @_;
  $self->validate_tests('openid', sub {
    return 1 if !$uri;
    length $uri <= 255 or die "Your OpenID address must be no more than 255 characters long.\n";
    my $uri_obj = URI->new($uri);
    unless ($uri_obj->scheme =~ /^https?$/) {
      my $suggestion = uf_uristr($uri);
      die "Sorry, please use an http or https scheme for your OpenID address\n"
	  if !$suggestion or $suggestion eq "$uri_obj";
      $suggestion_callback->($suggestion) if defined $suggestion_callback;
      die "The OpenID URL you have entered doesn\'t look like a full URL. Perhaps you meant:<br />$suggestion<br />If so, please click Update.  If not, please edit the location, making sure you include http or https.\n";
    }
    $uri_obj->host or die "Sorry, your OpenID address appears to have no host name.\n";
  });
}

1;
__END__
