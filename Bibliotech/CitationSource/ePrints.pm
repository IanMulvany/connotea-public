# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::ePrints class retrieves citation data for articles
# on an ePrints supported website using an open archives initiative protocol for metadata harvesting (OAI-PMH)

package Bibliotech::CitationSource::ePrints;

use strict;
use warnings;

use Bibliotech::CitationSource;
use base 'Bibliotech::CitationSource';

use Bibliotech::CitationSource::Simple;

use Data::Dumper;
use XML::LibXML;
use XML::LibXML::NodeList;

use HTTP::OAI::Harvester;
use constant VERSION => '2.0'; 	        # version for Harvester Identify
use constant META_PREFIX => 'oai_dc';   # return dublin core metadata
use constant OAI_BASE => '/perl/oai2';

sub api_version {
  1;
}

sub name {
  'ePrints';
}

sub version {
  '1.3.2.1';
}

sub understands {
  my ($self, $uri) = @_;
  return 0 unless $uri->scheme =~ /^http$/i;
  return 0 unless Bibliotech::CitationSource::ePrints::HostTable::defined($uri->host);
  return 1 if $uri->path;
  return 0;
}

sub citations {
  my ($self, $uri) = @_;

  my $understands = $self->understands($uri);
  return undef unless $understands;

  my $art_id = $self->get_art_id($uri);
  return undef unless $art_id;

  # OAI set base/prefix
  my $port = ':' . $uri->port if $uri->port;
  my $oai_base_url = 'http://' . $uri->host . $port . OAI_BASE;
  my $oai_prefix = Bibliotech::CitationSource::ePrints::HostTable::getOAIPrefix($uri->host);

  my $metadata = $self->metadata($art_id, $oai_base_url, $oai_prefix);
  return undef unless $metadata;

  return Bibliotech::CitationSource::ResultList->new(Bibliotech::CitationSource::Result::Simple->new($metadata));
}

#
# The ePrints OAI service (OAI2) provides access to metadata of all items in any ePrints website, 
#
sub metadata {
  my ($self, $art_id, $base, $prefix) = @_;
  my $xml;

  #
  # harvest the ePrints static repository with the Identify method, at baseURL 
  #	already know the Identify object
  # 
  # set bibliotech object
  #
  my $h = HTTP::OAI::Harvester->new(bibliotech => $self->bibliotech,
				    repository => HTTP::OAI::Identify->new( baseURL=> $base, version=> VERSION));

  #
  # get corresponding record for $art_id from repository
  #
  my ($gr) = $h->GetRecord(identifier => $prefix.':'.$art_id,  # required
			   metadataPrefix => META_PREFIX);     # required
  if ($gr->is_error) {
    $self->errstr('GetRecord Error: '.$gr->message);
    return undef;
  }
  if ($gr->errors) {
    $self->errstr('GetRecord Error for '.$art_id);
    return undef;
  }

  #
  # get first record from GetRecord object (first record stored in response)
  #	??how likely will it be to have multiple records returned for an artid??
  #
  my ($rec) = $gr->next;

  unless ($rec) {
    $self->errstr("No records");
    return undef;
  }

  # get the parsed DOM tree
  my ($dom) = $rec->metadata->dom;

  # go get the metadata from tree
  my $metadata = $self->build_metadata($dom);
  return undef unless $metadata;

  # check that it's worth returning
  unless($metadata->{'title'} && $metadata->{'pubdate'}) {
    $self->errstr('Insufficient metadata extracted for artid: '.$art_id);
    return undef;
  }

  return $metadata;
}

# eprints URL looks like: 	http://ws.fetter.us:8080/5/
#				http://eprints.bibl.hkr.se/archive/23
# grab what is after the last slash
# according to eprints website
sub get_art_id {
  my ($self, $uri) = @_;

  my ($path) = $uri->path;
  ($path) =~ s,/$,,;  # strip trailing slash, if any

  #strip suffix, if any
  # 	ex. (http://memsic.ccsd.cnrs.fr)
  #	/mem_00000001.en.html
  ($path) =~ s,\.(.*?)$,,;

  $path =~ m,([^/]*)$,;
  my ($art_id) = $1;

  return $art_id;
}

