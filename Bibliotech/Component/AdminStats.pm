# Copyright 2007 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::AdminStats class provides an
# interface to a simple administrative statistics report.

package Bibliotech::Component::AdminStats;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::DBI;
use Bibliotech::Clicks;
use Bibliotech::Util qw/hrtime/;

our $ADMIN_USERS = __PACKAGE__->cfg('ADMIN_USERS');
$ADMIN_USERS = [$ADMIN_USERS] unless ref $ADMIN_USERS;

sub last_updated_basis {
  'NOW';
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;
  my $user       = $self->getlogin or return $self->saylogin('to access the admin menu');
  my $username   = $user->username;
  #grep { $username eq $_ } @{$ADMIN_USERS} or return Bibliotech::Page::HTML_Content->simple('Not an admin.');
  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $o          = $self->tt('compadminstats', $self->stat_vars, undef);
  return Bibliotech::Page::HTML_Content->simple($o);
}

sub db {
  my $db = shift || 'main';
  return Bibliotech::Clicks->db_Main if $db eq 'clicks';
  return Bibliotech::DBI->db_Main;
}

sub query {
  my $db = shift;
  my $ret = eval { (db($db)->selectrow_array(@_))[0]; };
  return $@ if $@;
  return $ret;
}

sub query_timed {
  my $db = shift;
  my @args = @_;
  my ($result, $time) = hrtime(sub { (db($db)->selectrow_array(@args))[0] });
  return "$result [$time]";
}

sub interval {
  local $_ = shift;
  /^(\d+)\s*(minute|hour|day)s?$/ or return;
  return join(' ', 'interval', $1, $2);
}

sub total_and_new {
  my $cache = shift;
  my $db = shift;
  my $name = shift;
  my $query = pop;
  my @tokens = @_;
  my $make = sub {
    my $handle = shift;
    ($handle => with_tokens($db, $query, $handle, $cache, @_));
  };
  return ($make->(join('_', 'total', $name) => 'total'),
	  $make->(join('_', 'new',   $name) => 'new'),
	  (map {
	    ($make->(join('_', 'total', $name, $_) => 'total', $_),
	     $make->(join('_', 'new',   $name, $_) => 'new',   $_))
	   } @tokens)
         );
}

sub with_tokens {
  my ($db, $query, $handle, $cache, @tokens) = @_;
  return sub {
    my $key = join(',', $handle, @_);
    return $cache->{$key} if defined $cache->{$key};
    local $_ = $query;
    s{ \% (\w+) \[ (.*?) \] }{
      my ($token, $sql_snippet) = (lc($1), $2);
      ((grep { $token eq $_ } @tokens) ? fixup_sql_snippet($sql_snippet, @_) : '');
    }gex;
    s/\b(where\s+)and\s+/where /;
    s/\s+$//;
    s/\s+where$//;
    return $cache->{$key} = query($db, $_);
  };
}

sub fixup_sql_snippet {
  local $_ = shift;
  s/(NOW\(\)\s*-[\s\)]*)$/$1.interval(shift)/e;
  return $_;
}

sub stat_vars {
  my $cache = {};
  my %stats =
      ((map { total_and_new($cache, undef, @{$_}) }
	(['user_bookmarks', 'public', 'private', 'mywork',
	  'select count(*) from user_bookmark where '.
	  '%PUBLIC[private = 0 and private_gang is null and private_until is null] '.
	  '%PRIVATE[(private = 1 or private_gang is not null or private_until is not null)] '.
	  '%MYWORK[user_is_author = 1] '.
	  '%NEW[and created >= NOW() - ]'],
	 ['bookmarks',
	  'select count(*) from bookmark '.
	  '%NEW[where created >= NOW() - ]'],
	 ['users', 'active', 'verified',
	  'select count(*) from user where '.
	  '%ACTIVE[active = 1] %VERIFIED[verifycode is null] %NEW[and created >= NOW() - ]'],
	 ['users_1plus',
	  'select count(distinct u.user_id) from user_bookmark ub left join user u on (ub.user = u.user_id) '.
	  '%NEW[where u.created >= NOW() - ]'],
	 ['citations',
	  'select count(*) from ('.
	  'select citation_id from ('.
	  'select c.citation_id, c.created '.
	  'from user_bookmark ub '.
	  'left join bookmark b on (ub.bookmark = b.bookmark_id) '.
	  'left join citation c on (b.citation = c.citation_id) '.
	  'UNION '.
	  'select c.citation_id, c.created '.
	  'from user_bookmark ub '.
	  'left join citation c on (ub.citation = c.citation_id) '.
	  ') as u1 %NEW[where created >= NOW() - ]'.
	  ') as u2'],
	 ['citations_authoritative', 'pubmed', 'doi', 'asin',
	  'select count(c.citation_id) '.
	  'from user_bookmark ub '.
	  'left join bookmark b on (ub.bookmark = b.bookmark_id) '.
	  'left join citation c on (b.citation = c.citation_id) '.
	  'where '.
	  '%PUBMED[c.pubmed is not null and c.pubmed != \'\'] '.
	  '%DOI[c.doi is not null and c.doi != \'\'] '.
	  '%ASIN[c.asin is not null and c.asin != \'\'] '.
	  '%NEW[and c.created >= NOW() - ]',
	 ],
	 ['citations_personal', 'pubmed', 'doi', 'asin',
	  'select count(c.citation_id) '.
	  'from user_bookmark ub '.
	  'left join citation c on (ub.citation = c.citation_id) '.
	  'where '.
	  '%PUBMED[c.pubmed is not null and c.pubmed != \'\'] '.
	  '%DOI[c.doi is not null and c.doi != \'\'] '.
	  '%ASIN[c.asin is not null and c.asin != \'\'] '.
	  '%NEW[and c.created >= NOW() - ]',
	 ],
	)),
       total_and_new($cache, 'clicks', 'clicks',
		     'select count(distinct ip_addr) from log '.
		     'where dest_uri = "https://secure.nature.com/subscribe/nature" '.
		     '%NEW[and time >= NOW() - ]')
       );
  return \%stats;
}

1;
__END__
