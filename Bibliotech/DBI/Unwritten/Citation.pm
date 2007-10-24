package Bibliotech::Unwritten::Citation;
use strict;
use base ('Bibliotech::Unwritten', 'Bibliotech::Citation');

__PACKAGE__->columns(TEMP => qw/x_authors/);

sub authors {
  my ($self, $value) = @_;
  $self->x_authors($value) if defined $value;
  my $authors_ref = $self->x_authors or return ();
  return @{$authors_ref};
}

sub link_author {
  my $self = shift;
  $self->authors([$self->authors,
		  map { Bibliotech::Unwritten::Author->from_name_str($_->[1]) } @_
		 ]);
}

sub _write_accept {
  my ($obj, $testaction, $linkaction) = @_;
  return unless defined $obj;
  return $obj if $obj->id;
  return if defined $testaction and !$testaction->($obj);
  return $linkaction->($obj);
}

sub write {
  my ($self, $bookmark_or_user_article) = @_;

  my $journal  = _write_accept($self->journal,
			       sub { $_[0]->name || $_[0]->medline_ta },
			       sub { transfer Bibliotech::Journal (shift) });
  my $citation = _write_accept($self,
			       undef,
			       sub { transfer Bibliotech::Citation ($self, {journal => $journal}) });
  my $i = 0;
  foreach my $author_mem ($self->authors) {
    my $author = _write_accept($author_mem,
			       undef,
			       sub { transfer Bibliotech::Author ($author_mem) });
    $citation->link_author([++$i => $author]);  # that's not link_author() in this class... it's in Bibliotech::Citation:
  }

  if ($bookmark_or_user_article) {
    $bookmark_or_user_article->citation($citation);
    $bookmark_or_user_article->update;
    $bookmark_or_user_article->citation_added if $bookmark_or_user_article->can('citation_added');
  }

  return $citation;
}

# convert a Bibliotech::CitationSource::Result object to a Bibliotech::Unwritten::Citation object
# $citation_model is a Bibliotech::CitationSource::Result object
# $user_supplied is 1/0 for whether the user supplied the citation data (0 means the date is authoritative)
# $original_module_str is a string naming the CitationSource or Import module that provided this data
# returns a Bibliotech::Unwritten::Citation object with author objects packed inside
sub from_citationsource_result {
  my ($self, $citation_model, $user_supplied, $original_module_str, $original_module_score) = @_;
  $citation_model or die 'no citation model provided';

  my $raw_date = $citation_model->date;
  my $journal;
  if ($citation_model->can('journal')) {
    if (my $journal_model = $citation_model->journal) {
      $journal = Bibliotech::Unwritten::Journal->transfer($journal_model, undef, undef, 'construct');
    }
  }
  my $citation = 
      Bibliotech::Unwritten::Citation->transfer($citation_model,
						{pubmed        => $citation_model->identifier('pubmed'),
						 doi           => $citation_model->identifier('doi'),
						 asin          => $citation_model->identifier('asin'),
						 journal       => $journal,
						 raw_date      => $raw_date,
						 date          => ($raw_date ? Bibliotech::Date->new($raw_date) : undef),
						 user_supplied => ($user_supplied ? 1 : 0),
						 cs_module     => $original_module_str,
						 cs_type       => $citation_model->type,
						 cs_source     => $citation_model->source,
						 cs_score      => $original_module_score,
					       },
						undef, 'construct');
  die 'no citation object' unless defined $citation;
  if (!$citation->start_page) {
    if ($citation_model->can('page')) {
      $citation->page($citation_model->page);
    }
    elsif ($citation_model->can('pages')) {
      $citation->page($citation_model->pages);
    }
  }
  $citation->clean_whitespace_all;
  $citation->update;
  my @authors;
  if (my $authors = $citation_model->authors) {
    while (my $author_model = $authors->fetch) {
      my $author = Bibliotech::Unwritten::Author->transfer($author_model, undef, undef, 'construct');
      die 'no author object' unless defined $author;
      $author->clean_whitespace_all;
      $author->update;
      push @authors, $author;
    }
    $citation->authors(\@authors);
  }
  return $citation;
}

# convert the first entry on a Bibliotech::CitationSource::ResultList object to a Bibliotech::Unwritten::Citation object
# $citations is a Bibliotech::CitationSource::ResultList object
# $user_supplied is 1/0 for whether the user supplied the citation data (0 means the date is authoritative)
# $original_module_str is a string naming the CitationSource or Import module that provided this data
# returns a Bibliotech::Unwritten::Citation object with author objects packed inside
sub from_citationsource_result_list {
  my ($self, $citations, $user_supplied, $original_module_str, $original_module_score) = @_;
  defined $citations or die 'no citations provided';
  $citations->can('fetch') or die 'citations object has no fetch method';
  $user_supplied = 0 unless defined $user_supplied;

  my @citations;
  while (my $citation_model = $citations->fetch) {
    my $citation = $self->from_citationsource_result($citation_model,
						     ($user_supplied ? 1 : 0),
						     $original_module_str,
						     $original_module_score) or next;
    push @citations, $citation;
  }
  die 'more than one citation line not yet supported' if @citations > 1;
  return @citations ? $citations[0] : undef;
}

sub from_hash_of_text_values {
  my ($self, $text_ref) = @_;

  my $fix_doi = sub {
    local $_ = shift or return;
    s/^doi:\s*//i;
    return $_;
  };
  my $fix_pubmed = sub {
    local $_ = shift or return;
    s/^pmid:?\s*//i;
    return $_;
  };
  my $date_or_die = sub {
    my $date = shift or return;
    my $obj = Bibliotech::Date->new($date);
    die "Cannot understand citation date \"$date\" - please clarify it.\n" if !defined($obj) or $obj->invalid;
    die 'The citation date must contain a year ('.$obj->citation.") - please clarify it.\n" unless $obj->year;
    return $obj;
  };

  my $get_journal = sub {
    my $name = shift or return;
    Bibliotech::Unwritten::Journal->transfer(undef, {name => $name}, undef, 'construct');
  };

  my $citation = Bibliotech::Unwritten::Citation->transfer
      (undef,
       {title         => $text_ref->{title} || undef,
	volume        => $text_ref->{volume} || undef,
	issue         => $text_ref->{issue} || undef,
	pubmed        => $fix_pubmed->($text_ref->{pubmed}) || undef,
	doi           => $fix_doi->($text_ref->{doi}) || undef,
	asin          => $text_ref->{asin} || undef,
	journal       => $get_journal->($text_ref->{journal}) || undef,
	raw_date      => $text_ref->{date} || undef,
	date          => $date_or_die->($text_ref->{date}) || undef,
	start_page    => $text_ref->{start_page} || undef,
	end_page      => $text_ref->{end_page} || undef,
	ris_type      => $text_ref->{ris_type} || $text_ref->{ristype} || undef,
	user_supplied => 1,
	cs_module     => 'User Edit',
	cs_type       => undef,
	cs_source     => undef,
	cd_score      => undef,
       },
       undef, 'construct');

  # possibly redefine start_page and end_page using object method:
  if (my $combined_start_and_end_pages = $text_ref->{pages} || $text_ref->{page} || $text_ref->{page_range}) {
    $citation->page($combined_start_and_end_pages);
  }

  # define authors using object method:
  $citation->authors([Bibliotech::Util::split_author_names($text_ref->{authors})]);

  return $citation;
}

sub json_content {
  my $self = shift;
  my $hash = $self->SUPER::json_content;
  $hash->{authors} = $hash->{x_authors};
  delete $hash->{x_authors};
  return $hash;
}

1;
__END__