sub build_metadata {
  my ($self, $dom) = @_;

  my $root = $dom->getDocumentElement;

  unless ($root) {
    $self->errstr("no root");
  }

  # ex: <dc:title>Title</dc:title>
  my $title = getFirstElement($root, 'title');
  my $date = getFirstElement($root, 'date');
  my $url = getFirstElement($root, 'identifier');
  #SUE does 'relation' contain doi?  do a pattern match and return doi or undef

  #		get the author info
  my ($authors);
  $authors = &getAuthors($root);

  #convert nodes to strings, checking for undef first.
  ($title, $date, $url) = map { $_->string_value if $_ } ($title, $date, $url);

  return { 
    title => $title,
    pubdate => $date,
    #doi => $doi,
    url => $url,
    authors => $authors
  };
}

sub getAuthors {
  my ($root) = @_;

  my(@auList);

  # build names foreach creator
  #foreach my $c ($root->getElementsByLocalName('creator')->string_value) {
  foreach my $x ($root->getElementsByLocalName('creator')) {
    my $c = $x->string_value;

    # ex. Toth, Fred
    my($l, $f) = $c =~ m/(.*?), (.*?)$/;

    my $name;
    $name->{'forename'} = $f if $f;
    $name->{'lastname'} = $l if $l;

    push(@auList, $name) if $name;
  }
  return \@auList if @auList;
  return undef unless @auList;
}

#
# get the first element in the array returned by getElementsByLocalName
#
sub getFirstElement {
  my ($node, $name) = @_;
  my @values = $node->getElementsByLocalName($name);
  return($values[0]);
}

