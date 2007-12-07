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
use CGI::Session;
use CGI::Session::ID::md5;
use CGI::Session::Serialize::default;
use Net::OpenID::JanRain::Consumer;
use Net::OpenID::JanRain::Stores;
use Net::OpenID::JanRain::Util qw/normalizeUrl/;
use Digest::MD5 qw/md5_hex/;
use Bibliotech::Component::LoginForm;
use Bibliotech::Util qw/ua/;
use Bibliotech::Config;
use Bibliotech::Cache;
use Bibliotech::Util;

sub last_updated_basis {
  ('NOW');
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $memcache   = $bibliotech->memcache;
  my $location   = $bibliotech->location;

  my $openid 	 = $cgi->param('openid');
  my $button 	 = $cgi->param('button');
  my $ret    	 = $cgi->param('ret');
  my $sid    	 = $cgi->param('cssid');

  my $session    = CGI::Session->new('driver:bibcache;id:md5;serializer:default', $sid, {memcache => $memcache});
  my $scache     = Bibliotech::Component::OpenIDForm::Store::Memcache->new($memcache);
  my $consumer   = Net::OpenID::JanRain::Consumer->new($session, $scache);

  my $root       = "$location";
  my $root_ret   = $root.'openid?ret=1&cssid='.$session->id;

  my $validationmsg;

  if ($button or $ret) {
    eval {
      if ($button and $button =~ /^login$/i) {
	$openid or die "Must supply an OpenID.\n";
	my $instance = $consumer->begin($openid);
	$instance->addExtensionArg('sreg', 'optional', 'nickname,fullname,email')
	    unless Bibliotech::User->by_openid(normalizeUrl($openid));  # request sreg if not in db
	my $status = $instance->status;
	if ($status eq 'in_progress') {
	  die 'Location: '.$instance->redirectURL($root, $root_ret)."\n";
	}
	elsif ($status eq 'failure') {
	  die 'OpenID error: '.$instance->message."\n";
	}
	die 'bad begin instance status';
      }
      if ($ret) {
	my $instance = $consumer->complete({map {$_ => $cgi->param($_)} $cgi->param});
	my $status = $instance->status;
	if ($status eq 'setup_needed') {
	  die 'Location: '.$instance->setup_url."\n";
	}
	elsif ($status eq 'success') {
	  my $verified_url = $instance->identity_url;
	  my $sreg = $instance->extensionResponse('sreg');
	  my $user = $bibliotech->allow_login_openid("$verified_url", $self->parse_sreg($sreg))
	      or die "OpenID problem - no user.\n";
	  my $loginform = Bibliotech::Component::LoginForm->new({bibliotech => $bibliotech});
	  die 'Location: '.$loginform->do_login_and_return_location($user, $bibliotech)."\n";
	}
	elsif ($status eq 'cancel') {
	  die "OpenID login aborted.\n";
	}
	elsif ($status eq 'failure') {
	  die 'OpenID error: '.$instance->message."\n";
	}
	die 'bad complete instance status';
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

# input:  {nickname => ..., fullname => ..., email => ...}
# output: (username, firstname, lastname, email)
sub parse_sreg {
  my $self = shift;
  my $sreg = shift or return;
  my %sreg = %{$sreg} or return;
  my $username = $sreg{nickname};
  my $fullname = $sreg{fullname};
  my ($firstname, $lastname) = split(/\s+/, $fullname, 2);
  my $email = $sreg{email};
  return ($username, $firstname, $lastname, $email);
}


package CGI::Session::Driver::bibcache;
use base qw(CGI::Session::Driver CGI::Session::ErrorHandler);

sub memcache {
  shift->{memcache};
}

sub full_key {
  my ($self, $key) = @_;
  return Bibliotech::Cache::Key->new(class => ref $self, id => 'Bibliotech', id => $key);
}

sub get {
  my ($self, $key) = @_;
  return $self->memcache->get($self->full_key($key));
}

sub set {
  my ($self, $key, $value) = @_;
  return $self->memcache->set($self->full_key($key), $value, 86400);
}

sub delete {
  my ($self, $key) = @_;
  return $self->memcache->delete($self->full_key($key));
}

# API conformance: (store, retrieve, remove)

sub store {
  my ($self, $sid, $datastr) = @_;
  $self->set($sid, $datastr);
}

sub retrieve {
  my ($self, $sid) = @_;
  $self->get($sid) || '';
}

sub remove {
  my ($self, $sid) = @_;
  $self->delete($sid);
}

# travese() is not implemented as this would complicate matters
# greatly and is not required by the JanRain consumer.


package Bibliotech::Component::OpenIDForm::Store::Memcache;
use base 'Net::OpenID::JanRain::Stores';
use Net::OpenID::JanRain::CryptUtil qw/randomString/;

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

sub add {
  my ($self, $key) = @_;
  return $self->memcache->add($self->full_key($key));
}

sub get {
  my ($self, $key) = @_;
  return $self->memcache->get($self->full_key($key));
}

sub set {
  my ($self, $key, $value) = @_;
  return $self->memcache->set($self->full_key($key), $value, 86400);
}

sub lock {
  my ($self, $key) = @_;
  return $self->memcache->lock($self->full_key($key));
}

sub unlock {
  my ($self, $key) = @_;
  return $self->memcache->unlock($self->full_key($key));
}

sub getAuthKey {
  my $self = shift;
  my $key = '_authkey';
  my $value = $self->get($key);
  return $value if $value;
  $value = randomString(8);
  $self->add($key => $value);
  return $self->get($key);
}

sub storeAssociation {
  my ($self, $server_url, $association) = @_;
  my $key = '_associations';
  $self->lock($key) or die 'lock failed on '.$key;
  $self->set($key => [(grep { $_->[1]->expiresIn > 0 } @{$self->get($key)||[]}),
		      [$server_url, $association]]);
  $self->unlock($key);
}

sub getAssociation {
  my ($self, $server_url, $handle) = @_;
  my $key = '_associations';
  $self->lock($key) or die 'lock failed on '.$key;
  my @results = sort { $a->{issued} <=> $b->{issued} }
                map  { $_->[1] }
                grep { $_->[1]->expiresIn > 0 &&
		       (not defined $server_url or $_->[0] eq $server_url) &&
		       (not defined $handle     or $_->[1]->handle eq $handle)
		     } @{$self->get($key)||[]};
  $self->unlock($key);
  return pop @results;
}

sub removeAssociation {
  my ($self, $server_url, $handle) = @_;
  my $key = '_associations';
  $self->lock($key) or die 'lock failed on '.$key;
  my @results = grep { $_->[1]->expiresIn > 0 &&
		       (not defined $server_url or $_->[0] ne $server_url) &&
		       (not defined $handle     or $_->[1]->handle ne $handle)
		     } @{$self->get($key)||[]};
  $self->set($key => \@results);
  $self->unlock($key);
}

sub _expire_nonces {
  my ($time, %nonces) = @_;
  my $max_age = 6*60*60;
  foreach (keys %nonces) {
    delete $nonces{$_} if $time - $nonces{$_} > $max_age;
  }
  return %nonces;
}

sub storeNonce {
  my ($self, $nonce) = @_;
  my $key = '_nonces';
  $self->lock($key) or die 'lock failed on '.$key;
  my $time = Bibliotech::Util::time();
  my %nonces = _expire_nonces($time, %{$self->get($key)||{}});
  $nonces{$nonce} = $time;
  $self->set($key => \%nonces);
  $self->unlock($key);
}

sub useNonce {
  my ($self, $nonce) = @_;
  my $key = '_nonces';
  $self->lock($key) or die 'lock failed on '.$key;
  my $time = Bibliotech::Util::time();
  my %nonces = _expire_nonces($time, %{$self->get($key)||{}});
  my $value = $nonces{$nonce};
  delete $nonces{$nonce};
  $self->set($key => \%nonces);
  $self->unlock($key);
  return $value ? 1 : 0;
}

sub isDumb {
  undef;
}

1;
__END__
