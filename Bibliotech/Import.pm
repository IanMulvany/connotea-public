# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Import class is a base class for import modules

# The importer supports a two-stage file parse. It is possible to
# parse a file straight out, or to parse it into blocks and then parse
# each block indepedently. The latter approach is slightly preferred
# as it allows the system to simply skip records with minor
# incompatiblities and still present the rest of the entries to the
# user for importing. In "the wild" file formats are generally so
# unreliable that this is good practice.

use Bibliotech::CitationSource;
use Bibliotech::CitationSource::NPG;

package Bibliotech::Import;
use strict;
use base 'Class::Accessor::Fast';
use List::Util qw/first/;
use Bibliotech::DBI;

our $IMPORT_MAX_COUNT = Bibliotech::Config->get('IMPORT_MAX_COUNT') || 1000;

__PACKAGE__->mk_accessors(qw/bibliotech bibliotech_parser
                             user doc data selections given_tags
                             use_keywords trial_mode captcha/);

# a human-readable name to refer to the import module as a whole, e.g. 'RIS'
# if the module can read from multiple sources, use an inclusive name
sub name {
  undef;
}

# should return a version number for the source module (needs no
# correlation to the outside, just needs to be different each time the
# module is substantially changed)
sub version {
  'alpha-version';
}

# should return 1 in an overridden module
sub api_version {
  0;  # zero will cause the module to be skipped
}

# return the MIME type this module handles
#   (not used yet - for future features)
sub mime_types {
  ('*/*');
}

# return the filename extension this module handles
#   (not used yet - for future features)
sub extensions {
  ();
}

# return 'RIS' or 'RSS' or something that signifies the content type
sub noun {
  local $_ = shift->name;
  s/ *\(.*\) *//;  # remove parenthetical parts
  s/ *\[.*\] *//;
  return $_;
}

sub file_noun {
  shift->noun.' file';
}

sub keyword_noun {
  'keyword';
}

sub ignore_keywords_use_given_tags {
  shift->use_keywords(0);
}

sub use_keywords_plus_given_tags {
  shift->use_keywords(1);
}

sub use_keywords_or_default_to_given_tags {
  shift->use_keywords(2);
}

# selections is representative of the checkboxes that lets a user
# deselect certain entries from import after the first pass
sub parse_selections {
  my $selections_ref = shift->selections;
  my ($select_all, @selections);
  if (defined $selections_ref) {
    $select_all = 0;
    @selections = sort {$a <=> $b} @{$selections_ref};
  }
  else {
    $select_all = 1;
  }
  return ($select_all, @selections);
}

# given tags is the list of tags given by the user to serve as a
# default list (depending on tag logic selected)
sub parse_given_tags {
  my $given_tags_ref = shift->given_tags;
  return () unless defined $given_tags_ref;
  my @tags = (ref $given_tags_ref ? @{$given_tags_ref} : ($given_tags_ref));
  return grep($_, @tags);
}

# called to determine if an import module understands a document
sub understands {
  undef;
}

# called before all the fetch()'ing
# there is an accessor called data() that this method is free to use to pass data to fetch()
# if you bless an array of Bibliotech::Import::Entry's into a Bibliotech::Import::EntryList,
# you can use the default fetch() method
sub parse {
  undef;
}

# keep returning Bibliotech::Import::Entry objects, one for each entry in the file
# return undef when done
sub fetch {
  shift->data->shift;
}

# return (unwritten) user_articles in Bibliotech::Import::ResultList (even if only one)
# analogous to citations() method in Bibliotech::CitationSource
sub user_articles {
  my $self = shift;
  $self->trial_mode(2);
  return $self->generate_user_articles;
}

# return (unwritten) user_articles in Bibliotech::Import::ResultList (even if only one)
# articles will be preadd()'d and authoritative metadata will be fetched and noted
sub user_articles_write_articles {
  my $self = shift;
  $self->trial_mode(1);
  return $self->generate_user_articles;
}

# actually write
sub import_user_articles {
  my $self = shift;
  $self->trial_mode(0);
  return $self->generate_user_articles;
}

our $NO   = 'This record will not be added to your library because';
our $NOPE = 'This record will not be added because';

sub _uploaded_tag_name {
  'uploaded';
}

