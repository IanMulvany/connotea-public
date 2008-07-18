# The Bibliotech::CitationSource::LivingReviews class retrieves citation data 
# for articles in a Living Reviews journal (http://www.livingreviews.org/)

# Copyright Robert Forkel
# This software is licensed under the terms of the GPL

package Bibliotech::CitationSource::LivingReviews;

use strict;
use warnings;
use XML::Twig;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';

my $JOURNALS = {
    lrr => {
	name => "Living Reviews in Relativity",
	subdomain => "relativity",
	issn => "1433-8351",
	start_year => 1998,
    },
    lrsp => {
	name => "Living Reviews in Solar Physics",
	subdomain => "solarphysics",
	issn => "1614-4961",	
	start_year => 2004,
    }, 
    lreg => {
	name => "Living Reviews in European Governance",
	subdomain => "europeangovernance",
	issn => "1813-856X",	
	start_year => 2006,
    }, 
};

sub api_version {
  1;
}

sub name {
  'Living Reviews';
}

sub version {
  '1.2';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless parse_uri($uri);
  return 1;
}

#
# defect: incomplete! implement understands_id and citations_id
#

sub citations {
  my ($self, $uri) = @_;
  my $parsed_uri = parse_uri($uri);

  return undef unless($parsed_uri != 0);

  my $meta_uri = $self->meta_uri($parsed_uri);
  my $meta_xml;

  eval { $meta_xml = $self->get($meta_uri) };
  if ($@) {
    $self->errstr($@);
    return undef;
  }
  my $raw_citation = $self->raw_parse_xml($meta_xml);

  $raw_citation->{'uri'} = $uri->as_string;
  $raw_citation->{'meta_uri'} = $meta_uri->as_string;
  $raw_citation->{'journal'} = $parsed_uri->{'journal'}->{'name'};
  $raw_citation->{'issn'} = $parsed_uri->{'journal'}->{'issn'};

  if ($parsed_uri->{'pubNo'} =~ /^[^-]+-(\d{4})-(\d+)$/) {
    $raw_citation->{'volume'} = $1 - $parsed_uri->{'journal'}->{'start_year'} + 1;
    $raw_citation->{'issue'} = $2;
  } else {
    $raw_citation->{'volume'} = 0;
    $raw_citation->{'issue'} = 0;
  }
  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::LivingReviews->new($raw_citation));
}

sub parse_uri {
  my $uri = shift;
  my ($journal, $pubNo, $key);
  my ($subdomain, $domain) = split(/\./, $uri->host, 2);

  return 0 unless $uri->scheme eq 'http';
  return 0 unless $domain eq 'livingreviews.org';

  if ($subdomain eq 'www') {
    # path must be a living reviews publication id!
    if ($uri->path =~ m!^/(lrr|lreg|lrsp)-(\d{4}-\d+)$!) {
      return {journal => $JOURNALS->{$1}, pubNo => join('-', $1, $2)};
    }
  } else {
    foreach $key (keys(%{$JOURNALS})) {
      my $value = $JOURNALS->{$key};	
      if ($subdomain eq $value->{'subdomain'}) { 
	if ($uri->path =~ m!^/Articles/$key-(\d{4}-\d+)(/.+)?!) {
	  return {journal => $value, pubNo => join('-', $key, $1)};
	}
	last;
      }
    }
  }
  return 0;
}

sub meta_uri {
  my ($self, $parsed_uri) = @_;
  my $subdomain = $parsed_uri->{'journal'}->{'subdomain'};
  my $pubNo = $parsed_uri->{'pubNo'};
  my $new_uri = 'http://'.$subdomain.'.livingreviews.org/Articles/'.$pubNo.'/metadata.rdf';
  return URI->new($new_uri);
}

sub raw_parse_xml {
  my ($self, $xml) = @_;
  my $citation;
  my $twig = XML::Twig->new;
  my $res = undef;
  my @creators;

  $twig->parse($xml);

  $res = $twig->get_xpath('//dc:title', 0);
  if ($res) {
    $citation->{'title'} = $res->text();
  }

  foreach $res ($twig->get_xpath('//dc:creator/rdf:Bag/rdf:li')) {
    push @creators, $res->text();
  }
  $citation->{'authors'} = \@creators;

  $res = $twig->get_xpath('//dc:publisher', 0);
  if ($res) {
    $citation->{'publisher'} = $res->text();
  }

  $res = $twig->get_xpath('//dcterms:issued', 0);
  if ($res) {
    $citation->{'pubdate'} = $res->text();
  }

  $res = $twig->get_xpath('//dc:identifier', 0);
  if ($res) {
    $citation->{'pubNo'} = $res->text();
  }

  $citation->{'language'} = 'en';

  return $citation;
}

package Bibliotech::CitationSource::Result::LivingReviews;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource::Result';

sub new {
  my ($class, $citation) = @_;
  return bless {'citation' => $citation}, $class;
}

sub type {
  my $self = shift;
  return 'Living Reviews Article';
}

sub source {
  my $self = shift;
  return $self->{'citation'}->{'meta_uri'};
}

sub identifiers {
  my $self = shift;
  return {'livingreviews' => $self->{'citation'}->{'pubNo'}, 'doi' => undef};
}

sub title {
  my $self = shift;
  return $self->{'citation'}->{'title'};
}


# return an object of author objects: Bibliotech::CitationSource::Result::AuthorList
sub authors {
  my $self = shift;
  return Bibliotech::CitationSource::Result::AuthorList->new(map { Bibliotech::CitationSource::Result::Author::LivingReviews->new($_) } @{$self->{'citation'}->{'authors'}} );
}

# return a journal object: Bibliotech::CitationSource::Result::Journal
sub journal {
  my $self = shift;
  return Bibliotech::CitationSource::Result::Journal::LivingReviews->new($self->{'citation'}); 
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
  return $self->{'citation'}->{'pubdate'};
}

# return date record was created or last modified, same format as date()
# required - do not return undef
sub last_modified_date {
  return shift->date;
}

sub page {
  my $self = shift;
  return 0;
}



package Bibliotech::CitationSource::Result::Author::LivingReviews;
#
# author names are formatted as "First Initials Last", where Initials is a 
# sequence of capital letters ending with a '.'.
#
use strict;

#
# defect: the following function to parse names is not used yet!
#
sub parse_name {
  my @firstname = undef;
  my @initials = undef;
  my @lastname = undef;
  my $part = undef;

  foreach $part (reverse(split(/\s+/, shift))) {
    if (@lastname < 2) {
      push @lastname, $part;
    } else {
      if ($part =~ /\./) {
	push @initials, $part;
      } else {
	push @firstname, $part;
      }
    }
  }
  return {
    'firstname' => join(' ', reverse(@firstname)),
    'initials' => join(' ', reverse(@initials)),
    'lastname' => join(' ', reverse(@lastname)),
  };
}

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
  return undef;
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

package Bibliotech::CitationSource::Result::Journal::LivingReviews;
use strict;

sub new {
  my ($class, $citation) = @_;
  return bless {'name' => $citation->{'journal'}, 'issn' => $citation->{'issn'}}, $class;
}

# return as many of these strings as possible:
sub name           { return shift->{'name'}; }
sub issn           { return shift->{'issn'}; }

1;
__END__
