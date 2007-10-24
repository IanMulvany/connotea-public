package Bibliotech::Bookmark;
use strict;
use base 'Bibliotech::DBI';
use Bibliotech::Query;
use Bibliotech::Util;
use URI;
use Digest::MD5 qw/md5_hex/;
use RDF::Core;
use RDF::Core::Literal;
use RDF::Core::Resource;
use RDF::Core::Statement;
use RDF::Core::Model;
use Bibliotech::RDF::Core::Storage::Memory;
use Bibliotech::RDF::Core::Model::Serializer;
use Bibliotech::DBI::Unwritten::CitationConcat;
use utf8;
# if Bibliotech::Clicks is loaded it will change the behavior of html_content() to add a click counter onclick handler

__PACKAGE__->table('bookmark');
__PACKAGE__->columns(Primary => qw/bookmark_id/);
__PACKAGE__->columns(Essential => qw/url hash updated citation/);
__PACKAGE__->columns(Others => qw/first_user created/);
__PACKAGE__->columns(TEMP => qw/x_adding x_for_user_article user_article_count_packed tags_packed document/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->add_trigger('before_create' => \&set_correct_hash);
__PACKAGE__->has_a(url => 'URI');
__PACKAGE__->has_a(first_user => 'Bibliotech::User');
__PACKAGE__->has_a(citation => 'Bibliotech::Citation');
__PACKAGE__->has_a(article => 'Bibliotech::Article');
__PACKAGE__->has_many(user_articles_raw => 'Bibliotech::User_Article');
__PACKAGE__->has_many(users => ['Bibliotech::User_Article' => 'user']);
__PACKAGE__->might_have(details => 'Bibliotech::Bookmark_Details' => qw/title/);

__PACKAGE__->set_sql(url_case_sensitive => <<'');
SELECT 	 __ESSENTIAL__
FROM     __TABLE(Bibliotech::Bookmark=b)__
WHERE  	 b.url = BINARY ?

__PACKAGE__->set_sql(url_or_hash => <<'');
SELECT 	 __ESSENTIAL__
FROM     __TABLE(Bibliotech::Bookmark=b)__
WHERE  	 b.url = ?
UNION
SELECT 	 __ESSENTIAL__
FROM     __TABLE(Bibliotech::Bookmark=b)__
WHERE  	 b.hash = ?

sub search_new {
  my ($self, $url_or_hash) = @_;
  my $sth = $self->sql_url_or_hash;
  my $param = "$url_or_hash";  # convert to string if object, so it only happens once here
  $sth->execute($param, $param);
  my $obj;
  $obj = $self->construct($sth->fetchrow_hashref) if $sth->rows;
  $sth->finish;
  return $obj;
}

sub set_correct_hash {
  my $self = shift;
  my $url = $self->url;
  $self->hash(md5_hex("$url"));
}

sub my_alias {
  'b';
}

sub packed_select {
  my $self = shift;
  my $alias = $self->my_alias;
  return (map("$alias.$_", $self->_essential),
	  'COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed',
	  Bibliotech::DBI::packing_groupconcat('Bibliotech::Tag', 't2', 'tags_packed', 'uat2.created'),
	  );
}

sub uri {
  shift->url(@_);
}

sub is_hash_format {
  $_[$#_] =~ /^[0-9a-f]{32}$/;
}

sub normalize_option_to_simple_uri_object {
  my ($self, $options_ref) = @_;

  my $uri = $options_ref->{uri} || $options_ref->{url} || $options_ref->{bookmark}
    or die "You must specify a URI.\n";

  if (UNIVERSAL::isa($uri, 'Bibliotech::Bookmark')) {
    return $uri->url;
  }

  if (is_hash_format($uri)) {
    my ($bookmark) = Bibliotech::Bookmark->search(hash => $uri) or die "Hash not found ($uri).\n";
    return $bookmark->url;
  }

  if ($uri =~ /^\d+$/) {
    return UNIVERSAL::isa($uri, 'URI') ? $uri : URI->new($uri);
  }

  return URI::Heuristic::uf_uri($uri)->canonical;
}

sub count_active {
  # use user_article table; it's faster
  Bibliotech::User_Article->sql_single('COUNT(DISTINCT bookmark)')->select_val;
}

sub delete {
  my $self = shift;
  my $citation = $self->citation;
  $self->SUPER::delete(@_);
  $citation->delete if $citation and $citation->bookmarks_or_user_articles_or_articles_count == 0;
}

sub authors {
  my $self = shift;
  my $citation = $self->citation or return ();
  return $citation->authors;
}

sub author_list {
  my $self = shift;
  my $citation = $self->citation or return ();
  return $citation->author_list(@_);
}

# adding means that the bookmark is being added at this very moment so a full display is not appropriate
# behaviour of 'adding' property:
# 0 = regular bookmark
# 1 = suppress most supplemental links (edit, copy, remove) and privacy note      (this level used on add form)
# 2 = suppress 'info' supplemental link
# 3 = show quotes around tags with spaces in Bibliotech::User_Article->postedby() (this level used on upload form)
# 4 = will not be added, suppress posted by                                       (this level used on upload form)
sub adding {
  my $self = shift;
  $self->remove_from_object_index if @_;
  return $self->x_adding(@_);
}

sub for_user_article {
  my $self = shift;
  $self->remove_from_object_index if @_;
  return $self->x_for_user_article(@_);
}

sub cite {
  my ($self, $ignore_user_data) = @_;
  unless ($ignore_user_data) {
    my $user_citation;
    my $for_user_article = $self->for_user_article;
    # deletion test added when profiling code in Bibliotech::Query was
    # requesting a description of deleted user_article rows
    return if UNIVERSAL::isa($for_user_article, 'Class::DBI::Object::Has::Been::Deleted');
    if ($for_user_article) {
      if ($user_citation = $for_user_article->citation) {
	return $user_citation;
      }
    }
  }
  return $self->citation;
}

# run through Bibliotech::Query to get privacy control, and later, maybe caching
sub user_articles {
  my $self = shift;
  my $q = new Bibliotech::Query;
  $q->set_bookmark($self);
  $q->activeuser($Bibliotech::Apache::USER);
  return $q->user_articles;
}

sub unique {
  'url';
}

sub another_index {
  'hash';
}

sub label_parse_easy {
  shift->hash;
}

sub visit_link {
  my ($self, $bibliotech, $class) = @_;
  return $bibliotech->cgi->div({class => ($class || 'referent')},
			       'Go to the',
			       $bibliotech->sitename,
			       'page for the this bookmark.'
			       );
}

sub href {
  my $url = shift->url or return '';
  my $href = "$url";  # intentionally discard remaining parameters which otherwise would change the URL!
  return '' if $href eq 'NO_URI';
  return $href;
}

sub href_hash {
  shift->SUPER::href_search_global(@_);
}

sub url_never_undef {
  my $url = shift->url;
  return '' unless defined $url;
  return $url;
}

sub url_chunked {
  my $url = shift->url;
  return undef unless defined $url;
  my $str = "$url";
  $str =~ s|(\S{75})|$1 |g;
  return $str;
}

sub url_host_or_opaque {
  my $url = shift->url;
  return undef unless defined $url;
  return $url->host   if $url->can('host');
  return $url->opaque if $url->can('opaque');
  return "$url";
}

sub search_value {
  shift->hash;
}

sub authoritative_title {
  my $citation = shift->citation or return;
  return $citation->title;
}

sub need_authoritative_title {
  my $self = shift;
  return without_punctuation($self->label_title) eq without_punctuation($self->authoritative_title);
}

sub without_punctuation {
  local $_ = shift;
  s/[[:punct:]]//g;
  return $_;
}

sub onclick_snippet {
  return unless defined $INC{'Bibliotech/Clicks.pm'};  # provide onclick string if click counter module is loaded
  my ($self, $bibliotech) = @_;
  return Bibliotech::Clicks::CGI::onclick_bibliotech($bibliotech, $self->url);
}
use Data::Dumper;
sub html_content {
  my ($self, $bibliotech, $class, $verbose, $main) = @_;
  my $cgi = $bibliotech->cgi;

  my $onclick = $self->onclick_snippet($bibliotech);
  my @output = ($self->link($bibliotech, $class, undef, 'label_title', $verbose, $onclick));
  return wantarray ? @output : join('', @output) unless $verbose;

  my $supplemental = $self->supplemental_links($bibliotech);
  unless ($self->adding) {
    my $location = $bibliotech->location;
    my $docroot  = $bibliotech->docroot;
    my @icons;
    #                  code           uri           name
    foreach my $tool (['copy',       'copy',       'copy'],
                      ['edit',       'edit',       'edit'],
                      ['remove',     'delete',     'delete'],
                      ) {
      my ($code, $uri, $name) = @{$tool};
      next unless $supplemental->{$code};
      push @icons, (-e $docroot.$uri.'_ico.gif'
		      ? $cgi->img({src => $location.$uri.'_ico.gif', alt => $name}).' '
		      : '').
		   $cgi->a({href => $supplemental->{$code}, class => 'linkicons'}, $name);
    }
    unshift @output, $cgi->div({class => 'icons'}, @icons ? @icons : ('&nbsp;'));
  }

  my $hasdblink = 0;
  if (my $citation = $self->cite) {

    # include authoritative citation title if different from label_title() already output above
    if (my $authoritative_citation = $self->cite(1)) {
      if (my $authoritative_citation_title = $authoritative_citation->title) {
	my $label_title = $self->label_title || '';  # label_title() has already already output above
	$authoritative_citation_title =~ s/[[:punct:]]//g;  # ignore minor differences in punctuation
	$label_title                  =~ s/[[:punct:]]//g;  # ignore minor differences in punctuation
	if ($authoritative_citation_title ne $label_title) {
	  push @output, $cgi->div({class => 'truetitle'},
				  Bibliotech::Util::encode_xhtml_utf8($authoritative_citation_title));
	}
      }
    }

    # show authors
    my $author_list = $citation->author_list($bibliotech->command->is_bookmark_command, $bibliotech);
    push @output, $cgi->div({class => 'authors'}, $author_list) if $author_list;

    # show journal, page, date, etc.
    my $citation_line = $citation->citation_line($bibliotech, 1);  # 1 means in_html
    push @output, $cgi->div({class => 'citationline'}, $citation_line) if $citation_line;

    # show identifiers
    if (my @id = $citation->standardized_identifiers(bibliotech => $bibliotech)) {
      $hasdblink = 1;
      $output[0] = $cgi->span({class => 'hasdblink'}, $output[0]);
      my @citelinks;
      foreach my $id (@id) {
	push @citelinks, $cgi->a({href => $id->info_or_link_uri->as_string, class => 'dblink',
				  onclick => "window.location = \'".$id->uri->as_string."\'; return false;"},
				 Bibliotech::Util::encode_xhtml_utf8($id->info_or_link_text));
      }
      push @output, $cgi->div({class => 'citation'}, join(' | ', @citelinks));
    }

  }
  elsif ($self->label_title ne $self->url_never_undef) {
    push @output, $cgi->div({class => 'actualurl'}, Bibliotech::Util::encode_xhtml_utf8($self->url_host_or_opaque));
  }
  $output[0] = $cgi->span({class => 'internet'}, $output[0]) unless $hasdblink;
  return wantarray ? @output : join('', @output);
}

sub label_title {
  my ($self, $disregard_user_data) = @_;
  unless ($disregard_user_data) {
    if (my $for_user_article = $self->for_user_article) {
      if (my $user_title = $for_user_article->title) {
	return $user_title;
      }
      if (my $user_citation = $for_user_article->citation) {
	if (my $user_citation_title = $user_citation->title) {
	  return $user_citation_title;
	}
      }
    }
  }
  if (my $citation = $self->citation) {
    if (my $citation_title = $citation->title) {
      return $citation_title;
    }
  }
  if (my $html_title = $self->title) {
    return $html_title;
  }
  return $self->SUPER::label_title(@_);
}

sub label_short {
  my $self = shift;
  if (my $citation = $self->cite) {
    if (my $id = $citation->best_standardized_identifier) {
      return $id->prefix.$id->value;
    }
  }
  return $self->SUPER::label_short(@_);
}

sub supplemental_links {
  my ($self, $bibliotech) = @_;
  my $adding = $self->adding;
  my %supplemental;
  if (!$adding || $adding == 1) {
    my $cgi = $bibliotech->cgi;
    my $hash = $self->hash;
    $supplemental{'info'} = $bibliotech->location.'uri/'.$hash;
    if (!$adding) {
      if (my $request = $bibliotech->request) {
	if (my $user_id = $request->user) {
	  my $for_my_user_article = 0;
	  my $for_user_article = $self->for_user_article;
	  if ($for_user_article) {
	    if ($user_id == $for_user_article->user->user_id) {
	      $supplemental{'edit'} = $bibliotech->location.'edit?uri='.$hash;
	      $supplemental{'remove'} = $bibliotech->location.'remove?uri='.$hash;
	      $for_my_user_article = 1;
	    }
	  }
	  if (!$for_my_user_article and !$self->is_linked_by($user_id)) {
	    $supplemental{'copy'} = $bibliotech->location.'add?uri='.$hash;
	    $supplemental{'copy'} .= '&from='.$for_user_article->user->username if $for_user_article;
	  }
	}
      }
    }
  }
  return \%supplemental;
}

sub tags {
  shift->packed_or_raw('Bibliotech::Tag', 'tags_packed', 'tags_raw');
}

sub tags_raw {
  Bibliotech::Tag->search_from_bookmark(shift->bookmark_id);
}

__PACKAGE__->set_sql(from_article => <<'');
SELECT 	 __ESSENTIAL__
FROM     __TABLE__
WHERE  	 article = ?

__PACKAGE__->set_sql(from_tag => <<'');
SELECT 	 __ESSENTIAL(b)__
FROM     __TABLE(Bibliotech::Tag=t)__,
       	 __TABLE(Bibliotech::User_Article_Tag=uat)__,
       	 __TABLE(Bibliotech::User_Article=ua)__,
       	 __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::Bookmark=b)__
WHERE  	 __JOIN(t uat)__
AND    	 __JOIN(uat ua)__
AND    	 __JOIN(ua a)__
AND    	 __JOIN(a b)__
AND    	 t.tag_id = ?
GROUP BY b.bookmark_id
ORDER BY b.url

__PACKAGE__->set_sql(used => <<'');
SELECT 	 __ESSENTIAL(b)__, COUNT(ua.user_article_id) as cnt
FROM     __TABLE(Bibliotech::User_Article=ua)__,
         __TABLE(Bibliotech::Article=a)__,
   	 __TABLE(Bibliotech::Bookmark=b)__
WHERE  	 __JOIN(ua a)__,
AND      __JOIN(a b)__
%s
GROUP BY b.bookmark_id
ORDER BY cnt DESC, b.created DESC

__PACKAGE__->set_sql(where => <<'');
SELECT 	 __ESSENTIAL(b)__
FROM     __TABLE(Bibliotech::Bookmark=b)__
         LEFT JOIN __TABLE(Bibliotech::Article=a)__ ON (__JOIN(b a)__)
         LEFT JOIN __TABLE(Bibliotech::User_Article=ua)__ ON (__JOIN(a ua)__)
WHERE  	 %s
ORDER BY b.created, b.url

# call count_user_articles() and the privacy parameter is handled for you
__PACKAGE__->set_sql(count_user_articles_need_privacy => <<'');
SELECT 	 COUNT(*)
FROM     __TABLE(Bibliotech::User_Article=ua)__
WHERE    ua.bookmark = ? AND %s

sub count_user_articles {
  my $self = shift;
  my $packed = $self->user_article_count_packed;
  return $packed if defined $packed;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_count_user_articles_need_privacy($privacywhere);
  $sth->execute($self, @privacybind);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

__PACKAGE__->set_sql(count_user_articles_no_privacy => <<'');
SELECT 	 COUNT(*)
FROM     __TABLE(Bibliotech::User_Article)__
WHERE    bookmark = ?

sub count_user_articles_no_privacy {
  my $self = shift;
  my $sth = $self->sql_count_user_articles_no_privacy;
  $sth->execute($self);
  my ($count) = $sth->fetchrow_array;
  $sth->finish;
  return $count;
}

sub user_article_comments {
  return Bibliotech::User_Article_Comment->search_from_bookmark(shift->bookmark_id);
}

sub comments {
  return Bibliotech::Comment->search_from_bookmark(shift->bookmark_id);
}

sub is_linked_by {
  my ($self, $user) = @_;
  return undef unless defined $user;
  my $user_id = UNIVERSAL::isa($user, 'Bibliotech::User') ? $user->user_id : $user;
  if (my $for_user_article = $self->for_user_article) {
    if (defined (my $packed = $for_user_article->article_is_linked_by_current_user)) {
      if ($packed->[0] == $user_id) {
	return $packed->[1];
      }
    }
  }
  my ($link) = Bibliotech::User_Article->search_from_article_for_user($self->article->article_id, $user_id);
  return $link;
}

sub txt_content {
  my ($self, $bibliotech, $verbose) = @_;
  my @output;
  my $citation = $self->cite;
  if (defined $citation) {
    if (my $citation_title = $citation->title) {
      push @output, $citation_title;
    }
  }
  elsif (my $title = $self->title) {
    push @output, $title;
  }
  if (defined $citation) {
    if (my $author_list = $citation->author_list(0, undef, 1)) {
      push @output, $author_list;
    }
    if (my $citation_line = $citation->citation_line($bibliotech)) {
      push @output, $citation_line;
    }
  }
  push @output, $self->url->as_string;
  if (defined $citation) {
    if (my @id = $citation->standardized_identifiers(bibliotech => $bibliotech, just_with_values => 1)) {
      push @output, map { $_->as_string } @id;
    }
  }
  return wantarray ? @output : join("\n", @output)."\n";
}

sub ris_content {
  my ($self, $bibliotech, $verbose, $for_user_article) = @_;
  my %ris;
  $ris{TI} = $self->label_title;
  $ris{UR} = $self->url->as_string;
  if ($verbose) {
    my $multi = defined $for_user_article ? $for_user_article : $self;
    $ris{KW} = [map { $_->name }            $multi->tags];
    $ris{U1} = [map { $_->plain_content(1) } $multi->user_article_comments];
    $ris{N2} = $for_user_article->description if defined $for_user_article;
  }
  if (my $citation = $self->cite) {
    $ris{TY} = $citation->inferred_ris_type;
    if (my @authors = $citation->authors) {
      $ris{AU} = [map($_->name(1), @authors)];
    }
    if (my $date = $citation->date) {
      $ris{PY} = $date->ymd('/');
    }
    if (my $journal = $citation->journal) {
      $ris{JF} = $journal->name;
      $ris{JO} = $journal->medline_ta;
      $ris{SN} = $journal->issn;
    }
    $ris{VL} = $citation->volume;
    $ris{IS} = $citation->issue;
    $ris{SP} = $citation->start_page;
    $ris{EP} = $citation->end_page;
    if (my $doi = $citation->doi) {
      $ris{M3} = $doi;
      $ris{N1} = $doi;
      $ris{UR} ||= $citation->doi_uri;
    }
  }
  else {
    $ris{TY} = 'ELEC';
  }
  return \%ris;
}

sub biblio_rdf {
  my ($self, $bibliotech) = @_;

  my $model    = RDF::Core::Model->new(Storage => Bibliotech::RDF::Core::Storage::Memory->new);
  my $subject  = RDF::Core::Resource->new(Bibliotech::Util::encode_xml_utf8($self->url));
  # (annoyingly, RDF::Core::Serializer does not quote RDF resource URL's)

  my $RDF      = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
  my $CONNOTEA = 'http://www.connotea.org/2005/01/schema#';
  my $DC       = 'http://purl.org/dc/elements/1.1/';
  my $DCTERMS  = 'http://purl.org/dc/terms/';
  my $PRISM    = 'http://purl.org/rss/1.0/modules/prism/';

  # create local shortcuts to keep statements below each on one line for easier reading
  my $S = sub { RDF::Core::Statement->new(@_) };
  my $R = sub { RDF::Core::Resource->new(@_) };
  my $L = sub { RDF::Core::Literal->new(@_) };

  my $xml = '';
  my $serializer = Bibliotech::RDF::Core::Model::Serializer->new
      (Model => $model,
       Output => \$xml,
       BaseURI => $bibliotech->location,
       _prefixes => {$CONNOTEA => 'connotea',
		     $DC       => 'dc',
		     $DCTERMS  => 'dcterms',
		     $PRISM    => 'prism'},
       preferred_subject_type => $R->($DCTERMS.'URI')
       );

  my $A = sub { $model->addStmt(@_); };

  $A->($S->($subject => $R->($RDF.'type') => $R->($DCTERMS.'URI')));
  $A->($S->($subject => $R->($DC.'title') => $L->($self->label_title(1).'')));  # can sometimes be a URI object

  if (my $citation = $self->cite) {
    if (my @authors = $citation->authors) {
      $A->($S->($subject => $R->($DC.'creator') => $L->($_->name))) foreach (@authors);
    }
    my $ids = $citation->standardized_identifiers(bibliotech => $bibliotech);
    if ($ids and @{$ids}) {
      my $blank_node_counter = 0;
      foreach my $id (@{$ids}) {
	my $node = $R->('_:#node'.++$blank_node_counter);
	$A->($S->($subject => $R->($CONNOTEA.$id->urilabel) => $R->(Bibliotech::Util::encode_xml_utf8($id->uri))));
	$A->($S->($subject => $R->($DC.'identifier')        => $node));
	$A->($S->($node    => $R->($RDF.'type')             => $R->($CONNOTEA.($id->xmlnoun || $id->noun))));
	$A->($S->($node    => $R->($CONNOTEA.'idValue')     => $L->($id->value || $id->uri->as_string)));
	$A->($S->($node    => $R->($RDF.'value')            => $L->($id->as_string)));
      }
    }
    if (my $date = $citation->date) {
      $A->($S->($subject => $R->($DC.'date') => $L->($date->ymd)));
    }
    if (my $journal = $citation->journal) {
      $A->($S->($subject => $R->($PRISM.'publicationName') => $L->($journal->name || $journal->medline_ta)));
      $A->($S->($subject => $R->($PRISM.'issn')            => $L->($journal->issn)));
    }
    if (my $volume = $citation->volume) {
      $A->($S->($subject => $R->($PRISM.'volume') => $L->($volume)));
    }
    if (my $issue = $citation->issue) {
      $A->($S->($subject => $R->($PRISM.'number') => $L->($issue)));
    }
    if (my $page = $citation->page) {
      if ($page =~ /(\d+)\s*-\s*(\d+)/) {
	my ($start, $end) = ($1, $2);
	$end = substr($start, 0, -length($end)) . $end if $start and $end and $end < $start;
	$A->($S->($subject => $R->($PRISM.'startingPage') => $L->($start)));
	$A->($S->($subject => $R->($PRISM.'endingPage')   => $L->($end)));
      }
      else {
	$A->($S->($subject => $R->($PRISM.'startingPage') => $L->($page)));
      }
    }
  }

  $serializer->serialize;
  $xml =~ s|^\s*<rdf:RDF[^>]*>||s;
  $xml =~ s|</rdf:RDF>\s*$||s;

  return $xml;
}

sub standard_annotation_text {
  my ($self, $bibliotech, $register) = @_;
  my $sitename = $bibliotech->sitename;
  my $label = $self->label_short;
  return "This is a list of postings for $label by users of $sitename.
          To copy this resource to your own $sitename library, $register";
}

# see Bibliotech::Util::get for documentation on return values
# this is just a cached utility to call that routine
sub get_network_document {
  my ($self, $bibliotech) = @_;
  my @document;
  if (my $document = $self->document) {
    @document = @{$document};
  }
  else {
    @document = Bibliotech::Util::get($self->url, $bibliotech);
    $self->document(\@document);
  }
  return wantarray ? @document : $document[1];
}

sub get_network_content {
  my ($self, $bibliotech) = @_;
  return scalar $self->get_network_document($bibliotech);
}

sub get_network_response {
  my ($self, $bibliotech) = @_;
  return ($self->get_network_document($bibliotech))[0];
}

sub get_network_title {
  my ($self, $bibliotech) = @_;
  return ($self->get_network_document($bibliotech))[2];
}

# when a citation is added to a bookmark, give an opportunity to go to the article and write a new concatenated citation
sub citation_added {
  my $bookmark = shift;
  my $article = $bookmark->article or return;
  Bibliotech::Unwritten::CitationConcat::add_article_citation($article);
}

1;
__END__
