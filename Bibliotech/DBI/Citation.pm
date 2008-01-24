package Bibliotech::Citation;
use strict;
use base 'Bibliotech::DBI';
use URI;
use URI::OpenURL;
use URI::Escape;
use Bibliotech::Util;

__PACKAGE__->table('citation');
__PACKAGE__->columns(Primary => qw/citation_id/);
__PACKAGE__->columns(Essential => qw/title journal volume issue start_page end_page pubmed doi asin ris_type raw_date date last_modified_date user_supplied cs_module cs_type cs_source cs_score created/);
__PACKAGE__->columns(TEMP => qw/authors_packed/);
__PACKAGE__->force_utf8_columns(qw/title volume issue start_page end_page raw_date cs_module cs_type cs_source/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_a(journal => 'Bibliotech::Journal');
__PACKAGE__->has_many(authors_raw => ['Bibliotech::Citation_Author' => 'author']);
__PACKAGE__->datetime_column('date', undef, 'date');
__PACKAGE__->datetime_column('last_modified_date', undef, 'date');

sub my_alias {
  'ct';
}

sub authors {
  shift->packed_or_raw('Bibliotech::Author', 'authors_packed', 'authors_raw');
}

sub first_author {
  (shift->authors)[0];
}

sub bookmarks_or_user_articles_or_articles {
  my $self = shift;
  return (Bibliotech::Bookmark->search(citation => $self),
	  Bibliotech::Article->search(citation => $self),
	  Bibliotech::User_Article->search(citation => $self));
}

sub bookmarks_or_user_articles_or_articles_count {
  my @count = shift->bookmarks_or_user_articles_or_articles;
  return scalar @count;
}

sub delete {
  my $self = shift;
  foreach my $entity ($self->bookmarks_or_user_articles_or_articles) {
    $entity->citation(undef);
    $entity->mark_updated;
  }
  return $self->SUPER::delete(@_);
};

sub clean_whitespace_all {
  my $self = shift;
  $self->clean_whitespace($_) foreach (qw/title journal volume issue start_page end_page pubmed doi asin ris_type/);
}

# if you prefer distinctly separate start/end pages call start_page() and end_page()
sub page {
  my $self = shift;
  return $self->set_start_and_end_pages_joined(shift) if @_;
  return $self->get_start_and_end_pages_joined;
}

sub set_start_and_end_pages {
  my ($self, $start, $end) = @_;
  $self->start_page($start);
  $self->end_page($end);
  return $self->start_page;
}

sub set_start_and_end_pages_joined {
  my ($self, $value) = @_;
  return $self->set_start_and_end_pages(Bibliotech::Util::split_page_range($value));
}

sub get_start_and_end_pages {
  my $self = shift;
  return ($self->start_page, $self->end_page);
}

# for (1960,1969) return '1960-9'
sub _join_page_numbers {
  my $start = shift or return;
  my $end   = shift or return $start;
  return $start if $start eq $end;
  my ($start_copy, $end_copy) = ($start, $end);
  while ($start_copy =~ s/^(.)(.)/$2/ and $end_copy =~ s/^$1//) {}  # change 1960-1969 to 1960-9
  my $possibly_shorter_end = length($end_copy) <= 2 ? $end_copy : $end;
  return join('-', $start, $possibly_shorter_end);
}

sub get_start_and_end_pages_joined {
  _join_page_numbers(shift->get_start_and_end_pages);
}

sub inferred_ris_type {
  my ($self, $default) = @_;
  my $ris_type = $self->ris_type;
  return $ris_type if $ris_type;
  $ris_type = $default || 'ELEC';
  if (my $author = $self->first_author) {
    $ris_type = 'BOOK';  # if we have authors, assume BOOK (or possibly JOUR)
  }
  if (my $journal = $self->journal) {
    my $name = $journal->name || $journal->medline_ta;
    $ris_type = 'JOUR' if $name;  # if we have a journal name, assume JOUR
  }
  return $ris_type;
}

sub standardized_identifiers {
  my ($self, %options) = @_;
  my $bibliotech       = $options{bibliotech};
  my $just_with_values = $options{just_with_values} || $options{just_best};
  my $just_best        = $options{just_best};
  my @id;
  unless ($just_with_values) {
    if (my $id = Bibliotech::Citation::Identifier::OpenURL->new($self, $bibliotech, $bibliotech->user)) {
      push @id, $id;
    }
  }
  if (my $id = Bibliotech::Citation::Identifier::Pubmed->new($self->pubmed)) {
    return $id if $just_best;
    push @id, $id;
  }
  if (my $id = Bibliotech::Citation::Identifier::DOI->new($self->doi)) {
    return $id if $just_best;
    push @id, $id;
  }
  if (my $id = Bibliotech::Citation::Identifier::ASIN->new($self->asin)) {
    return $id if $just_best;
    push @id, $id;
  }
  return undef if $just_best;
  return wantarray ? @id : \@id;
}

sub has_standardized_identifiers {
  my $self = shift;
  return ($self->pubmed || $self->doi || $self->asin || $self->is_openurl_uri_possible) ? 1 : 0;
}

sub standardized_identifiers_html {
  my ($self, $bibliotech) = @_;
  die 'no bibliotech object' unless $bibliotech;
  my @id = $self->standardized_identifiers(bibliotech => $bibliotech) or return;
  my $cgi = $bibliotech->cgi;
  return $cgi->div({class => 'citation'},
		   join(' | ',
			map { $cgi->a({href => $_->uri, class => 'dblink'},
				      Bibliotech::Util::encode_xhtml_utf8($_->link_text)) } @id));
}

sub best_standardized_identifier {
  my ($self, $bibliotech) = @_;
  return $self->standardized_identifiers(bibliotech => $bibliotech, just_best => 1);
}

sub is_openurl_uri_possible {
  my ($self, %options) = @_;
  my $bibliotech = $options{bibliotech};
  my $user = $options{user} || (defined $bibliotech ? $bibliotech->user : $Bibliotech::Apache::USER);
  my $resolver_uri = $options{resolver_uri} || (defined $user ? $user->openurl_resolver : undef) or return 0;
  return 1;
}

sub citation_line {
  my ($self, $bibliotech, $in_html) = @_;
  my $date        = $self->date;
  my $date_str    = $date ? $date->citation : '';
  my $journal     = $self->journal;
  my $journal_str = defined $journal ? $journal->name || $journal->medline_ta : '';
  my $volume_str  = $self->volume;
  my $issue_str   = $self->issue;
  my $page_str    = $self->page;

  # abandon citation line construction if there's not enough data
  return undef unless $journal_str;

  my $span = $in_html
               ? do { my $cgi = $bibliotech->cgi;
		      sub { my $class = shift;
			    return $cgi->span({class => $class},
					      map { Bibliotech::Util::encode_xhtml_utf8($_) } @_); };
	            }
               : sub { shift; join(' ', @_); };

  ## AOP hack
  if ($volume_str eq 'advanced online publication') {
    return undef unless $date_str;  # need to have the date now
    $volume_str = undef;
    return join('', ($span->('journal', $journal_str),
		     $span->('aop', ', published online '.$date_str)));
  }

  my $source    = join(' ', ($journal_str ? $span->('journal', $journal_str)     : (),
			     $volume_str  ? $span->('volume',  $volume_str)      : (),
			     $issue_str   ? '('.$span->('issue', $issue_str).')' : ()));

  my $page_date = join(' ', ($page_str    ? $span->('pages', $page_str)          : (),
			     $date_str    ? '('.$span->('date', $date_str).')'   : ()));

  return join(', ', grep($_, $source, $page_date));
}

sub link_author {
  my $self = shift;
  my @ba = map(Bibliotech::Citation_Author->find_or_create({citation => $self,
							    author => Bibliotech::Author->new($_->[1], 4),
							    displayorder => $_->[0]}), @_);
  return wantarray ? @ba : $ba[0];
}

sub unlink_author {
  my $self = shift;
  foreach (@_) {
    my $author = ref $_ eq 'Bibliotech::Author' ? $_ : Bibliotech::Author->retrieve($_) or next;
    my ($link) = Bibliotech::Citation_Author->search(citation => $self, author => $author) or next;
    $link->delete;
  }
}

sub author_list {
  my ($self, $expand, $bibliotech, $dont_encode) = @_;

  my @authors   = $self->authors;
  my $etal_span = sub { my $text = shift;
			defined $bibliotech        or return $text;
			my $cgi = $bibliotech->cgi or return $text;
			return $cgi->span({class => 'etal'}, $text);
		      };
  my $getname   = sub { my $name = shift->name(0);
			return $name if $dont_encode;
			return Bibliotech::Util::encode_xhtml_utf8($name); };

  return ''                                              if @authors == 0;              # ''
  return $getname->($authors[0])                         if @authors == 1;              # 'John Smith'
  return $getname->($authors[0]).$etal_span->(' et al.') if @authors > 3 and !$expand;  # 'John Smith et al.'
  return Bibliotech::Util::speech_join('and', map { $getname->($_) } @authors);        # 'John Smith and Bob Jones ...'
}

sub expanded_author_list {
  my ($self, $bibliotech) = @_;
  return $self->author_list(1, $bibliotech);
}

sub expanded_author_list_dont_encode {
  my ($self, $bibliotech) = @_;
  return $self->author_list(1, $bibliotech, 1);
}

sub is_only_title_eq {
  my ($self, $usertitle) = @_;
  return 0 if $self->title ne $usertitle;
  my @essential = $self->_essential;
  my %columns;
  @columns{@essential} = @essential;
  delete $columns{title};
  delete $columns{cs_module};
  delete $columns{cs_type};
  delete $columns{cs_source};
  delete $columns{cs_score};
  delete $columns{user_supplied};
  return 0 if grep($self->$_, keys %columns);
  return 1;
}

__PACKAGE__->set_sql(from_article => <<'');
SELECT   __ESSENTIAL(c)__
FROM     __TABLE(Bibliotech::Bookmark=b)__
         LEFT JOIN __TABLE(Bibliotech::Citation=c)__ ON (__JOIN(b c)__)
WHERE    b.article = ?
AND      c.citation_id IS NOT NULL

1;
__END__
