# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::CitationSource::RIS class interprets RIS.

use strict;
package Bibliotech::CitationSource::RIS;
use base 'Class::Accessor::Fast';
use Bibliotech::Util;
# used for spec: http://www.refman.com/support/risformat_intro.asp
# read a RIS file and provide back an object that is a hashref of the tags,
# using arrayrefs for tags with multiple values

our %TYPES = (ABST  => 'Abstract',
	      ADVS  => 'Audiovisual material',
	      ART   => 'Art Work',
	      BILL  => 'Bill/Resolution',
	      BOOK  => 'Book, Whole',
	      CASE  => 'Case',
	      CHAP  => 'Book chapter',
	      COMP  => 'Computer program',
	      CONF  => 'Conference proceeding',
	      CTLG  => 'Catalog',
	      DATA  => 'Data file',
	      ELEC  => 'Electronic citation',
	      GEN   => 'Generic',
	      HEAR  => 'Hearing',
	      ICOMM => 'Internet communication',
	      INPR  => 'In Press',
	      JFULL => 'Journal (full)',
	      JOUR  => 'Journal article',
	      MAP   => 'Map',
	      MGZN  => 'Magazine article',
	      MPCT  => 'Motion picture',
	      MUSIC => 'Music score',
	      NEWS  => 'Newspaper',
	      PAMP  => 'Pamphlet',
	      PAT   => 'Patent',
	      PCOMM => 'Personal communication',
	      RPRT  => 'Report',
	      SER   => 'Serial (Book, Monograph)',
	      SLIDE => 'Slide',
	      SOUND => 'Sound recording',
	      STAT  => 'Statute',
	      STD   => 'Standard Citation',
	      THES  => 'Thesis/Dissertation',
	      UNBIL => 'Unenacted bill/resolution',
	      UNPB  => 'Unpublished work',
	      VIDEO => 'Video recording'
	      );

__PACKAGE__->mk_accessors(qw/TY ID T1 TI CT BT T2 BT T3 A1 AU A2 ED A3 Y1 PY Y2 N1 AB N2 KW RP JF JO JA J1 J2
			  VL IS SP EP CP CY PB SN AD AV M1 M2 M3 U1 U2 U3 U4 U5 UR L1 L2 L3 L4 ER
			  has_data inceq/);

sub new {
  my ($class, $data) = @_;
  my $self = {};
  bless $self, ref $class || $class;
  $self->has_data(0);
  $self->inceq(0);  # "include equivalents" - when calling title() do we return just T1 or all of T1, TI, CT, BT
  $self->parse($data) if $data;
  return $self;
}

