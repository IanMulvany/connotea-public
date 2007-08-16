# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::arXiv class retrieves citation data for articles
# on arXiv.org using an open archives initiative protocol for metadata harvesting (OAI-PMH)
#
# Only test a few urls at a time.  arXiv.org will block access if they detect accelerated fetching.
# access is blocked for about a week.
#

package Bibliotech::CitationSource::arXiv;

use strict;
use warnings;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';

use Bibliotech::CitationSource::Simple;

use Data::Dumper;
use XML::LibXML;
use XML::LibXML::NodeList;

use HTTP::OAI::Harvester;
use constant VERSION => '2.0'; 					# version for Harvester Identify
use constant OAI_BASE_URL => 'http://www.arXiv.org/oai2';	# baseURL for Harvester Identify
use constant META_PREFIX => 'oai_dc';				# return metadata in dublin core format
use constant OAI_PREFIX => 'oai:arXiv.org';			# prefix for Harvester GetRecord() identifier

sub api_version
{
  1;
}

sub name
{
  'arXiv';
}

sub version
{
  '1.2.2.1';
}

sub understands
{
	my ($self, $uri) = @_;

	#check the host
	return 0 unless ($uri->scheme =~ /^http$/i);

	# check for mirrors: ex.  uk. ru. aps. lanl. ...
	return 0 unless ($uri->host =~ m/^((...?|lanl)\.)?arxiv\.org$/);
	#return 0 unless ($uri->host =~ m/^(www\.)?arxiv\.org$/);

	#check path for id
	#	ex. abs/hep-th/0404156
	return 1 if ($uri->path =~ m,/abs/.*?/[0-9]+,);

	return 0;
}

sub citations
{
	my ($self, $uri) = @_;

	return undef unless($self->understands($uri));

	my $art_id = $self->get_art_id($uri);
	return undef unless $art_id;
	 
	my $metadata = $self->metadata($art_id);

	return undef unless $metadata;

	return new Bibliotech::CitationSource::ResultList(Bibliotech::CitationSource::Result::Simple->new($metadata));
}

#
# The arXiv OAI service provides access to metadata of all items in the arXiv archive.
#
sub metadata
{
    my ($self, $art_id) = @_;
    my $xml;

	#
	# harvest the ArXiv OAI static repository with the Identify method, at baseURL 
	#	already know the Identify object
	#
	my $h = HTTP::OAI::Harvester->new(bibliotech => $self->bibliotech,
		repository=>HTTP::OAI::Identify->new( baseURL=> OAI_BASE_URL, version=> VERSION)
	);
	#
	# get corresponding record for $art_id from repository
	#
	my($gr) = $h->GetRecord(
			identifier => OAI_PREFIX . ":" . $art_id,	# required
			metadataPrefix => META_PREFIX			# required
	);

	unless($gr->is_success) {
		$self->errstr('GetRecord Error: ' . $gr->message);
		return undef;
	}

	#
	# get first record from GetRecord object (first record stored in response)
	#
	my($rec) = $gr->next;
	if($rec->is_error) {
		$self->errstr($rec->message);
		return undef;
	}

	#
	# could be helpful
	#
	#$self->errstr($rec->identifier . " (" . $rec->datestamp . ")");

	# get the parsed DOM tree
	#	in dublin core format (dc)
	my($dom) = $rec->metadata->dom;

	# go get the metadata from document
	my $metadata = $self->build_metadata($dom);
	return undef unless $metadata;

	# check that it's worth returning
	unless($metadata->{'title'} && $metadata->{'pubdate'})
	{
		$self->errstr('Insufficient metadata extracted for artid: ' . $art_id);
		return undef;
	}

	return $metadata;
}

sub get_art_id {
    my ($self, $uri) = @_;

    my ($art_id) = $uri->path =~ m,/abs/(.*?)$,i;
    return $art_id;
}

sub build_metadata 
{
	my ($self, $dom) = @_;

	my $root = $dom->getDocumentElement;
	unless ($root) {
		$self->errstr("no root");
	}

	my $title = getFirstElement($root, 'title');
	my $date = getFirstElement($root, 'date');
	my $url = getFirstElement($root, 'identifier');

	#	get the author info
	my($authors);
	$authors = &getAuthors($root);

	# convert nodes to strings, checking for undef first
	($title, $date, $url) = map { $_->string_value if $_ } ($title, $date, $url);

	return {
		title => $title,
		pubdate => $date,
		url => $url,
		authors => $authors,
		#doi => $doi,	# may be in 'relation', didn't see any in arXiv test
        }; 
}

#
# get the first element in the array returned by getElementsByLocalName
#
sub getFirstElement {
	my ($node, $name) = @_;
	my @values = $node->getElementsByLocalName($name);
	return($values[0]);
}

sub getAuthors {
	my ($root) = @_;

	my(@auList);

	# build names foreach creator
	foreach my $x ($root->getElementsByLocalName('creator')) {
		my $c = $x->string_value;
		my $name;

		# Makidon, Russell - strip comma
		my($l, $f) = $c =~ m/(.*?),? (.*?)$/;

		$name->{'forename'} = $f if $f;
		$name->{'lastname'} = $l if $l;

		push(@auList, $name) if $name;
	}
	return \@auList if @auList;
	return undef unless @auList;
	#return "No Authors" unless @auList;
}

#sub errstr {
    #my ($self, $err) = @_;
#
    #print STDERR $self->name . " " . $err . "\n";
#}

#true!
1;