# do the work
sub generate_user_articles {
  my $self = shift;

  my $bibliotech        = $self->bibliotech;  # don't fail unless trial_mode != 2 ... see below
  my $bibliotech_parser = $self->bibliotech_parser || ($bibliotech ? $bibliotech->parser : undef)
      or die 'need a bibliotech parser';
  my $user              = $self->user;  # don't fail unless trial_mode != 2 ... see below
  my ($select_all,
      @selections)      = $self->parse_selections;
  my @given_tags        = $self->parse_given_tags;
  my $use_keywords      = $self->use_keywords || 0;
  my $trial_mode        = int($self->trial_mode);
  my $captcha           = $self->captcha;

  unless ($bibliotech) {
    die 'need a bibliotech object' unless $trial_mode == 2;
  }
  unless ($user) {
    die 'need a user object' unless $trial_mode == 2;
    $user = construct Bibliotech::User ({username => 'testuser'});
  }

  @given_tags = (_uploaded_tag_name()) if !$use_keywords and !@given_tags;

  my %invalid_renamed;
  my $invalid_fallback_count = 'A';
  my @result;
  my @uri_list;

  my $count = 0;
  my $count_acceptable = 0;

  $self->parse;
 
  while (my $entry = $self->fetch) {
    $count++;
    unless ($select_all) { next unless $count == $selections[0]; shift @selections; }  # skip if unchecked
    $count_acceptable++;  # gets decremented back in case of error
    
    my ($user_article, @info, $uri, $title, $description, @tags);
    my $accept = sub {
      my ($info_ref, $tags_ref);
      ($info_ref, $uri, $title, $description, $tags_ref) = @_;
      @info = @{$info_ref};
      @tags = @{$tags_ref};
    };

    eval {
      die _skip_max_message($count, $IMPORT_MAX_COUNT) if $count_acceptable > $IMPORT_MAX_COUNT;
      $accept->($self->_entry_analyze($entry, $count, $use_keywords, \@given_tags, \@result,
				      $trial_mode, $user,
				      \%invalid_renamed, \$invalid_fallback_count,
				      sub { my ($uri, $title) = @_;
					    $bibliotech->preadd(uri => $uri, title => $title); },
				      sub { my ($uri, $user) = @_;
					    $bibliotech->check(uri => $uri, user => $user); },
				      sub { my $tag_list = shift;
					    $bibliotech_parser->tag_list($tag_list); }));
    };
    my $error;
    my $is_spam = 0;
    if ($@) {
      die $@ if $@ =~ / at .* line /;
      $error = $@;
      $count_acceptable--;
    }
    push @tags, _uploaded_tag_name() unless @tags;
    my $construct_all = 0;
    my $noncommital = $trial_mode || ($error ? 1 : 0);
    if ($noncommital == 2) {
      $construct_all = 1;
    }
    else {
      eval {
	$user_article = $bibliotech->add(uri         => $uri,
					 title       => $title,
					 description => $description,
					 tags 	     => \@tags,
					 user 	     => $user,
					 captcha     => $captcha,
					 construct   => $noncommital);
      };
      if (my $e = $@) {
	die $e if $e =~ / at .* line /;
	if ($e =~ /^SPAM/) {
	  $is_spam = 1;
	}
	else {
	  $error ||= $e;
	}
	$construct_all = 1;
      }
    }
    if ($construct_all) {
      my $uri_obj   = URI->new("$uri" || 'NO_URI');
      my $bookmark  = Bibliotech::Unwritten::Bookmark->construct({url => $uri_obj});
      my $article   = Bibliotech::Unwritten::Article->new_from_bookmark_and_citation($bookmark, undef);
      $user_article = Bibliotech::Unwritten::User_Article->construct
	  ({user        => $user,
	    article     => $article,
	    bookmark    => $bookmark,
	    title       => $title,
	    description => $description,
	   });
      $user_article->tags([map { Bibliotech::Unwritten::Tag->new({name => $_}) } @tags]);
      $user_article->bookmark->for_user_article($user_article);
      $noncommital = 1;
    }
    die 'no user_article object' unless defined $user_article;
    my $bookmark = $user_article->bookmark;
    die 'no bookmark object' unless defined $bookmark;
    if ($bookmark->citation) {
      push @info, _authoritative_citation_message($self->file_noun);
    }
    else {
      if (my $citation = $entry->citation($self)) {
	unless ($citation->is_only_title_eq($title)) {
	  $citation->update;
	  if ($noncommital) {
	    $user_article->citation($citation);
	    $user_article->update;
	  }
	  else {
	    $citation->write($user_article);
	  }
	}
      }
    }
    push @result, Bibliotech::Import::Result->new({block        => $entry->block,
						   user_article => $user_article,
						   warning      => (@info ? join("\n", @info) : undef),
						   error        => $error,
						   is_spam      => $is_spam,
						  });
  }
  return Bibliotech::Import::ResultList->new(@result);
}

