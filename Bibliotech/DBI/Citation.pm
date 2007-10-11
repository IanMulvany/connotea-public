package Bibliotech::Citation;
use strict;
use base 'Bibliotech::DBI';
use URI;
use URI::OpenURL;
use URI::Escape;
use Bibliotech::Util;

__PACKAGE__->table('citation');
#__PACKAGE__->columns(All => qw/citation_id title journal volume issue start_page end_page pubmed doi asin ris_type raw_date date last_modified_date user_supplied cs_module cs_type cs_source created/);
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

sub bookmarks_or_user_bookmarks {
  my $self = shift;
  return (Bibliotech::Bookmark->search(citation => $self), Bibliotech::User_Bookmark->search(citation => $self));
}

sub bookmarks_or_user_bookmarks_count {
  my @bookmarks_or_user_bookmarks = shift->bookmarks_or_user_bookmarks;
  return scalar @bookmarks_or_user_bookmarks;
}

sub delete {
  #warn 'delete citation';
  my $self = shift;
  foreach my $bookmark_or_user_bookmark ($self->bookmarks_or_user_bookmarks) {
    $bookmark_or_user_bookmark->citation(undef);
    $bookmark_or_user_bookmark->update;
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
  my $bibliotech = $options{bibliotech};
  my $just_with_values = $options{just_with_values} || $options{just_best};
  my $just_best = $options{just_best};
  my @id;
  unless ($just_with_values) {
    my ($openurl_uri, $openurl_name) = $self->openurl_uri(bibliotech => $bibliotech);
    if ($openurl_uri) {
      my $id = Bibliotech::Citation::Identifier->new({source      => 'OpenURL',
						      type        => 'openurl',
						      prefix      => $openurl_name,
						      noun        => $openurl_name,
						      xmlnoun     => 'OpenURL',
						      value       => undef,
						      urilabel    => 'openurlResolver',
						      uri         => $openurl_uri,
						      natural_fmt => '%U'});
      push @id, $id;
    }
  }
  if (my $pubmed = $self->pubmed) {
    my $id = Bibliotech::Citation::Identifier->new({source   	=> 'Pubmed',
						    type     	=> 'pubmed',
						    infotype 	=> 'pmid',
						    prefix   	=> 'PMID: ',
						    noun     	=> 'PubMedID',
						    xmlnoun  	=> 'PubMedID',
						    value    	=> $pubmed,
						    urilabel 	=> 'pmidResolver',
						    uri      	=> $self->pubmed_uri,
						    natural_fmt => 'info:pmid/%v'});
    return $id if $just_best;
    push @id, $id;
  }
  if (my $doi = $self->doi) {
    my $id = Bibliotech::Citation::Identifier->new({source   	=> 'doi',
						    type     	=> 'doi',
						    infotype 	=> 'doi',
						    prefix   	=> 'doi:',
						    noun     	=> 'DOI',
						    xmlnoun  	=> 'DOI',
						    value    	=> $doi,
						    urilabel 	=> 'doiResolver',
						    uri      	=> $self->doi_uri,
						    natural_fmt => 'info:doi/%v'});
    return $id if $just_best;
    push @id, $id;
  }
  if (my $asin = $self->asin) {
    my $id = Bibliotech::Citation::Identifier->new({source   	=> 'Amazon.com',
						    type     	=> 'asin',
						    infotype 	=> 'isbn',
						    prefix   	=> 'ASIN: ',
						    noun     	=> 'ASIN',
						    xmlnoun  	=> 'ASIN',
						    value    	=> $asin,
						    urilabel 	=> 'asinResolver',
						    uri      	=> $self->asin_uri,
						    natural_fmt => 'urn:isbn:%v'});
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

sub standardized_uri {
  my ($self, $column, $prefix) = @_;
  die 'no prefix' unless $prefix;
  my $id = $self->$column or return undef;
  my $escaped = uri_escape($id, "^A-Za-z0-9\-_.!~*'()/"); # standard, plus added forward slash to exclusion
  return URI->new($prefix.$escaped);
}

sub pubmed_uri {
  shift->standardized_uri(pubmed =>
			  'http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&db=pubmed&dopt=Abstract&list_uids=');
}

sub doi_uri {
  shift->standardized_uri(doi => 'http://dx.doi.org/');
}

sub asin_uri {
  shift->standardized_uri(asin => 'http://www.amazon.com/exec/obidos/ASIN/');
}

sub is_openurl_uri_possible {
  my ($self, %options) = @_;

  my $bibliotech = $options{bibliotech};
  my $user = $options{user} || (defined $bibliotech ? $bibliotech->user : $Bibliotech::Apache::USER);
  my $resolver_uri = $options{resolver_uri} || (defined $user ? $user->openurl_resolver : undef) or return 0;
  return 1;
}

sub openurl_uri {
  my ($self, %options) = @_;

  my $bibliotech     = $options{bibliotech};
  my $user           = $options{user}           || (defined $bibliotech ? $bibliotech->user : $Bibliotech::Apache::USER);
  my $resolver_uri   = $options{resolver_uri}   || (defined $user ? $user->openurl_resolver : undef) or return undef;
  my $resolver_alias = $options{resolver_alias} || (defined $user ? $user->openurl_name : undef) || 'OpenURL';

  my ($referrer_id, $requester_id, $referent_id);

  if ($bibliotech) {
    my $location = $bibliotech->location;
    my $host = $location->host;
    $host =~ s|^www\.||;
    if (my $path = $location->path) {
      $path =~ s|/$||;
      $host .= $path;
    }
    my $sitename = $bibliotech->sitename;
    $host .= ':'.$sitename if $sitename;
    $referrer_id = 'info:sid/'.$host if $host;
    if ($bibliotech->can('library_location') && defined $user) {
      $requester_id = $bibliotech->library_location($user);
    }
    if (my @id = $self->standardized_identifiers(bibliotech => $bibliotech, just_with_values => 1)) {
      $referent_id = [map($_->natural_uri, @id)];
    }
  }

  my $openurl = URI::OpenURL->new($resolver_uri);
  $openurl->referrer (id => $referrer_id)  if $referrer_id;
  $openurl->requester(id => $requester_id) if $requester_id;
  $openurl->referent (id => $referent_id)  if $referent_id;

  my %citation;
  if (my $first_author = $self->first_author) {
    if (my $lastname = $first_author->lastname) {
      $citation{aulast} = $lastname;
    }
    if (my $firstname = $first_author->firstname) {
      $citation{aufirst} = $firstname;
    }
    elsif (my $initials = $first_author->initials) {
      $citation{auinit} = $initials;
    }
    elsif (my $forename = $first_author->forename) {
      $citation{auinit1} = substr($forename, 0, 1);
    }
  }
  if (my $journal = $self->journal) {
    if (my $title = $journal->name || $journal->medline_ta) {
      $citation{jtitle} = $title;
    }
    if (my $issn = $journal->issn) {
      $citation{issn} = $issn;
    }
  }
  if (my $volume = $self->volume) {
    $citation{volume} = $volume;
  }
  if (my $issue = $self->issue) {
    $citation{issue} = $issue;
  }
  if (my $date = $self->date) {
    $citation{date} = $date->ymd_ordered_cut;
  }
  if (my $start_page = $self->start_page) {
    $citation{spage} = $start_page;
  }
  if (my $end_page = $self->end_page) {
    $citation{epage} = $end_page;
  }
  my $ris_type = $self->inferred_ris_type;
  my $typefunc = 'journal';
  if ($ris_type eq 'BOOK') {
    $typefunc = 'book';
    if (my $title = $self->title) {
      $citation{title} = $title;
    }
    if (my $asin = $self->asin) {
      $citation{isbn} = $asin;
    }
  }
  elsif ($ris_type eq 'CONF') {
    $citation{genre} = 'conference';
  }
  elsif ($ris_type eq 'PAT') {
    $typefunc = 'patent';
  }
  else {
    $citation{genre} = 'article';
    if (my $title = $self->title) {
      $citation{atitle} = $title;
    }
  }
  $openurl->$typefunc(%citation);

  my $hybrid = $openurl->as_hybrid || $openurl;
  return wantarray ? ($hybrid, $resolver_alias) : $hybrid;
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

1;
__END__
