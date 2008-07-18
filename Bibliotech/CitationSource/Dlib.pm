# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Dlib class retrieves citation data for articles
# in D-Lib Magazine.

package Bibliotech::CitationSource::Dlib;

use strict;
use warnings;
use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';

sub api_version {
  1;
}

sub name {
  'D-Lib Magazine';
}

sub version {
  '1.3.16.1';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless $uri->host =~ m/^(?:www)?.dlib.org$/;
  return 0 unless $uri->path =~ m!^/dlib/(?:january|february|march|april|may|june|july|august|september|october|november|december)\d+/(.+?)/\d+\1\.html$!i;
  return 1;
}

sub citations {
  my ($self, $uri) = @_;
  return undef unless($self->understands($uri));

  my $meta_uri = $self->dlib_meta_uri($uri);
  my $meta_xml;
  eval { $meta_xml = $self->get($meta_uri) };
  if ($@) {
    $self->errstr($@);
    return undef;
  }
  my $raw_citation = $self->raw_parse_dlib_xml($meta_xml);
  # check it's worth returning
  unless($raw_citation->{'title'} && $raw_citation->{'pubdate'} && $raw_citation->{'serial_name'}) {
    $self->errstr('Insufficient metadata extracted for ' . $uri);
    return undef;
  }
  $raw_citation->{'uri'} = $uri->as_string;
  $raw_citation->{'meta_uri'} = $meta_uri->as_string;

  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::Dlib->new($raw_citation));
}

sub dlib_meta_uri {
  my ($self, $uri) = @_;
  my $new_uri = $uri->as_string;
  $new_uri =~ s!\.html$!.meta.xml!i;
  return URI->new($new_uri);
}

sub raw_parse_dlib_xml {
  my ($self, $xml) = @_;

  my $citation;
  if ($xml =~ m!<title>(.+?)</title>!s) {
    $citation->{'title'} = $1;
    $citation->{'title'} =~ s!\n! !g;
  }
  if ($xml =~ m!(<creator>.+</creator>)!s) {
    my $subxml = $1;
    my @creators = ($subxml =~ m!<creator>(.+?)</creator>!g);
    $citation->{'authors'} = \@creators;
  }
  if ($xml =~ m!<publisher>(.+?)</publisher>!s) {
    $citation->{'publisher'} = $1;
  }
  if ($xml =~ m!<date\s+date-type\s*=\s*"publication">(.+?)</date>!s) {
    $citation->{'pubdate'} = $1;
  }
  if ( ($xml =~ m!<identifier\s+uri-type\s*=\s*"DOI">(.+?)</identifier>!s) ||
       ($xml =~ m!<meta\s+name\s*=\s*"DOI"\s*content\s*="(.+?)">!s) ) {
    $citation->{'doi'} = $1;
  }
  if ($xml =~ m!<language>(.+?)</language>!s) {
    $citation->{'language'} = $1;
  }
  if ($xml =~ m!<serial-name>(.+?)</serial-name>!s) {
    $citation->{'serial_name'} = $1;
  }
  if ($xml =~ m!<issn>(.+?)</issn>!s) {
    $citation->{'issn'} = $1;
  }
  if ($xml =~ m!<volume>(.+?)</volume>!s) {
    $citation->{'volume'} = $1;
  }
  if ($xml =~ m!<issue>(.+?)</issue>!s) {
    $citation->{'issue'} = $1;
  }

  return $citation;
}

package Bibliotech::CitationSource::Result::Dlib;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource::Result';

sub new {
  my ($class, $citation) = @_;
  return bless {'citation' => $citation}, $class;
}

sub type {
  'DLib Magazine Article';
}

sub source
{
  my $self = shift;
  return $self->{'citation'}->{'meta_uri'};
}

sub identifiers {
  my $self = shift;
  return {'doi' => $self->{'citation'}->{'doi'}};
}

sub title {
  my $self = shift;
  return $self->{'citation'}->{'title'};
}


# return an object of author objects: Bibliotech::CitationSource::Result::AuthorList
sub authors {
  my $self = shift;
  return new Bibliotech::CitationSource::Result::AuthorList(map { Bibliotech::CitationSource::Result::Author::Dlib->new($_) } @{$self->{'citation'}->{'authors'}} );
}

# return a journal object: Bibliotech::CitationSource::Result::Journal
sub journal {
  my $self = shift;
  return Bibliotech::CitationSource::Result::Journal::Dlib->new($self->{'citation'}); 
}

sub volume {
  my $self = shift;
  return $self->{'citation'}->{'volume'};
}

sub issue {
  my $self = shift;
  return $self->{'citation'}->{'issue'};
}


# return date first published as YYYY-MM-DD
# where MM is digits or 3-letter English month abbreviation
# and MM and DD as digits do not need to be zero-padded
sub date {
  my $self = shift;
  my ($month, $year) = ($self->{'citation'}->{'pubdate'} =~ m!(\w+)\s+(\d+)!);
  $month = substr($month, 0, 3);
  return "$year-$month";
}

# return date record was created or last modified, same format as date()
# required - do not return undef
sub last_modified_date {
  return shift->date;
}


package Bibliotech::CitationSource::Result::Author::Dlib;
use strict;

sub new {
  my ($class, $authorname) = @_;
  return bless {'authorname' => $authorname}, $class;
}

# just the first name
sub firstname {
  my $self = shift;
  return $1 if $self->{'authorname'} =~ m!^(\w+)!;
  return undef;
}

# everything up to the last name
sub forename {
  my $self = shift;
  return $1 if $self->{'authorname'} =~ m!^(.*)\s\w+$!;
  return undef
}

sub initials {
  my $self = shift;
  my $initials = '';
  $initials .= uc(substr($self->firstname, 0, 1)) if $self->firstname;
  $initials .= uc(substr($self->middlename, 0, 1)) if $self->middlename;
  $initials .= uc(substr($self->middleinitial, 0, 1)) if ($self->middleinitial && !$self->middlename);
  return $initials if $initials;
  return undef;
}

sub middlename {
  my $self = shift;
  my @names = split /\s+/, $self->{'authorname'};
  if (@names == 3 && $names[1] !~ m!\w\.?!) {
    return $names[1];
  }
  return undef;
}

sub middleinitial {
  my $self = shift;
  my @names = split /\s+/,$self->{'authorname'};
  if (@names == 3 && $names[1] =~ m!\w\.?!) {
    return $names[1];
  }
  return undef;
}

sub lastname {
  my $self = shift;
  return $1 if $self->{'authorname'} =~ m!^.*\s(\w+)$!;
  return undef;
}

package Bibliotech::CitationSource::Result::Journal::Dlib;
use strict;

sub new {
  my ($class, $citation) = @_;
  return bless {'name' => $citation->{'serial_name'}, 'issn' => $citation->{'issn'}}, $class;
}

# return as many of these strings as possible:
sub name           { return shift->{'name'}; }
sub issn           { return shift->{'issn'}; }

1;
__END__
