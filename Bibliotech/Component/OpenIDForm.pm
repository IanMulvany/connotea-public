# Copyright 2007 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::OpenIDForm class provides a login form
# that uses OpenID third party authentication.

package Bibliotech::Component::OpenIDForm;
use strict;
use base 'Bibliotech::Component';
use LWPx::ParanoidAgent;
use Net::OpenID::Consumer;
use Digest::MD5 qw/md5_hex/;
use Bibliotech::Component::LoginForm;
use Bibliotech::Util qw/ua/;
use Bibliotech::Config;
use Bibliotech::Cache;

our $OPENID_SECRET = Bibliotech::Config->get('OPENID_SECRET') || '123';

sub last_updated_basis {
  ('NOW');
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $cgi        = $bibliotech->cgi;
  my $memcache   = $bibliotech->memcache;

  my $csr = Net::OpenID::Consumer->new
      (ua              => ua($bibliotech),
       cache           => cache_broker($memcache),
       args            => $cgi,
       consumer_secret => \&openid_secret,
       required_root   => "$location");

  my $openid = $cgi->param('openid');
  my $button = $cgi->param('button');
  my $ret    = $cgi->param('ret');

  my $validationmsg;

  if ($button or $ret) {
    eval {
      if ($button and $button =~ /^login$/i) {
	$openid or die "Must supply an OpenID.\n";
	my $claimed_identity = $csr->claimed_identity($openid) or die "OpenID problem - no CI.\n";
	my $check_url = $claimed_identity->check_url
	    (return_to  => $location.'openid?ret=1',
	     trust_root => "$location");
	die "Location: $check_url\n";
      }
      if ($ret) {
	if (my $setup_url = $csr->user_setup_url) {
	  die "Location: $setup_url\n";
	}
	elsif ($csr->user_cancel) {
	  die "OpenID login aborted.\n";
	}
	elsif (my $verified_identity = $csr->verified_identity) {
	  my $verified_url = $verified_identity->url or die "OpenID problem - no VI URL.\n";
	  my $user = $bibliotech->allow_login_openid("$verified_url") or die "OpenID problem - no user.\n";
	  my $loginform = Bibliotech::Component::LoginForm->new({bibliotech => $bibliotech});
	  die 'Location: '.$loginform->do_login_and_return_location($user, $bibliotech)."\n";
	}
	die 'OpenID validation error: '.($csr->err || 'no setup, cancel, or identity')."\n";
      }
    };
    if (my $e = $@) {
      die $e if $e =~ /^Location:/ or $e =~ / at .* line /;
      $validationmsg = $self->validation_exception('openid', $e);
    }
  }

  my $o = $self->tt('compopenid', undef, $validationmsg);

  my $javascript_first_empty = $self->firstempty($cgi, 'openid', qw/openid/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					      javascript_onload => ($main ? $javascript_first_empty : undef)});
}

sub openid_secret {
  md5_hex(join('/', 'openid', $OPENID_SECRET, shift));
}

sub cache_broker {
  Bibliotech::Component::OpenIDForm::Cache->new(shift);
}


package Bibliotech::Component::OpenIDForm::Cache;

sub new {
  my ($class, $memcache) = @_;
  return bless [$memcache], ref $class || $class;
}

sub memcache {
  shift->[0];
}

sub full_key {
  my ($self, $key) = @_;
  return Bibliotech::Cache::Key->new(class => ref $self, id => $key);
}

sub get {
  my ($self, $key) = @_;
  return $self->memcache->get($self->full_key($key));
}

sub set {
  my ($self, $key, $value) = @_;
  return $self->memcache->set($self->full_key($key), $value, 900);  # nothing here should take more than 15 minutes
}

1;
__END__
