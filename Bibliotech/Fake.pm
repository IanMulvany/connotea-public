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
use URI;

our ($SITE_NAME, $SITE_EMAIL);

__PACKAGE__->mk_accessors(qw/path canonical_path canonical_path_for_cache_key
			     x_parser x_command query request cgi location
			     title heading link description user
			     no_cache has_rss docroot error memcache log/);

sub sitename {
  return $SITE_NAME if defined $SITE_NAME;
  eval "use Bibliotech::Config";
  die $@ if $@;
  return $SITE_NAME = Bibliotech::Config->get('SITE_NAME');
}

sub siteemail {
  return $SITE_EMAIL if defined $SITE_EMAIL;
  eval "use Bibliotech::Config";
  die $@ if $@;
  return $SITE_EMAIL = Bibliotech::Config->get('SITE_EMAIL');
}

sub new {
  return shift->SUPER::new({cgi      => CGI::Fake->new,
			    log      => Bibliotech::Fake::Log->new,
			    location => URI->new('http://localhost/'),
			   });
}

sub parser {
  my $self = shift;
  my $parser = $self->x_parser;
  return $parser if defined $parser;
  eval "use Bibliotech::Parser";
  die $@ if $@;
  $parser = Bibliotech::Parser->new;
  $self->x_parser($parser);
  return $parser;
}

sub command {
  my $self = shift;
  my $command = $self->x_command;
  return $command if defined $command;
  eval "use Bibliotech::Command";
  die $@ if $@;
  $command = Bibliotech::Command->new;
  $self->x_command($command);
  return $command;
}

sub real {
  my $fake = shift;
  return bless {path                         => $fake->path || undef,
		canonical_path               => $fake->canonical_path || undef,
		canonical_path_for_cache_key => $fake->canonical_path_for_cache_key || undef,
		parser  		     => $fake->parser || undef,
		command 		     => $fake->command || undef,
		query                        => $fake->query || undef,
		request                      => $fake->request || undef,
		cgi                          => $fake->cgi || undef,
		location                     => $fake->location || undef,
		title                        => $fake->title || undef,
		heading                      => $fake->heading || undef,
		link                         => $fake->link || undef,
		description                  => $fake->description || undef,
		user                         => $fake->user || undef,
		no_cache                     => $fake->no_cache || undef,
		has_rss                      => $fake->has_rss || undef,
		docroot                      => $fake->docroot || undef,
		error                        => $fake->error || undef,
		memcache                     => $fake->memcache || undef,
		log                          => $fake->log || undef
  }, 'Bibliotech';
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