sub parse {
  my ($self, $input) = @_;
  my $data = Bibliotech::Util::clean_block($input);
  my %values;
  {
    my @lines;
    {
      my @data = ref $data ? map { s/\r?\n$//; $_; } @{$data} : split(/\r?\n/, $data);
      my $in_data = 0;
      my $double_newlines = 0;
      foreach (@data) {
	if ($double_newlines == 1) {
	  $double_newlines = 2;
	}
	elsif ($double_newlines == 2) {
	  if (/^$/) {
	    $double_newlines = 1;
	    next;
	  }
	  else {
	    $double_newlines = 0;
	  }
	}
	if ($in_data) {
	  if (/^ER  - ?/) {
	    $in_data = 0;
	  }
	  else {
	    if (/^\w\w  - ?/) {
	      push @lines, $_;
	    }
	    else {
	      if (@lines) {
		if ($lines[-1] =~ /^TY  - ?/) {
		  $double_newlines = 1;
		}
		else {
		  $lines[-1] .= "\n$_";
		}
	      }
	    }
	  }
	}
	elsif (/^TY  - ?/) {
	  $in_data = 1;
	  $self->has_data(1);
	  push @lines, $_;
	}
      }
    }
    foreach (@lines) {
      my ($key, $value) = /^(\w\w)  - (.*)$/s;
      next unless defined $key && $self->can($key);
      my $stored = $values{$key};
      if (defined $stored) {
	if (ref $stored) {
	  push @{$stored}, $value;
	}
	else {
	  $values{$key} = [$stored, $value];
	}
      }
      else {
	$values{$key} = $value;
      }
    }
  }
  foreach my $key (keys %values) {
    $self->$key($values{$key});
  }
  return $self;
}

sub collect {
  my ($self, @fields) = @_;
  my $include = $self->inceq;
  my $soft = 0;
  if ($fields[0] eq 'soft') {
    shift @fields;
    $soft = 1;
  }
  if (($soft and $include >= 2) or (!$soft and $include >= 1)) {
    my @results;
    foreach my $field (@fields) {
      my $stored = $self->$field;
      next unless defined $stored;
      push @results, ref $stored ? @{$stored} : $stored;
    }
    return wantarray ? () : undef unless @results;
    return wantarray ? @results : \@results;
  }
  else {
    foreach my $field (@fields) {
      my $stored = $self->$field;
      return $stored if defined $stored;
    }
    return wantarray ? () : undef;
  }
}

sub ris_type         { shift->collect(qw/TY/); }
sub identification   { shift->collect(qw/ID/); }
sub title_primary    { shift->collect(qw/T1 TI CT BT/); }
sub title_secondary  { shift->collect(qw/T2 BT/); }
sub title_series     { shift->collect(qw/T3/); }
sub title      	     { shift->collect(soft => qw/title_primary title_secondary title_series/); }
sub author_primary   { shift->collect(qw/A1 AU/); }
sub author_secondary { shift->collect(qw/A2 ED/); }
sub author_series    { shift->collect(qw/A3/); }
sub author           { shift->collect(soft => qw/author_primary author_secondary author_series/); }
sub authors          { shift->collect(qw/author/); }
sub date_primary     { shift->collect(qw/Y1 PY/); }
sub date_secondary   { shift->collect(qw/Y2/); }
sub date             { shift->collect(soft => qw/date_primary date_secondary/); }
sub notes            { shift->collect(qw/N1 AB/); }
sub abstract         { shift->collect(qw/N2/); }
sub keywords         { shift->collect(qw/KW/); }
sub reprint          { shift->collect(qw/RP/); }
sub periodical_name  { shift->collect(qw/JF JO/); }
sub periodical_abbr  { shift->collect(qw/JA J1 J2/); }
sub journal          { shift->collect(soft => qw/periodical_name periodical_abbr/); }
sub journal_abbr     { shift->collect(qw/periodical_abbr/); }
sub volume           { shift->collect(qw/VL/); }
sub issue            { shift->collect(qw/IS/); }
sub starting_page    { shift->collect(qw/SP/); }
sub ending_page      { shift->collect(qw/EP/); }
sub page             { shift->collect(qw/starting_page/); }
sub publication_city { shift->collect(qw/CP CY/); }
sub publisher        { shift->collect(qw/PB/); }
sub issn_or_isbn     { shift->collect(qw/SN/); }
sub issn             { shift->collect(qw/issn_or_isbn/); }
sub isbn             { shift->collect(qw/issn_or_isbn/); }
sub address          { shift->collect(qw/AD/); }
sub availablity      { shift->collect(qw/AV/); }
sub misc1            { shift->collect(qw/M1/); }
sub misc2            { shift->collect(qw/M2/); }
sub misc3            { shift->collect(qw/M3/); }
sub misc             { shift->collect(qw/misc1 misc2 misc3/); }
sub user1            { shift->collect(qw/U1/); }
sub user2            { shift->collect(qw/U2/); }
sub user3            { shift->collect(qw/U3/); }
sub user4            { shift->collect(qw/U4/); }
sub user5            { shift->collect(qw/U5/); }
sub user             { shift->collect(qw/user1 user2 user3 user4 user5/); }
sub url              { shift->collect(qw/UR/); }
sub uri              { shift->collect(qw/url/); }
sub web              { shift->collect(qw/url/); }
sub pdf              { shift->collect(qw/L1/); }
sub full_text        { shift->collect(qw/L2/); }
sub related          { shift->collect(qw/L3/); }
sub image            { shift->collect(qw/L4/); }
sub links            { shift->collect(qw/web pdf full_text related image/); }

sub page_range {
  my $self = shift; 
  my $starting_page = $self->collect(qw/starting_page/) or return undef;
  my $ending_page   = $self->collect(qw/ending_page/)   or return $starting_page;
  return $starting_page.' - '.$ending_page if $starting_page != $ending_page;
  return $starting_page;
}

sub ris_type_description {
  return $TYPES{shift->ris_type};
}

sub is_valid_ris_type {
  return exists $TYPES{shift->ris_type};
}

sub make_result {
  my ($self, $type, $source) = @_;
  bless $self, 'Bibliotech::CitationSource::RIS::Result';
  $self->type($type);
  $self->source($source);
  return $self;
}

package Bibliotech::CitationSource::RIS::Result;
use Bibliotech::CitationSource;
use base ('Bibliotech::CitationSource::RIS', 'Bibliotech::CitationSource::Result', 'Class::Accessor::Fast');
use List::Util qw/first/;
use List::MoreUtils qw/none/;

__PACKAGE__->mk_accessors(qw/type source/);

sub make_resultlist {
  my $self = shift;
  return bless [$self], 'Bibliotech::CitationSource::ResultList';
}

sub identifiers {
  {doi => shift->doi};
}

sub justone {
  my ($self, $field, %options) = @_;
  my $super = 'SUPER::'.$field;
  my $stored = $self->$super or return undef;
  return undef unless defined $stored;
  return $stored unless ref $stored eq 'ARRAY';
  my @stored = @{$stored};
  my $join = $options{join};
  return join($join, @stored) if defined $join;
  my @not = @{$options{not}||[]};
  my $first = first { my $value = $_; none { $value eq $_ } @not } @stored;
  return $first;
}

sub authors {
  my ($self) = @_;
  my $authors = $self->SUPER::authors;
  my @authors = map(Bibliotech::CitationSource::RIS::Result::Author->new($_), ref $authors ? @{$authors} : $authors);
  bless \@authors, 'Bibliotech::CitationSource::Result::AuthorList';
}

# override - from Nature the abbreviated name arrives in JO
sub periodical_name  { shift->collect(qw/JF/); }
sub periodical_abbr  { shift->collect(qw/JO JA J1 J2/); }

sub journal {
  my ($self) = @_;
  return Bibliotech::CitationSource::RIS::Result::Journal->new($self->justone('journal'),
							       $self->justone('journal_abbr'),
							       $self->justone('issn'));
}

sub ris_type 	{ shift->justone('ris_type'); }
sub pubmed   	{ undef; }
sub asin        { undef; }
sub title    	{ shift->justone('title'); }
sub description { shift->justone('notes'); }
sub volume   	{ shift->justone('volume'); }
sub issue    	{ shift->justone('issue'); }
sub page     	{ shift->page_range; }

sub doi {
  my $doi = shift->justone('misc3') or return;
  $doi = lc $doi;
  $doi =~ s/^doi://;
  return $doi;
}

sub url {
  my @url = map { split(/[ \n]+/) } shift->collect(qw/UR L3/);
  return unless @url;
  return $url[0] if @url == 1;
  return wantarray ? @url : \@url;
}

sub date {
  my $date = shift->justone('date');
  $date =~ s|^(\d+/\d*/\d*)/.*$|$1|;
  return $date;
}

sub last_modified_date {
  shift->date(@_);
}


package Bibliotech::CitationSource::RIS::Result::Author;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/firstname forename initials lastname/);

sub new {
  my ($class, $author) = @_;
  my ($lastname, $firstname);
  if ($author =~ /^(.+?),\s*(.*)$/) {
    ($lastname, $firstname) = ($1, $2);
  }
  elsif ($author =~ /^(.*)\s+(.+)$/) {
    ($firstname, $lastname) = ($1, $2);
  }
  else {
    $lastname = $author;
  }
  my $initials = join(' ', map { s/^(.).*$/$1/; $_; } split(/\s+/, $firstname)) || undef;
  $firstname =~ s/(\s\w\.?)+$//;
  return $class->SUPER::new({firstname => $firstname, forename => $firstname, lastname => $lastname, initials => $initials});
}

package Bibliotech::CitationSource::RIS::Result::Journal;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/name medline_ta issn/);

sub new {
  my ($class, $name, $medline_ta, $issn) = @_;
  return $class->SUPER::new({name => $name, medline_ta => $medline_ta, issn => $issn});
}

1;
__END__
