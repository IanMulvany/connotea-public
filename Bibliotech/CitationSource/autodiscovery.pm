# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::autodiscovery class retrieves citation data for BioMed Central journals
#		1. parse the HTML of the URL, to get the citation metadata (embedded RDF in a comment)
#		2. parse RDF with RDF::Core::Model::Parser to get citation data
#

package Bibliotech::CitationSource::autodiscovery;
use strict;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';
use Bibliotech::CitationSource::Simple;
use HTTP::Request::Common;
use URI;
use URI::QueryParam;

sub api_version {
  1;
}

sub name {
  'autodiscovery';
}

sub cfgname {
  'autodiscovery';
}

sub version {
  '1.1.2.6';
}

sub potential_understands {
  2;
}

sub understands {
  my ($self, $uri, $content_sub) = @_;

  return 0 unless $uri->scheme eq 'http';

  my $content = $self->content_or_set_warnstr($content_sub, ['text/html', 'application/xhtml+xml'])
      or return -1;

  # check html for RDF data, else return 0
  $self->{rdf_content} = getRDFinaComment($content)
      or return 0;

  my ($ok, $metadata) = $self->catch_transient_warnstr(sub {
    Bibliotech::CitationSource::autodiscovery::Metadata->new($self->{rdf_content}, $uri);
  });
  $ok or return 0;

  return 0 unless $metadata;
  $self->{metadata} = $metadata;

  # since this is a less specific plug-in, return a 2 in the event a
  # more specific plug-in recognizes this site; the blog plug-in
  # returns 3, so embedded metadata is prefered to linked metadata
  return 2;
}

sub getRDFinaComment {
  my $content = shift or return;
  local $/ = undef;
  my ($rdf) = $content =~ m,<!--\s+(<rdf:RDF.+?</rdf:RDF>)\s+-->,gs;
  return $rdf;
}

sub citations {
  my ($self, $uri, $content_sub) = @_;
  my $metadata = eval {
    die "do not understand URI\n" unless $self->understands($uri, $content_sub);
    die "RDF obj false\n" unless $self->{metadata};
    die "RDF file contained no data\n" unless $self->{metadata}->{'has_data'};
    return $self->{metadata};
  };
  if ($@) {
    $self->errstr($@);
    return undef;
  }
  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::Simple->new($metadata));
}

package Bibliotech::CitationSource::autodiscovery::Metadata;
use base 'Class::Accessor::Fast';
use RDF::Core::Storage::Memory;
use RDF::Core::Model;
use RDF::Core::Model::Parser;
use RDF::Core::Resource;

__PACKAGE__->mk_accessors(qw/doi volume issue journal title author pubdate url has_data/);

#
# needed for RDF::Core::Resource
#		may need to add more resource locations if future sites using the "RDF in a comment" scheme
#		use models other than DC and PRISM.
#
use constant DC_LOC => 'http://purl.org/dc/elements/1.1/';
use constant PRISM_LOC => 'http://prismstandard.org/namespaces/1.2/basic/';

# 
# parse with RDF::Core::Model::Parser 
#
sub new {
  my ($class, $rdf_content, $url) = @_;
  my $self = {};
  my $storage = RDF::Core::Storage::Memory->new;
  my $model = RDF::Core::Model->new(Storage => $storage);
  my $parser = RDF::Core::Model::Parser->new(Model      => $model,
					     BaseURI    => $url,
					     Source     => $rdf_content, 
					     SourceType => 'string');
  bless $self, ref $class || $class;
  $self->has_data(0);
  $self->parse($model, $parser);
  return $self;
}

sub parse {
  my($self, $model, $parser) = @_;
  $parser->parse;
  my $id = $self->getElement($model, DC_LOC, "identifier");
  my $doi;
  $doi = $id if $id =~ m/doi/;
  my $pname = $self->getElement($model, PRISM_LOC, "publicationName");
  my $pdate = $self->getElement($model, DC_LOC, "date");
  my $volume = $self->getElement($model, PRISM_LOC, "volume");
  my $issue = $self->getElement($model, PRISM_LOC, "number");
  my $pageNo = $self->getElement($model, PRISM_LOC, "startingPage");
  my $title = $self->getElement($model, DC_LOC, "title");

  my ($authors) = $self->getAuthors($model, DC_LOC, "creator");

  #check it's worth returning
  unless ($pname && $pdate) {
    die "Insufficient metadata extracted for doi: [$doi]\n";
  }

  # clean doi
  my $new = $doi;
  $new =~ s,info:doi/(.*?)$,$1,g;
  $doi = $new if $new;

  # clean date ex. 2006-09-19T07:18:02-05:00
  ($new) = $pdate =~ m,([\d-]+),g;
  $pdate = $new if $new;

  # load the results
  $self->{'has_data'} = 1;
  $self->{'doi'} = $doi;
  $self->{'journal'}->{'name'} = $pname;
  $self->{'volume'} = $volume;
  $self->{'issue'} = $issue;
  $self->{'title'} = $title;
  $self->{'pubdate'} = $pdate;
  $self->{'page'} = $pageNo;
  $self->{'authors'} = $authors;
}

#
# use this method when only one instance
#
sub getElement {
  my($self, $model, $resource_loc, $element) = @_;

  my $resource = RDF::Core::Resource->new($resource_loc . "$element");
  my $resource_enum=$model->getStmts(undef, $resource, undef);

  my $label = '';
  my $stmt = $resource_enum->getFirst;

  if (defined $stmt) {
    $label = $stmt->getObject->getLabel;
  }

  return $label;
}

#
# use this method when multiple instances
#
sub getList {
  my ($self, $model, $resource_loc, $element) = @_;

  my $resource = RDF::Core::Resource->new($resource_loc."$element");
  my $resource_enum=$model->getStmts(undef, $resource, undef);

  my @list;
  my $stmt = $resource_enum->getFirst;
  while (defined $stmt) {
    my $label = $stmt->getObject->getLabel;

    push (@list, $label);
    $stmt = $resource_enum->getNext;
  }

  return @list;
}

sub getAuthors {
  my ($self, $model, $resource_loc, $element) = @_;

  my @auList;
  my (@list) = $self->getList($model, $resource_loc, $element);

  # build names foreach author
  # ex. Reguly, Teresa
  foreach my $author (@list) {
    my($l, $f) = $author =~ /^(.*),\s+(.+)$/;

    my $name;
    $name->{'forename'} = $f if $f;
    $name->{'lastname'} = $l if $l;
    push(@auList, $name) if $name;
  }

  return \@auList if @auList;
  return undef unless @auList;
}

1;
__END__
