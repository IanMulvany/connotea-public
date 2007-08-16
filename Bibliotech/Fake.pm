# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Fake class emulates enough of the Bibliotech
# class to allow short test programs to run

package Bibliotech::Fake;
use strict;
use base 'Class::Accessor::Fast';
use Bibliotech::Config;
use Bibliotech::Parser;
use Bibliotech::Command;
use URI;

our $SITE_NAME = Bibliotech::Config->get('SITE_NAME');
our $SITE_EMAIL = Bibliotech::Config->get('SITE_EMAIL');

__PACKAGE__->mk_accessors(qw/path canonical_path canonical_path_for_cache_key
			     parser command query request cgi location
			     title heading link description user
			     no_cache has_rss docroot error memcache log/);

sub sitename {
  $SITE_NAME;
}

sub siteemail {
  $SITE_EMAIL;
}

sub new {
  return shift->SUPER::new({cgi      => new CGI::Fake,
			    parser   => new Bibliotech::Parser,
			    command  => new Bibliotech::Command,
			    log      => new Bibliotech::Fake::Log,
			    location => URI->new('http://localhost/'),
			   });
}

sub real {
  my $fake = shift;
  return bless $fake, 'Bibliotech';
}


package CGI::Fake;
use strict;

sub new {
  my ($class) = @_;
  return bless {}, ref $class || $class;
}

# no parameters to set or get
sub param {
  undef;
}

sub DESTROY {
}

# return everything as text, do not add tags like CGI.pm does
sub AUTOLOAD {
  (my $tag = our $AUTOLOAD) =~ s/^.*::(.*)$/lc($1)/e;
  return "\n" if $tag eq 'br';
  my $self = shift;
  my $hash = shift if ref $_[0] eq 'HASH';
  return ($tag eq 'div' || $tag eq 'p' ? "\n" : '').join(' ', @_);
}


package Bibliotech::Fake::Log;

sub new {
  my $class = shift;
  return bless {}, ref $class || $class;
}

sub open {
}

sub close {
}

sub DESTROY {
}

sub AUTOLOAD {
  (my $level = our $AUTOLOAD) =~ s/^.*::(.*)$/$1/;
  print STDERR localtime()." $level: ";
  print STDERR map("$_\n", @_);
}


1;
__END__
