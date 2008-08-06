# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::Amazon class retrieves citation data for books
# on Amazon.com.

package Bibliotech::CitationSource::Amazon;

use strict;
use warnings;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';
use Bibliotech::CitationSource::Simple;

sub api_version {
  1;
}

sub name {
  'Amazon';
}

sub version {
  '1.3';
}

sub understands {
  my ($self, $uri) = @_;
  $self->awsid or return 0;
  return 0 unless $uri->scheme eq 'http';
  return 0 unless $uri->host =~ m/^(?:www\.)?amazon\.(?:com|co\.uk|de|fr|co\.jp|ca)$/;
  return 0 unless $uri->path =~ m!/\d{9}(?:\d|X)/!i;
  return 1;
}

sub citations {
  my ($self, $uri) = @_;
  my $meta_uri = _amazon_meta_uri($uri, $self->awsid)
      or $self->errstr('Unable to construct AWS URI for '.$uri), return;
  my $meta_xml = $self->content_or_set_errstr(sub { $self->get($meta_uri) }) or return;
  my $raw_citation = _raw_parse_amazon_xml($meta_xml);
  $raw_citation->{'title'} && $raw_citation->{'authors'}
      or $self->errstr('Insufficient metadata extracted for '.$uri), return;
  $raw_citation->{'uri'} = $uri->as_string;
  $raw_citation->{'meta_uri'} = $meta_uri->as_string;
  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::Simple->new($raw_citation));
}

sub _amazon_meta_uri {
  my ($uri, $awsid) = @_;
  my ($locale) = ($uri->host =~ m!^(?:www.)?amazon(.+)$!) or return;
  my ($asin)   = ($uri->path =~ m!/(\d{9}(?:\d|X))/!)     or return;
  return URI->new('http://webservices.amazon'.$locale.
		  '/onca/xml?Service=AWSECommerceService&SubscriptionId='.$awsid.
		  '&Operation=ItemLookup&IdType=ASIN&ItemId='.$asin.'&ResponseGroup=Small');
}

sub _raw_parse_amazon_xml {
  my $xml = shift;

  my $citation;
  my @items = ($xml =~ m!<Item>(.*?)</Item>!sg);
  return undef unless scalar(@items) == 1;

  if($items[0] =~ m!<ASIN>(.+?)</ASIN>!s) {
    $citation->{'asin'} = $1;
  }
  if($items[0] =~ m!<Title>(.+?)</Title>!s) {
    $citation->{'title'} = $1;
  }
  while($items[0] =~ m!<Author>(.+?)</Author>!sg) {
    push @{$citation->{'authors'}}, $1;
  }
  #try Creator if no Author
  if(! $citation->{'authors'}) {
    while($items[0] =~ m!<Creator.*?>(.+?)</Creator>!sg) {
      push @{$citation->{'authors'}}, $1;
    }
  }

  return $citation;
}

sub awsid {
  shift->cfg('AWSID');
}

1;
__END__