package Bibliotech::CitationSource::ePrints::HostTable;
%Bibliotech::CitationSource::ePrints::HostTable::Hosts = (
	# Host (without Port)		=>		OAI Prefix
	# test eprints
	'ws.fetter.us'			=>	'oai:GenericEPrints.ab',
	'eprints.bibl.hkr.se'		=>	'oai:eprints.bibl.hkr.se.oai2',

	#Australia National University - E-Print Repository
	'eprints.anu.edu.au'		=> 	'oai:eprints.anu.edu.au',

	#Indian Institute of Science - eprints@iisc
	'eprints.iisc.ernet.in'		=> 'oai:iiscePrints.OAI2',

	#NUI Maynooth - Eprint Archive
	'eprints.may.ie'		=> 'oai:GenericEPrints.OAI2',

	#Universitàegli studi di Trento - UNITN-eprints
	'eprints.biblio.unitn.it' 	=> 'oai:UNITN.Eprints',

	#Birkbeck College, University of London - Birkbeck ePrints
	'eprints.bbk.ac.uk'		=> 'oai:BirkbeckEPrints.OAI2',

        #SUE added prefix (from epapers.bham.ac.uk/perl/oai2?verb=Identify), but it doesn't conform (needs .xxx)
	#University of Birmingham - Birmingham ePapers
	#'epapers.bham.ac.uk'		=> 'oai:GenericEPrints',	# bad form

	#The British Library - British Library Research Archive
	#'sherpa.bl.uk'			=> 'oai:GenericEPrints',	# bad form

	#University of Durham - Durham e-Prints
	'eprints.dur.ac.uk'		=> 'oai:GenericEPrints.OAI2',

	#University of Glasgow - Glasgow ePrints Service
	'eprints.gla.ac.uk'		=> 'oai:eprints.gla.ac.uk',				

	#Kings College - Kings ePrints Archive
	'eprints.kcl.ac.uk'		=> 'oai:eprints.kcl.ac.OAI2',

#SUE added prefix (from /perl/oai2?verb=Identify)
	#London School of Economics - LSE ePrints Archive
	'eprints.lse.ac.uk'		=> 'oai:GenericEPrints.OAI2',

	#Royal Holloway - Royal Holloway Scholarship Online
	'eprints.rhul.ac.uk'		=> 'oai:RoyalHollowayResearchOnline.OAI2',

	#School of Oriental and African Studies - SOAS Online Research Repository
	'eprints.soas.ac.uk'		=> 'oai:eprints.soas.ac.uk.OAI2',

	#University College - UCL ePrints
	'eprints.ucl.ac.uk'		=> 'oai:eprints.ucl.ac.uk.OAI2',

	#University of Nottingham - Nottingham ePrints
	'eprints.nottingham.ac.uk'	=> 'oai:eprints.nottingham.ac.uk.OAI2',

	#Universities of Leeds, Sheffield, & York - White Rose Consortium ePrints Repository
	'eprints.whiterose.ac.uk'	=> 'oai:leeds.ac.uk:sherpa',

	#Open University - The Open University Library s e-prints Archive
	'libeprints.open.ac.uk'		=> 'oai:open.ac.uk.OAI2',

	#Oxford University Maths - The Mathematical Institute Eprints Archive
	'eprints.maths.ox.ac.uk'	=> 'oai:eprints.maths.ox.ac.uk',

	#Southampton Psychology - PsycPrints
	'psycprints.ecs.soton.ac.uk'	=> 'oai:psycprints.ecs.soton.ac.uk',

	#PASCAL - PASCAL EPrints
	'eprints.pascal-network.org'	=> 'oai:eprints.pascal-network.org',

	#Oxford University - Pxford Eprints
	'eprints.ouls.ox.ac.uk'		=> 'oai:OxfordEPrints.OAI2',

	#University of Nottingham  - Nottingham eTheses
	'etheses.nottingham.ac.uk'	=> 'oai:etheses.nottingham.ac.uk.OAI2',

	#University of Nottingham  - Notthingham ePrints
	'eprints.nottingham.ac.uk'	=> 'oai:eprints.nottingham.ac.uk.OAI2',

	#University of Nottingham - Modern Languages Publications Archive
	'mlpa.nottingham.ac.uk'		=> 'oai:mlpa.nottingham.ac.uk.OAI2',

	#University of Southampton - IPv6 Eprints Server
	'www.6journal.org'		=> 'oai:IPv6.EPrints.Server',

	#Electronic Resource Preservation and Access Network (ERPANET) and the Digital Curation Centre (DCC) - ERPAePRINTS Service
	'eprints.erpanet.org'		=> 'oai:eprints.erpanet.org',

	#Electronics and Computer Science, Southampton University - ECS EPrints Service
	'eprints.ecs.soton.ac.uk'	=> 'oai:eprints.ecs.soton.ac.uk',

	#University of Southampton - e-Prints Soton
	'eprints.soton.ac.uk'		=> 'oai:eprints.soton.ac.uk',

	#School of Information Resources and Library Science  and Learning Technologies Center, University of Arizona - DLIST Archive 
	'dlist.sir.arizona.edu'		=> 'oai:DLIST.OAI2',

	#University of Lincoln - Applied Computing Sciences ePrints Service
	'eprints.lincoln.ac.uk'		=> 'oai:eprints.lincoln.ac.uk',

	#AKT - AKT EPrints Archive
	'eprints.aktors.org'		=> 'oai:aktors.org',

	#Cognitive Science, University of Southampton - COGPrints
	'cogprints.ecs.soton.ac.uk'		=> 'oai:cogprints.soton.ac.uk',
	'cogprints.org'	    	                => 'oai:cogprints.soton.ac.uk',

	#St Andrews University - STAEPrints
	'eprints.st-andrews.ac.uk'		=> 'oai:GenericEPrints.OAI2.OAI',

	#11th Joint Symposium on Neural Computation - 11th Joint Symposium on Neural Computation
	'jsnc.library.caltech.edu'		=> 'oai:jsnc.library.caltech.edu',

	#l'ENS Lettres et Sciences Humaines de Lyon - l'Archive ENS LSH
        # Identify says oai:ArchiveEnslsh.OAI2, is this an alias? it works
	'eprints.ens-lsh.fr'		=> 'oai:ArchiveEnslsh',

	#University of Pittsburgh - Archive of European Integration
	'aei.pitt.edu'		=> 'oai:PITTAEI.OAI2',

	# Faculty of Computer and Information Science (FRI), University of Ljubljana - Eprints.FRI
	'eprints.fri.uni-lj.si'		=> 'oai:ePrints.FRI.OAI2',

	#Indian Institute of Science - ePrints@IISC
	'eprints.iisc.ernet.in'		=> 'oai:iiscePrints.OAI2',

	#SLU, Swedish University of Agricultural Sciences - EPSILON
	'diss-epsilon.slu.se'		=> 'oai:epsilondiss.OAI2',

	#Erasme : systè d'information documentaire de l'INPT - Erasme : systè d'information documentaire de l'INPT
	'ethesis.inp-toulouse.fr'		=> 'oai:ethesis.inp-toulouse.fr',

	#Monash University - Monash University ePrint Repository
	'eprint.monash.edu.au'		=> 'oai:Monash.OAI',

	#Communication and Information Sciences - méIC 
# Identify says oai:memsic.ccsd.cnrs.fr
	'memsic.ccsd.cnrs.fr'		=> 'oai:memsic.ccsd.cnrs.fr',

	#National Aerospace Laboratory - National Aerospace Laboratory Institutional Repository
	'nal-ir.nal.res.in'		=> 'oai:nal-ir.nal.res.in',

	#University of Pittsburgh - PhilSci
	'philsci-archive.pitt.edu'		=> 'oai:PittPhilSci.OAI2',

	#Rhodes University - Rhodes eReseach Repository
	'eprints.ru.ac.za'		=> 'oai:eprints.ru.ac.za',

	#STOA - KF-eprints
	'eprints.stoa.it'		=> 'oai:eprints.stoa.it',

	#University of Trento - unitn.it eprints
	'eprints.biblio.unitn.it'		=> 'oai:UNITN.Eprints',

	#Victoria University ePrints Repository - Victoria University Eprints Repository
	'eprints.vu.edu.au'		=> 'oai:vu.edu.au',

	#Bond University - School of Information Technology ePrints Repository
	'eprints.it.bond.edu.au'		=> 'oai:eprints.it.bond.edu.au',

	#University of Tasmania - UTasER
	'eprints.comp.utas.edu.au'		=> 'oai:UTasERprototype',

	#Bioline International - Bioline
	'bioline.utsc.utoronto.ca'		=> 'oai:BiolineEPrints.OAI2',

	#Dryden Flight Research Center, NASA - Dryden Technical Reports Server
	'dtrs.dfrc.nasa.gov'		=> 'oai:NASA-DTRS-EPRINTS.OAI2',

	#University of Otago Eprints Repository - University of Otago
	'eprints.otago.ac.nz'			=> 'oai:eprints.otago.ac.nz',


	#Added on request
	#
        
        #Organic eprints
	'orgprints.org'                          =>        'oai:orgprints.org',

        #Eprints in Library and Information Science
        'eprints.rclis.org'                      =>        'oai:eprints.rclis.org',

);

my ($hRef) = \%Bibliotech::CitationSource::ePrints::HostTable::Hosts;

sub defined {
  my ($host) = @_;

  return 1 if defined($hRef->{$host});
  if ($host =~ s/^www\.//) {
    return defined($hRef->{$host});
  }

  return 0;
}

sub getOAIPrefix {
  my ($host) = @_;

  return $hRef->{$host} if $hRef->{$host};
  $host =~ s/^www\.//;
  return $hRef->{$host};
}

1;
__END__
