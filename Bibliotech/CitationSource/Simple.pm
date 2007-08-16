# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Simple class is intended to be used when
# passing back simple data.

package Bibliotech::CitationSource::Simple;

use strict;
use warnings;

package Bibliotech::CitationSource::Result::Simple;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource::Result';

sub new
{
    my ($class, $citation) = @_;
    return bless {'citation' => $citation}, $class;
}

sub citation
{
    my ($self, $citation) = @_;
    $self->{'citation'} = $citation if $citation;
    return $self->{'citation'};
}

sub type
{
    my ($self, $type) = @_;
    if($type) {
	$self->citation->{'type'} = $type;
    }
    return $self->citation->{'type'} ? $self->citation->{'type'} : 'Simple CitationSource';
}

sub source
{
    my ($self, $source) = @_;
    if($source) {
	$self->citation->{'source'} = $source;
    }
    return $self->citation->{'source'};
}

sub identifiers
{
  my ($self, $identifiers) = @_;
  if($identifiers) {
      foreach (keys %$identifiers) {
	  $self->citation->{$_} = $identifiers->{$_};
      }
    }
  return $self->citation ? {'doi' => $self->citation->{'doi'}, 'pubmed' => $self->citation->{'pubmed'}, 'asin' => $self->citation->{'asin'} }: undef;
}

sub title
{
    my ($self, $title) = @_;
    if($title) {
	$self->citation->{'title'} = $title;
    }

    return $self->citation->{'title'};
}


# return an object of author objects: Bibliotech::CitationSource::Result::AuthorList
sub authors
{
    my ($self, $authors) = @_;
    if($authors) {
	##TODO
    }
    return new Bibliotech::CitationSource::Result::AuthorList(map { Bibliotech::CitationSource::Result::Author::Simple->new($_) } @{$self->citation->{'authors'}} );
}

# return a journal object: Bibliotech::CitationSource::Result::Journal
sub journal {
    my ($self, $journal) = @_;
    if($journal) {
	$self->citation->{'journal'} = $journal;
    }

    return Bibliotech::CitationSource::Result::Journal::Simple->new($self->citation->{'journal'}) if $self->citation and $self->citation->{'journal'};
    return undef;
}

sub volume {
    my ($self, $volume) = @_;
    if($volume) {
	$self->citation->{'volume'} = $volume;
    }
  return $self->citation->{'volume'};
}

sub issue {
    my ($self, $issue) = @_;
    if($issue) {
	$self->citation->{'issue'} = $issue;
    }

  return $self->citation->{'issue'};
}

sub page {
    my ($self, $page) = @_;
    if($page) {
	$self->citation->{'page'} = $page;
    }

  return $self->citation->{'page'};
}


# return date first published as YYYY-MM-DD
# where MM is digits or 3-letter English month abbreviation
# and MM and DD as digits do not need to be zero-padded
sub date {
    my $self = shift;
    my $citation = $self->citation or return undef;
    my $pubdate = $citation->{'pubdate'};
    return undef unless $pubdate;
    return $pubdate if $pubdate =~ m!\d{4}(?:-\d{2}){0,2}!;
    my ($month, $year) = ($self->{'citation'}->{'pubdate'} =~ m!(\w+)\s+(\d+)!);
    $month = substr($month, 0, 3);
    return "$year-$month";
}

# return date record was created or last modified, same format as date()
# required - do not return undef
sub last_modified_date {
    return shift->date;
}


package Bibliotech::CitationSource::Result::Author::Simple;
use strict;

sub new
{
    my ($class, $authorname) = @_;
    return bless {'authorname' => $authorname}, $class;
}

#just the first name
sub firstname
{
    my $self = shift;
    return $self->{'authorname'}->{'firstname'} if ref $self->{'authorname'};

    if($self->{'authorname'} =~ m!^(\w+)!)
    {
	return $1;
    }
    return undef;
}
#everything up to the last name
sub forename
{
    my $self = shift;
    return $self->{'authorname'}->{'forename'} if ref $self->{'authorname'};

    if($self->{'authorname'} =~ m!^(.*)\s\w+$!)
    {
	return $1;
    }
    return undef
}
sub initials
{
    my $self = shift;
    return $self->{'authorname'}->{'initials'} if ref $self->{'authorname'};

    my $initials = '';
    $initials .= uc(substr($self->firstname, 0, 1)) if $self->firstname;
    $initials .= uc(substr($self->middlename, 0, 1)) if $self->middlename;
    $initials .= uc(substr($self->middleinitial, 0, 1)) if ($self->middleinitial && !$self->middlename);
    
    return $initials if $initials;
    return undef;
}
sub middlename
{
    my $self = shift;
    return $self->{'authorname'}->{'middlename'} if ref $self->{'authorname'};

    my @names = split /\s+/, $self->{'authorname'};
    if(@names == 3 && $names[1] !~ m!\w\.?!)
    {
	return $names[1];
    }
    return undef;
}

sub middleinitial
{
    my $self = shift;
    return $self->{'authorname'}->{'middleinitial'} if ref $self->{'authorname'};

    my @names = split /\s+/,$self->{'authorname'};
    if(@names == 3 && $names[1] =~ m!\w\.?!)
    {
	return $names[1];
    }
    return undef;
}

sub lastname
{
    my $self = shift;
    return $self->{'authorname'}->{'lastname'} if ref $self->{'authorname'};

    if($self->{'authorname'} =~ m!^.*\s(\w+)$!)
    {
	return $1;
    }
    return undef;
}

package Bibliotech::CitationSource::Result::Journal::Simple;
use strict;

sub new
{
    my ($class, $journal) = @_;
    $journal = {} unless $journal;
    return bless $journal, $class;
}

# return as many of these strings as possible:
sub name           { return shift->{'name'}; }
sub issn           { return shift->{'issn'}; }

#true!
1;
