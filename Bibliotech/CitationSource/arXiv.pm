# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::arXiv class retrieves citation data
# for articles on arXiv.org using an open archives initiative protocol
# for metadata harvesting (OAI-PMH)
#
# Only test a few urls at a time.  arXiv.org will block access if they
# detect accelerated fetching.  Access is blocked for about a week.

package Bibliotech::CitationSource::arXiv;
use base 'Bibliotech::CitationSource';
use strict;
use warnings;
use Bibliotech::Util qw(parse_author);
use Bibliotech::CitationSource::Simple;
use XML::LibXML;
use XML::LibXML::NodeList;
use HTTP::OAI::Harvester;
use HTTP::OAI::UserAgent;
use HTTP::OAI::Identify;
use Bibliotech::DBI;
use Bibliotech::UserAgent;

use constant VERSION      => '2.0'; 			   # version for Harvester Identify
use constant OAI_BASE_URL => 'http://www.arXiv.org/oai2';  # baseURL for Harvester Identify
use constant META_PREFIX  => 'oai_dc';			   # return metadata in dublin core format
use constant OAI_PREFIX   => 'oai:arXiv.org:';		   # prefix for Harvester GetRecord() identifier

sub api_version {
  1;
}

sub name {
  'arXiv';
}

sub version {
  '1.3';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless $uri->host =~ m/^((...?|lanl)\.)?arxiv\.org$/;
  return 0 unless _art_id_from_url($uri);
  return 1;
}

sub _art_id_from_url {
  my $uri = shift;
  $uri->path =~ m,/abs/(.+)$,i and return $1;
  return;
}

sub citations {
  my ($self, $uri) = @_;
  my $metadata = $self->metadata(_art_id_from_url($uri)) or return undef;
  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::Simple->new($metadata));
}

# The arXiv OAI service provides access to metadata of all items in the arXiv archive.
sub metadata {
  my ($self, $art_id) = @_;
  my $metadata = eval {
    my $h = HTTP::OAI::Harvester->new
	(bibliotech => $self->bibliotech,
	 repository => HTTP::OAI::Identify->new(baseURL => OAI_BASE_URL, version=> VERSION))
	or die 'no Harvestor object';

    my $gr = $h->GetRecord(identifier     => OAI_PREFIX.$art_id,
			   metadataPrefix => META_PREFIX);
    $gr->is_success or die 'GetRecord Error: '.$gr->message."\n";

    # get first record from GetRecord object (first record stored in response)
    my $rec = $gr->next;
    die $rec->message."\n" if $rec->is_error;

    # get the parsed DOM tree in dublin core format (dc)
    my ($dom) = $rec->metadata->dom;
    my $m = $self->build_metadata($dom) or die 'no metadata';
    ($m->{'title'} && $m->{'pubdate'}) or die 'Insufficient metadata extracted for artid: '.$art_id."\n";
    return $m;
  };
  if (my $e = $@) {
    $self->errstr($e);
    return undef;
  }
  return $metadata;
}

sub build_metadata {
  my ($self, $dom) = @_;

  my $root  = $dom->getDocumentElement or $self->errstr('no root'), return undef;
  my $first = sub { my @v = $root->getElementsByLocalName(shift) or return; $v[0]->string_value; };

  return {title   => $first->('title')      || undef,
	  pubdate => $first->('date')       || undef,
	  url     => $first->('identifier') || undef,
	  authors => do { my @authors = map { parse_author($_->string_value)->as_hash }
			                    $root->getElementsByLocalName('creator');
			  @authors ? \@authors : undef }};
}


package HTTP::OAI::UserAgent;
use Carp qw(croak);
use URI;

# Redefine exactly as in the module but add a fix for the colons and
# slashes. The module as published seems to not work. Perhaps a
# dependency (URI?)  has changed behaviour in a newer version.

{
  no warnings 'redefine';
  sub _buildurl {
    my %attr = @_;
    croak "_buildurl requires baseURL" unless $attr{'baseURL'};
    croak "_buildurl requires verb" unless $attr{'verb'};
    my $uri = new URI(delete($attr{'baseURL'}));
    if( defined($attr{resumptionToken}) && !$attr{force} ) {
      $uri->query_form(verb=>$attr{'verb'},resumptionToken=>$attr{'resumptionToken'});
    } else {
      delete $attr{force};
      # http://www.cshc.ubc.ca/oai/ breaks if verb isn't first, doh
      $uri->query_form(verb=>delete($attr{'verb'}),%attr);
    }
    local $_ = $uri->as_string;
    s/\%3A/:/g;
    s/\%2F/\//g;
    return $_;
  }
}

1;
__END__