sub _skip_max_message {
  my ($count, $max_count) = @_;
  join('',
       'Entry #',
       $count,
       ' will be skipped because there is an import limit of ',
       $max_count,
       " entries per file.\n");
}

sub _authoritative_citation_message {
  my ($file_noun) = @_;
  join('',
       'The link associated with this record has been understood and ',
       'authoritative bibliographic information will be used in place of the data in the ',
       $file_noun,
       ".\n");
}

sub _entry_analyze {
  my ($self, $entry, $count, $use_keywords, $given_tags_ref, $result_ref, $trial_mode, $user,
      $invalid_renamed_ref, $invalid_fallback_count_ref,
      $preadd_sub, $check_library_sub, $parse_tag_list_sub) = @_;

  my (@info, $uri, $title, $description, @tags);

  $entry->parse($self);
  die _cannot_parse_message($self->noun, $count) unless $entry->parse_ok;

  $uri = _uri_array_to_one(_entry_get_or_make_uri($entry));

  $title       = $entry->title;
  $description = $entry->description;

  if ($trial_mode != 2) {
    if (my $bookmark = $preadd_sub->($uri, $title)) {
      $uri = $bookmark->uri;  # preadd can actually change the URI
    }
  }

  _back_check_for_dups($uri => $result_ref);

  @tags = $self->_entry_collect_tags($entry, $use_keywords, $given_tags_ref,
				     $invalid_renamed_ref, $invalid_fallback_count_ref,
				     $parse_tag_list_sub, sub { push @info, @_; });

  die _already_have_message() if $trial_mode != 2 && $check_library_sub->($uri, $user);

  return (\@info, $uri, $title, $description, \@tags);
}

sub _cannot_parse_message {
  my ($noun, $count) = @_;
  join('', 'Could not parse ', $noun, ' entry \#', $count, ".\n");
}

sub _already_have_message {
  "$NOPE you already have it in your library.\n";
}

sub _entry_get_or_make_uri {
  my $entry = shift or return;
  if ($entry->can('uri')) {
    if (my $uri = $entry->uri) {
      return $uri;
    }
  }
  if ($entry->can('pubmed')) {
    if (my $pubmed = $entry->pubmed) {
      return 'http://www.ncbi.nlm.nih.gov/pubmed/'.$pubmed;
    }
  }
  if ($entry->can('doi')) {
    if (my $doi = $entry->doi) {
      return 'http://dx.doi.org/'.lc($doi);
    }
  }
  if ($entry->can('asin')) {
    if (my $asin = $entry->asin) {
      return 'http://www.amazon.com/exec/obidos/ASIN/'.$asin;
    }
  }
  die "$NO it contains no detectable URI, PMID, DOI, or ASIN.\n";
}

# tolerate an array of URI's - select what looks like a real one, or go with the first
sub _uri_array_to_one {
  my $uri = shift or return;
  ref $uri eq 'ARRAY' or return $uri;
  return (first { /\.([a-z]?html?|asp|php)$/i } @{$uri}) || $uri->[0];
}

sub _back_check_for_dups {
  my ($uri, $result_ref) = @_;
  my $count = @{$result_ref};
  for (my $i = 0; $i < $count; $i++) {
    my $prior_uri = $result_ref->[$i]->user_article->bookmark->url;
    die _dup_messasge($i+1) if $prior_uri eq $uri;
  }
}

sub _dup_messasge {
  my ($prior) = @_;
  join('', "$NO the link associated with it is a duplicate of another in this batch (see \#", $prior, ").\n");
}

sub _entry_collect_tags {
  my ($self, $entry, $use_keywords, $given_tags_ref, $invalid_renamed_ref,
      $invalid_fallback_count_ref, $parse_tag_list_sub, $info_sub) = @_;
  my (@keywords, @tags);
  if ($use_keywords) {
    my ($original_keywords_ref, $keywords_info_ref) = $entry->keywords;
    $info_sub->(@{$keywords_info_ref}) if @{$keywords_info_ref};
    my %asterisk_info;
    foreach my $original_keyword (@{$original_keywords_ref}) {
      next unless $original_keyword;
      if (my $renamed = $invalid_renamed_ref->{$original_keyword}) {
	push @keywords, $renamed;
      }
      else {
	my $keyword = $original_keyword;
	my @info;
	my @tested = $parse_tag_list_sub->("\"$keyword\"");
	unless (@tested == 1) {
	  $keyword =~ s/[,\/\+\"\?\']//g;
	  @tested = $parse_tag_list_sub->("\"$keyword\"");
	  unless (@tested == 1) {
	    $keyword = 'kw_'.$keyword;
	    @tested = $parse_tag_list_sub->("\"$keyword\"");
	    unless (@tested == 1) {
	      @tested = ($keyword = 'keyword_invalid_as_tag_'.${$invalid_fallback_count_ref});
	      ${$invalid_fallback_count_ref}++;
	    }
	  }
	  $invalid_renamed_ref->{$original_keyword} = $tested[0];
	  push @info, _renaming_message($self->keyword_noun, $original_keyword, $tested[0]);
	}
	my $selected = $tested[0];
	if ($selected =~ s/^\*//) {
	  unless ($asterisk_info{$selected}) {
	    $asterisk_info{$selected} = 1;
	    $info_sub->(_asterisk_message($self->keyword_noun, $original_keyword));
	  }
	}
	unless (grep { $selected eq $_ } @keywords) {
	  push @keywords, $selected;
	  $info_sub->($_) foreach @info;
	}
      }
    }
    push @tags, @keywords;
  }
  unshift @tags, @{$given_tags_ref} if $use_keywords != 2 or ($use_keywords == 2 and !@keywords);

  die _no_tags_message() unless @tags;

  return @tags;
}

sub _no_tags_message {
  "$NO no tags can be associated with it.\n";
}

sub _renaming_message {
  my ($keyword_noun, $original_keyword, $replacement_keyword) = @_;
  join('',
       'The ',
       $keyword_noun,
       " \"",
       $original_keyword,
       "\" will become tag \"",
       $replacement_keyword,
       "\" to accommodate tag naming rules.\n");
}

sub _asterisk_message {
  my ($keyword_noun, $original_keyword) = @_;
  join('',
       'The ',
       $keyword_noun,
       " \"",
       $original_keyword,
       "\" has had a leading asterisk removed.\n");
}

package Bibliotech::Import::Entry;
use strict;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/block data parse_ok uri title description citation/);

# if we got a scalar of raw file content just store it in an accessor called block()
# if we got a scalar of a helper object just store it in an accessor called data()
sub new {
  my $self = shift;
  if (@_ == 1 and ref($_[0]) ne 'HASH') {
    my $obj = shift;
    return $self->SUPER::new({data => $obj}) if ref $obj;
    return $self->SUPER::new({block => $obj});
  }
  return $self->SUPER::new(@_);
}

# perform some parsing action and set parse_ok(); recieves the
# importer object as an argument (the Bibliotech::Import derived
# object); this method is free to read block() and set some data in
# data() to assist in the following method calls if necessary
sub parse {
  shift->parse_ok(1);
}

# this returns keywords after they have been cleaned up - better to
# override raw_keywords()
sub keywords {
  shift->split_keywords;
}

# override this to return a list of keywords, it will still be split
# by split_keywords()
sub raw_keywords {
  ();
}

sub split_keywords {
  my ($self, $split_regex, $split_error) = @_;
  $split_regex ||= qr/[,;\/]\s*/;
  $split_error ||= 'Keyword starting with "%s" split.';
  my @keywords;
  my @info;
  foreach my $raw_keyword ($self->raw_keywords) {
    my @parts = split($split_regex, $raw_keyword);
    push @info, sprintf($split_error, $parts[0]) if @parts > 1;
    push @keywords, @parts;
  }
  return (\@keywords, \@info);
}

# return the citation object - this is a good default implementation, supply a citation_obj() method if you like
sub citation {
  my ($self, $importer) = @_;
  my $citation_obj = $self->can('citation_obj') ? $self->citation_obj : $self->data;
  return undef unless defined $citation_obj;
  return Bibliotech::Unwritten::Citation->from_citationsource_result
      ($citation_obj, 1, $importer->name.' '.$importer->version);
}

package Bibliotech::Import::Entry::FromData;
use strict;
use base 'Bibliotech::Import::Entry';
# use this class if your data() object has most of the answers

sub from_data {
  my ($self, $field) = @_;
  my $data = $self->data or return undef;
  return UNIVERSAL::can($data, $field) ? $data->$field : undef;
}

sub uri   	{ shift->from_data('uri'); }
sub title 	{ shift->from_data('title'); }
sub description { shift->from_data('description'); }
sub doi         { shift->from_data('doi'); }
sub pubmed      { shift->from_data('pubmed'); }
sub asin        { shift->from_data('asin'); }

package Bibliotech::Import::EntryList;
use strict;
use base 'Set::Array';

# return next result or undef if finished
sub fetch {
  shift->shift;  # ;-)
}

package Bibliotech::Import::ResultList;
use strict;
use base 'Set::Array';

# return next result or undef if finished
sub fetch {
  shift->shift;  # ;-)
}

package Bibliotech::Import::Result;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/block user_article warning error is_spam/);

1;
__END__
