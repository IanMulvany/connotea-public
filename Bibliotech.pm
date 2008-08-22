# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech class provides an object that holds all of the runtime data
# needed to service an incoming request, and provides methods that perform
# fundamental operations.

=head1 NAME

Bibliotech - Connotea Code Perl modules

=cut

package Bibliotech;
use strict;
use base 'Class::Accessor::Fast';
use Digest::MD5 qw/md5_hex/;
use Encode qw/encode_utf8/;
use Bio::Biblio::IO;
use Set::Array;
use IO::File;
use Bibliotech::Const;
use Bibliotech::Config;
use Bibliotech::Util;
use Bibliotech::DBI;
use Bibliotech::Parser;
use Bibliotech::Query;
use Bibliotech::Log;
use Bibliotech::Bookmarklets;
use Bibliotech::Plugin;
use Bibliotech::CitationSource;
use Bibliotech::Import;
use Bibliotech::Antispam;

our $VERSION = '1.8';

our $SITE_NAME              	= Bibliotech::Config->get_required('SITE_NAME');
our $SITE_EMAIL             	= Bibliotech::Config->get_required('SITE_EMAIL');
our $SERVER_ID             	= Bibliotech::Config->get('SERVER_ID');
our $USER_VERIFYCODE_SECRET 	= Bibliotech::Config->get('USER_VERIFYCODE_SECRET');
our $IMPORT_MAX_COUNT           = Bibliotech::Config->get('IMPORT_MAX_COUNT') || 500;
our $EXCEPTION_ERROR_REPORTS_TO = Bibliotech::Config->get('EXCEPTION_ERROR_REPORTS_TO') || $SITE_EMAIL;
our $SKIP_EMAIL_VERIFICATION    = Bibliotech::Config->get('SKIP_EMAIL_VERIFICATION');
our $ANTISPAM_SCORE_LOG         = Bibliotech::Config->get('ANTISPAM', 'SCORE_LOG');
our $ANTISPAM_CAPTCHA_LOG       = Bibliotech::Config->get('ANTISPAM', 'CAPTCHA_LOG');

__PACKAGE__->mk_accessors(qw/path canonical_path canonical_path_for_cache_key
			     parser command query request cgi location
			     title heading link description user
			     no_cache has_rss docroot error memcache log load/);

sub version {
  $VERSION;
}

sub sitename {
  $SITE_NAME;
}

sub siteemail {
  $SITE_EMAIL;
}

sub server_id {
  $SERVER_ID;
}

sub sitename_plus_server_id {
  return $SITE_NAME unless $SERVER_ID;
  return $SITE_NAME.' ('.$SERVER_ID.')';
}

sub process {
  my ($self, %options) = @_;
  my $verb = $options{verb};
  my $die_on_error = $options{die_on_error};
  my $text = $self->path;
  eval {
    $self->parser(Bibliotech::Parser->new);
    my $command = $self->parser->parse($text, $verb) or die "bad command ($text)\n";
    $self->command($command);
    my $query = Bibliotech::Query->new($command, $self) or die "bad query\n";
    $query->activeuser($self->user);
    $self->query($query);
  };
  if ($@) {
    die $@ if $die_on_error;
    $self->error($@);
    $self->command($self->parser->parse('/error'));
  }
  return $self->query;
}

sub results {
  my ($self, $text) = @_;
  my $func = $self->command->page or die 'no page';
  return $self->query->$func;
}

sub import_file {
  my ($self, $user, $type, $doc, $selections_ref, $given_tags_ref, $use_keywords, $trial_mode, $captcha) = @_;
  die "Document is empty.\n" unless $doc;
  $doc =~ s/\r\n?/\n/g;  # un-Windowsify and un-Macify
  my $options = {bibliotech   => $self,
		 user         => $user,
		 doc          => $doc,
		 selections   => $selections_ref,
		 given_tags   => $given_tags_ref,
		 use_keywords => $use_keywords,
		 trial_mode   => $trial_mode,
		 captcha      => $captcha,
	        };
  my $importer;
  if ($type) {
    my $class = 'Bibliotech::Import::'.$type;
    $class->can('user_articles') or die "type $type not supported";
    $importer = $class->new($options) or die 'no importer object';
    my $score = $importer->understands($doc);
    die "Sorry, this file was not recognized as the selected type.\n" unless $score;
    die "Sorry, cannot analyze document now due to a transient error. Please try again later.\n" if $score < 0;
  }
  else {
    my $scanner = new Bibliotech::Plugin::Import;
    $importer = $scanner->scan($doc, [$options])
	or die "File format not recognized. Please check the list of types supported.\n";
  }
  return $importer->generate_user_articles;
}

sub preadd_validate_uri {
  my $uri = pop;
  my $ref = ref $uri;              # URI has subclasses per type of URI
  $ref && $ref ne 'URI::_generic'  # they are all ISA URI::_generic but if that's *all* then reject it
      or die "Sorry, this URL does not appear to be valid.\n";
  $uri->isa('URI')
      or die "Sorry, this URL does not appear to be valid (not URI object).\n";
  my $scheme = $uri->scheme        # if the scheme part of the URI is blank reject it (redundant with last check)
      or die "Sorry, the scheme on your URI is not understood.\n";
  $scheme !~ /^(file|mailto|data|chrome|about)$/
      or die "Sorry, ${scheme}: URI\'s are not allowed.\n";
  my $length = length("$uri");
  $length <= 400                   # this is just for practicality - the database field is this long
      or die "Sorry, URI\'s over 400 characters long are not supported ".
             "(URI provided is $length characters long).\n";
  return $uri;
}

sub _might_give_replacement_bookmark {
  my ($original_bookmark, $action) = @_;
  my $maybe_new_bookmark = $action->();
  return $maybe_new_bookmark if defined $maybe_new_bookmark;
  return $original_bookmark;
}

sub preadd_insert {
  my ($self, $uri, $title) = @_;
  my $bookmark = Bibliotech::Bookmark->insert({url => $uri});
  $bookmark = _might_give_replacement_bookmark($bookmark, sub { $self->pull_title($bookmark, $title) });
  $bookmark = _might_give_replacement_bookmark($bookmark, sub { $self->pull_citation($bookmark) });
  return $bookmark;
}

sub preadd {
  my ($self, %options) = @_;
  my $uri   = preadd_validate_uri(Bibliotech::Bookmark->normalize_option_to_simple_uri_object(\%options));
  my $title = $options{title};
  my ($bookmark) = Bibliotech::Bookmark->search(url => $uri);
  $bookmark = $self->preadd_insert($uri, $options{title}) unless defined $bookmark;
  return $bookmark;
}

sub _popular_tag_names_for_change_antispam_calc {
  [map { $_->name }
   Bibliotech::Tag->search_for_popular_tags_in_window
   ('30 DAY', '10 MINUTE', ['uploaded'], 5, 5, 5, 1, 100)];
}

sub popular_tag_names_for_change_antispam {
  my $self = shift;
  my $memcache = $self->memcache;
  my ($cache_key, $now);
  if ($memcache) {
    $cache_key = Bibliotech::Cache::Key->new($self,
					     class => ref $self,
					     method => '_popular_tag_names_for_change_antispam');
    $now = Bibliotech::Util::now();
    my $cached = $memcache->get_with_last_updated($cache_key, $now, 1, 1);
    return $cached if defined $cached;
  }
  my $ref = _popular_tag_names_for_change_antispam_calc();
  $memcache->set_with_last_updated($cache_key, $ref, $now) if defined $cache_key;
  return $ref;
}

sub change {
  my ($self, %options) = @_;

  my $action = $options{action};
  my ($add, $addcomment, $edit) = (0, 0, 0);
  if (!$action or $action eq 'add') {
    $add = 1;
  }
  elsif ($action eq 'addcomment') {
    $addcomment = 1;
  }
  elsif ($action eq 'edit') {
    $edit = 1;
  }

  my $firstexists = sub {
    my $ops = shift;
    foreach (@_) {
      return defined $ops->{$_} ? $ops->{$_} : '' if exists $ops->{$_};
    }
    return;
  };

  my $user           = Bibliotech::User->normalize_option(\%options);

  $user->active or die "Sorry, this account is inactive.\n";

  my $bookmark       = $self->preadd(%options);

  my $title          = $firstexists->(\%options, qw/usertitle title/);
  my $description    = $firstexists->(\%options, qw/description/);

  my $user_is_author = $firstexists->(\%options, qw/mywork user_is_author/);
  my $private        = $firstexists->(\%options, qw/private/);

  my $private_gang = Bibliotech::Gang->normalize_option(\%options, optional => 1, blank_for_undef => 1);
  if (defined $private_gang && $private_gang ne '') {
    my $private_gang_id = $private_gang->gang_id;
    unless (grep($private_gang_id == $_->gang_id, $user->gangs)) {
      die 'You are not a member of the group '.$private_gang->name.".\n";
    }
  }

  my $private_until = $firstexists->(\%options, qw/private_until privateuntil embargo/);
  if ($private_until) {
    $private_until = Bibliotech::Date->new($private_until, 1) unless ref $private_until;
    die "Invalid \"private until\" date.\n" if $private_until->invalid;
    die "The \"private until\" date has already passed.\n" if $private_until->has_been_reached;
  }

  my $tags_ref;
  if ($add or $edit) {
    $tags_ref = $options{tags} or die "You must specify at least one tag.\n";
    @{$tags_ref} > 0 or die "You must specify at least one tag.\n";
    my $parser = $self->parser;
    foreach my $tag (@{$tags_ref}) {
      $parser->check_tag_format($tag) or die "Invalid tag name: $tag\n";
    }
    Bibliotech::SpecialTagSet->scan($tags_ref);  # will die in case of problems
  }

  my $comment     = Bibliotech::Util::sanitize($options{comment});
  my $lastcomment = Bibliotech::Util::sanitize($options{lastcomment});

  my $copying_user_article;
  if ($options{from}) {
    my $from = Bibliotech::User->normalize_option(\%options, field => 'from');
    if ($from->user_id != $user->user_id) {
      ($copying_user_article) = Bibliotech::User_Article->search(user => $from, bookmark => $bookmark);
    }
  }

  Bibliotech::Antispam::is_not_spam_or_die_with_special
      ($user, $bookmark,
       $tags_ref, $description, $title, $comment,
       do { my $citation = $bookmark->citation;
	    defined $citation ? (1, $citation->cs_score || undef)
                              : (0, undef); },
       $options{prefilled} || 0,
       $self->popular_tag_names_for_change_antispam || [],
       $options{captcha} || 0,
       $user->is_captcha_karma_bad,
       $ANTISPAM_SCORE_LOG,
       $ANTISPAM_CAPTCHA_LOG,
      )
      if (($add or $edit) and !$options{skip_antispam});


  my $dbh = Bibliotech::DBI->db_Main;
  $dbh->do('SET AUTOCOMMIT=0');
  my $user_article = eval {
    my $user_citation;
    my $operative_citation = $bookmark->citation;
    if ($add or $edit) {
      if (defined $options{user_citation}) {
	my $parsed_citation = eval {
	  Bibliotech::Unwritten::Citation->from_hash_of_text_values($options{user_citation});
	};
	if ($@) {
	  die "Citation: $@" if $@ !~ /\bcitation\b/i;
	  die $@;
	}
	$user_citation = $parsed_citation->write;
	$operative_citation = $user_citation;
      }
    }
    my $user_article;
    unless ($options{construct}) {
      if ($add) {
	my $article = Bibliotech::Article->find_or_create_for_bookmark_and_citation($bookmark, $operative_citation);
	die 'no article object' unless defined $article;
	$bookmark->article($article);
	$bookmark->update;
	$article->reconcat_citations;
	my ($existing) = Bibliotech::User_Article->search(user => $user, article => $article);
	if (defined $existing) {
	  # switch to the new bookmark
	  $user_article = $existing;
	  $user_article->bookmark($bookmark);
	  $user_article->update;
	}
	else {
	  $user_article = $user->link_bookmark([$bookmark, $article]);
	}
	die 'no user_article object' unless defined $user_article;
      }
      else {
	$user_article = $user->find_bookmark($bookmark);
	die "This URI was not found for this user.\n" unless defined $user_article;
      }
    }
    else {
      my $article = Bibliotech::Unwritten::Article->new({hash => $bookmark->hash});
      $user_article = Bibliotech::Unwritten::User_Article->construct({user     => $user,
								      bookmark => $bookmark,
								      article  => $article});
      die 'no unwritten user_article object' unless defined $user_article;
      $user_article->bookmark->for_user_article($user_article);
    }
    if (($add and $user->quarantined) or $options{captcha} == 1) {
      # adding by a quarantined user, or they were given a captcha and passed it - quarantine this post
      $user_article->set_datetime_now('quarantined');
    }
    if ($add or $edit) {
      if ($add) {
	if (!$bookmark->first_user) {
	  $bookmark->first_user($user);
	  $bookmark->update;
	}
	if ($copying_user_article) {
	  if (my $copying_citation = $copying_user_article->citation) {
	    $user_article->citation($copying_citation);
	  }
	}
      }
      $user_article->user_is_author($user_is_author ? 1 : 0) if $add or defined $user_is_author;
      $user_article->private       ($private        ? 1 : 0) if $add or defined $private;
      $user_article->private_gang  ($private_gang  || undef) if $add or defined $private_gang;
      $user_article->private_until ($private_until || undef) if $add or defined $private_until;

      # def_public is merely a speed optimization field for faster
      # SQL. We don't allow a value to be passed in; for consistency we
      # simply calculate the correct value here.
      $user_article->def_public    (($user_article->private               ||
				     defined $user_article->private_gang  ||
				     defined $user_article->private_until ||
				     defined $user_article->quarantined)     ? 0 : 1);

      if (defined $title or defined $description) {
	$user_article->title($title || undef)                if $add or defined $title;
	$user_article->description($description || undef)    if $add or defined $description;
	$user_article->mark_updated;
      }
      $user_article->update_links_one_to_many('Bibliotech::Tag' => $tags_ref);
      if ($edit) {
	if (defined $lastcomment) {
	  if ($lastcomment) {
	    $user_article->update_last_comment($lastcomment);
	  }
	  else {
	    if (my $user_article_comment = $user_article->last_user_article_comment) {
	      my $comment = $user_article_comment->comment;
	      $user_article_comment->delete;
	      $comment->delete unless $comment->user_article_comments->count;
	    }
	  }
	}
      }
      $user_article->citation($user_citation) if defined $user_citation;
    }
    $user_article->link_comment($comment) if $comment;
    $user_article->mark_updated;
    return $user_article;
  };
  if (my $e = $@) {
    $dbh->do('ROLLBACK');
    $dbh->do('SET AUTOCOMMIT=1');
    die $e;
  }
  $dbh->do('COMMIT');
  $dbh->do('SET AUTOCOMMIT=1');
  return $user_article;
}

sub add {
  my ($self, %options) = @_;
  $options{action} = 'add';
  return $self->change(%options);
}

sub addcomment {
  my ($self, %options) = @_;
  $options{action} = 'addcomment';
  return $self->change(%options);
}

sub edit {
  my ($self, %options) = @_;
  $options{action} = 'edit';
  return $self->change(%options);
}

sub remove {
  my ($self, %options) = @_;
  my $user_article = $self->check(%options) or return 0;
  return $self->remove_user_article($user_article);
}

sub remove_user_article {
  my ($self, $user_article) = @_;
  $user_article->delete;  # all logic pushed into DBI.pm
  return 1;
}

sub check {
  my ($self, %options) = @_;

  my $user = Bibliotech::User->normalize_option(\%options);

  my $uri = Bibliotech::Bookmark->normalize_option_to_simple_uri_object(\%options);
  my ($bookmark) = Bibliotech::Bookmark->search(url => $uri);
  return 0 unless defined $bookmark;

  my $article = $bookmark->article;
  return 0 unless defined $article;

  my ($user_article) = Bibliotech::User_Article->search(user => $user, article => $article);
  return 0 unless defined $user_article;

  return $user_article;
}

sub pull_title {
  my ($self, $bookmark, $title) = @_;
  unless ($title) {
    my $uri = $bookmark->url;
    my $unproxied_uri = $self->proxy_translate_uri($uri);
    if (defined $unproxied_uri) {
      $title = (Bibliotech::Util::get($unproxied_uri, $self))[2];
    }
    else {
      $title = $bookmark->get_network_title($self);
    }
  }
  if ($title) {
    $bookmark->title($title);
    $bookmark->update;
  }
  return $bookmark;
}

sub pull_citation {
  my ($self, $bookmark1, $mod_obj, $die_on_errstr) = @_;
  my ($bookmark2, $citations, $module_str, $module_score) = $self->pull_citation_calc($bookmark1, $mod_obj, $die_on_errstr);
  return $bookmark2 if !$citations;
  return $self->pull_citation_save($bookmark2, $citations, $module_str, $module_score);
}

sub scan_for_best_citation_source_module_for_uri {
  my ($self, $uri, $document_callback) = @_;
  my $scanner = Bibliotech::Plugin::CitationSource->new;
  return $scanner->scan($uri, [$self], [$document_callback]);
}

sub scan_for_best_proxy_module_for_uri {
  my ($self, $uri) = @_;
  my $scanner = Bibliotech::Plugin::Proxy->new;
  return $scanner->scan($uri, [$self], []);
}

sub proxy_translate_uri {
  my ($self, $uri) = @_;
  #warn "proxy_translate_uri: <<< $uri";
  my $proxy_mod = $self->scan_for_best_proxy_module_for_uri($uri) or return;
  my $new_uri = $proxy_mod->filter($uri);
  #warn "proxy_translate_uri: >>> $new_uri";
  return $new_uri;
}

sub make_document_callback {
  my ($self, $bookmark_or_uri) = @_; 
  my $cache;
  if (!ref($bookmark_or_uri) or UNIVERSAL::isa($bookmark_or_uri, 'URI')) {
    my $uri = $bookmark_or_uri;  # for clarity
    return sub { return Bibliotech::Util::get($uri, $self, \$cache) };
  }
  my $bookmark = $bookmark_or_uri;  # for clarity
  return UNIVERSAL::can($bookmark, 'get_network_document')
           ? sub { return $bookmark->get_network_document($self) }
           : sub { return Bibliotech::Util::get($bookmark->url, $self, \$cache) };
}

sub pull_citation_calc {
  my ($self, $bookmark, $mod_obj, $die_on_errstr) = @_;

  defined $bookmark or die 'must provide a bookmark';

  (   UNIVERSAL::can($bookmark, 'url')
   && UNIVERSAL::can($bookmark, 'user_articles')
   && UNIVERSAL::can($bookmark, 'delete')
   && UNIVERSAL::can($bookmark, 'update'))
    or die 'bookmark object type is not recognized ('.ref($bookmark).')';

  my $uri = $bookmark->url or return ($bookmark);

  my $unproxied_uri = $self->proxy_translate_uri($uri);
  $uri = $unproxied_uri if defined $unproxied_uri;

  my $document_callback = $self->make_document_callback($unproxied_uri || $bookmark);

  # $mod_obj is never passed in, under the current code base, but you never know :-)
  my $mod_score;
  unless ($mod_obj) {
    ($mod_obj, $mod_score) = $self->scan_for_best_citation_source_module_for_uri($uri, $document_callback);
    defined $mod_obj or return ($bookmark);
  }

  my $ref = ref $mod_obj;

  # use the selected module
  my $new_uri;
  eval {
    $new_uri = $mod_obj->filter($uri, $document_callback);
  };
  die "Error from ${ref}::filter(\'$uri\'): $@" if $@;
  if (defined $new_uri) {
    if ($new_uri eq '') {
      $bookmark->delete unless $bookmark->user_articles->count;
      my $errstr = $mod_obj->errstr || 'Sorry, you cannot add the given URI: '.$uri;
      chomp $errstr;
      if (my $log = $self->log) {
	$log->info('citation module '.$mod_obj->name.' blanked URI '.$uri.' with: '.$errstr);
      }
      die "$errstr\n";  # this one intended to be read by users so add newline to avoid die() adding location
    }
    unless ($new_uri->eq($uri)) {
      $uri = $new_uri;
      # there is a potential for Bad Things to happen because we are
      # letting modules change URI's already in the database; the
      # original URI could have already been bookmarked by someone
      # else; or it could have been preadd()'ed with no bookmarks; we
      # operate on faith that any result from a filter() method call
      # is a benign improvement on the URI
      my ($new_bookmark) = Bibliotech::Bookmark->search_url_case_sensitive($new_uri);
      if (defined $new_bookmark) {
	# if what we want to transition to is already in our database, switch to that bookmark
	$bookmark->delete unless $bookmark->user_articles->count;
	undef $bookmark;
	$bookmark = $new_bookmark;
      }
      else {
	# otherwise it hurts nothing to simply update the one we're working on
	$bookmark->url($new_uri);
	$bookmark->set_correct_hash;
	$bookmark->update;
      }
      # let the network get routine be updated too
      $document_callback = $self->make_document_callback($bookmark);
    }
  }

  my $citations;
  eval {
    $citations = $mod_obj->citations($uri, $document_callback);
  };
  die "Error from ${ref}::citations(\'$uri\'): $@" if $@;
  my $errstr = $mod_obj->errstr;
  if ($errstr) {
    die "Error from ${ref}::citations(\'$uri\'): $errstr" if $die_on_errstr;
    my $report = "Citation module error report:\n\nIn $ref for\n$uri\n\n$errstr\n\n";
    $self->notify_for_exception(subject => '['.$self->sitename_plus_server_id.' citation module error]', body => $report);
  }

  my $module_str;
  eval {
    (my $short_ref = $ref) =~ s/^Bibliotech::CitationSource:://;
    (my $version = $mod_obj->version) =~ s/^\$[Rr]evision:\s*([\d\.]+)\s*\$$/$1/;  # free of CVS trappings
    my $name = $mod_obj->name;
    $module_str = $short_ref.($version ? ' '.$version : '').($name and $name ne $short_ref ? '; '.$name : '');
  };
  die "Error from ${ref}::version or ::name: $@" if $@;

  return ($bookmark, $citations, $module_str, $mod_score);
}

sub pull_citation_calc_return_unwritten_citation_obj {
  my ($self, $bookmark, $mod_obj, $die_on_errstr, $user_supplied) = @_;
  my ($new_bookmark, $citations_model_ref, $original_module_str, $original_module_score)
      = $self->pull_citation_calc($bookmark, $mod_obj, $die_on_errstr);
  return ($new_bookmark,
	  undef) unless defined $citations_model_ref;
  return ($new_bookmark,
	  Bibliotech::Unwritten::Citation->from_citationsource_result_list($citations_model_ref,
									   $user_supplied || 0,
									   $original_module_str,
									   $original_module_score));
}

# $bookmark is an add()'d bookmark
# $citations is the result of a citations() call to a CitationSource module and has
#   non-saved citation data in it
# $module_str is a string representing a description from the module that got the data
sub pull_citation_save {
  my ($self, $bookmark, $citations, $module_str, $module_score) = @_;
  if (my $citation = Bibliotech::Unwritten::Citation->from_citationsource_result_list
      ($citations, $bookmark->isa('Bibliotech::User_Bookmark') ? 1 : 0, $module_str, $module_score)) {
    $citation->write($bookmark);
  }
  return $bookmark;
}

sub validate_user_fields_for_new_user {
  my ($self, $username, $password, $firstname, $lastname, $email, $openurl_resolver, $openurl_name) = @_;
  # ----- username
  $username
      or die "You must specify a username.\n";
  $self->parser->check_user_format($username) 
      or die "Please choose a username 3-40 characters not starting with a digit.\n";
  Bibliotech::User->search(username => $username)
      and die "Sorry, the username $username is already taken; please choose another.\n";
  # ----- email
  $email
      or die "You must specify an email address.\n";
  Bibliotech::User->search(email => $email)
      and die "Sorry, the email address $email is already registered. Perhaps you already have an account?\n";
  # ----- password
  $password
      or die "You must specify a password.\n";
  return 1;
}

sub _generate_verifycode {
  my ($username, $password, $email) = @_;
  return substr(md5_hex(encode_utf8(join('/',
					 $username,
					 $password,
					 $email,
					 $USER_VERIFYCODE_SECRET))),
		0, 16);
}

sub new_user {
  my ($self, $username, $password, $firstname, $lastname, $email, $openurl_resolver, $openurl_name,
      $redirect_email) = @_;
  my @data = ($username, $password, $firstname, $lastname, $email, $openurl_resolver, $openurl_name);
  $self->validate_user_fields_for_new_user(@data);
  my $user = $self->new_user_create_with_dup_key_error(@data);
  $self->new_user_possibly_send_email($user, $redirect_email);
  return $user;
}

sub new_user_create {
  my ($self, $username, $password, $firstname, $lastname, $email, $openurl_resolver, $openurl_name) = @_;
  Bibliotech::User->create({username         => $username,
			    password         => $password,
			    firstname        => $firstname,
			    lastname         => $lastname,
			    email            => $email,
			    openurl_resolver => $openurl_resolver || undef,
			    openurl_name     => $openurl_name     || undef,
			    verifycode       => _generate_verifycode($username, $password, $email),
			    active           => 0,
			   }) or die "cannot create user $username\n";
}

sub new_user_create_with_dup_key_error {
  my ($self, $username, $password, $firstname, $lastname, $email, $openurl_resolver, $openurl_name) = @_;
  my $user = eval {
    $self->new_user_create($username, $password, $firstname, $lastname, $email, $openurl_resolver, $openurl_name);
  };
  if (my $e = $@) {
    # These errors occur when two processes are asked to insert the
    # same user simultaneously. This can happen for example when the
    # user clicks the submit button twice quickly. The best thing to
    # do is handle them the same as a slightly slower race condition
    # that failed in validate_user_fields_for_new_user().
    if ($e =~ /\bDuplicate entry '.*' for key 2\b/) {
      die "Sorry, the username $username is already taken; please choose another.\n";
    }
    elsif ($e =~ /\bDuplicate entry '.*' for key 3\b/) {
      die "Sorry, the email address $email is already registered. Perhaps you already have an account?\n";
    }
    else {
      die $e;
    }
  }
  return $user;
}

# $redirect email should be undef normally, set to filename for
# debugging to send new user welcome email output to a file instead of
# sending a real email
sub new_user_possibly_send_email {
  my ($self, $user, $redirect_email) = @_;
  return $self->verify_user_action($user) if $SKIP_EMAIL_VERIFICATION;  # simulate user verifying themself
  return $self->new_user_send_email($user, $redirect_email ? (outfile => $redirect_email) : ());
}

sub _verify_url {
  my ($location, $user_id, $verifycode) = @_;
  return $location.'verify?userid='.$user_id.'&code='.$verifycode;
}

sub new_user_send_email {
  my ($self, $user, %options) = @_;
  $user or die 'no user object';
  my $user_id    = $user->user_id    or die 'No user_id';
  my $username   = $user->username   or die 'No username';
  my $verifycode = $user->verifycode or die "User $username currently has no verify code - perhaps already verified?\n";
  my $location   = $self->location   or die 'No location, hyperlink will not work';
  my $sitename   = $self->sitename   or die 'No site name';
  $options{file}    ||= 'register_email';
  $options{subject} ||= $sitename.' signup';
  $options{var}     ||= {url => _verify_url($location, $user_id, $verifycode)};
  $self->notify_user($user, %options);
  return $user;
}

sub load_user {
  my ($self, $user_id) = @_;
  die "You must specify a userid\n" unless $user_id;
  my $user = Bibliotech::User->retrieve($user_id) or die "cannot find user $user_id\n";
  return ((map { $_ => $user->$_; } qw/username password firstname lastname email openurl_resolver openurl_name/),
	  (openid => do { local $_ = $user->openids->first; defined $_ ? $_->openid : undef; }));
}

# pass in user_id, password, firstname, lastname, email, new username
sub update_user {
  my $self    = shift;
  my $user_id = shift or die "You must specify a userid\n";
  my $dbh     = Bibliotech::DBI::db_Main;

  $dbh->do('SET AUTOCOMMIT=0');
  eval {
    my $user = Bibliotech::User->retrieve($user_id) or die "cannot find user $user_id\n";
    foreach (qw/password firstname lastname email/) {
      last unless @_;
      my $current = $user->$_;
      my $new = shift;
      next if $new eq $current;
      if ($_ eq 'email') {
	my $email = $new;
	Bibliotech::User->search(email => $email)
	    and die "Sorry, the email address $email is already registered.\n";
      }
      $user->$_($new);
    }
    $user->update;
    if (my $new_username = shift) {
      if ($new_username ne $user->username) {
	if ($user->is_unnamed_openid) {
	  Bibliotech::User->search(username => $new_username)
	      and die "Sorry, the username $new_username is already registered.\n";
	  $user->username($new_username);
	  $user->update;
	}
	else {
	  die "Sorry, you may only rename a user if they have a temporary OpenID username.\n";
	}
      }
    }
  };
  if (my $e = $@) {
    $dbh->do('ROLLBACK');
    $dbh->do('SET AUTOCOMMIT=1');
    die $e;
  }
  $dbh->do('COMMIT');
  $dbh->do('SET AUTOCOMMIT=1');
  return 1;
}

# pass a user object and possibly some options
# options:
#   body: text of email
#   file: read text from file instead
#   outfh: output to file handle
#   outfile: output to file
#   prog: output to program, defaults to sendmail
#   to: who the email is to, defaults to user's email address
#   from: who the email is from, defaults to standard site email address
#   reply-to: who to reply to
#   subject: the email subject line
sub notify_user {
  my ($self, $user, %options) = @_;
  die 'no user specified' unless $user;

  $options{default_to}   ||= $user->email;
  $options{default_from} ||= $self->siteemail;

  if ($options{file}) {
    $options{file} =~ s|^([^/])|$self->docroot.$1|e;
  }

  $options{filter} = sub {
    my ($body_ref, $var_ref) = @_;
    return [$self->replace_text_variables($body_ref, $user, $var_ref)];
  };

  return Bibliotech::Util::notify(\%options);
}

sub notify_admin {
  my ($self, %options) = @_;
  $options{default_to}   ||= $SITE_EMAIL;
  $options{default_from} ||= $SITE_EMAIL;
  $options{file} =~ s|^([^/])|$self->docroot.$1|e if $options{file};
  $options{filter} = sub {
    my ($body_ref, $var_ref) = @_;
    return [$self->replace_text_variables($body_ref, $self->user, $var_ref)];
  };
  return Bibliotech::Util::notify(\%options);
}

sub notify_for_exception {
  my ($self, %options) = @_;
  return 0 if !$EXCEPTION_ERROR_REPORTS_TO and !$options{to};
  $options{default_to} ||= $EXCEPTION_ERROR_REPORTS_TO;
  return $self->notify_admin(%options);
}

sub replace_text_variables {
  my ($self, $body_ref, $user, $values, $values_code_obj) = @_;

  my @body = map { s|(\\?\$\{?\w+\??\}?)|$self->lookup_text_variable($1, $user, $values, $values_code_obj)|ge; $_; } @{$body_ref};
  @body = map { s|\\u(.)|\u$1|g; s|\\U(.*)\\E|\U$1\E|g; s|\\l(.)|\l$1|g; s|\\L(.*)\\E|\L$1\E|g; $_; } @body;
  return wantarray ? @body : \@body;
}

sub lookup_text_variable {
  my ($self, $symbol, $user, $values, $values_code_obj) = @_;

  my ($escape, $prefix, $name, $questionmark) = ($symbol =~ m|^(\\?)(\$)\{?(\w+)(\??)\}?$|);

  return substr($symbol, 1) if $escape;               # just a classic escape
  return $symbol            if $name eq 'component';  # just avoid those, we have nothing to do with them here

  # special variables
  if (defined $values and ref $values and defined $values->{$name}) {
    my $entry = $values->{$name};
    my $ref = ref $entry;
    return $entry unless $ref;
    return $entry->($values_code_obj) if $ref eq 'CODE';
    return join(' ', @{$entry}) if $ref eq 'ARRAY';
    return "$entry";
  }

  # system settings
  foreach ('location', 'sitename', 'siteemail', 'title', 'heading', 'link', 'description',
	   'path', 'canonical_path', 'canonical_path_for_cache_key', 'docroot', 'error') {
    return $self->$name if $_ eq $name;
  }

  # bookmarklets
  if ($name =~ /^bookmarklet(s|(_javascript)?_([a-z]+)_([a-z]+))$/) {
    return Bibliotech::Bookmarklets::bookmarklets
	($self->sitename, $self->location, $self->cgi) if $1 eq 's';
    return Bibliotech::Bookmarklets::bookmarklet_javascript
	($self->sitename, $self->location, $self->cgi, $3, $4) if $2 eq '_javascript';
    return Bibliotech::Bookmarklets::bookmarklet
	($self->sitename, $self->location, $self->cgi, $3, $4);
  }

  # properties of the current user
  if (Bibliotech::User->find_column($name) or $name eq 'name') {
    $user = Bibliotech::User->retrieve($user) if $user and !UNIVERSAL::isa($user, 'Bibliotech::User');
    return $user->$name if defined $user;
  }

  # failed
  return $questionmark ? '' : $symbol;
}

sub verify_user_action {
  my ($self, $user) = @_;
  $user->verifycode(undef);
  $user->active(1);
  $user->update;
  return $user;
}

sub verify_user {
  my ($self, $user_id, $code) = @_;
  my $user = Bibliotech::User->retrieve($user_id) or die 'bad user_id';
  if (my $stored_code = $user->verifycode) {
    die "Sorry, you have provided an incorrect verification code.\n" unless $code eq $stored_code;
    $self->verify_user_action($user);
  }
  return $user;
}

sub validate_user_can_login {
  my $user = pop;
  defined $user or die 'no user provided to validate_user_can_login';
  $user->verifycode and die "A verification email has been sent to you. When you receive it, please click the verification hyperlink to activate your account.\n";
  $user->active or die "Sorry, this account has been deactivated.\n";  # generic
}

sub allow_login {
  my ($self, $username, $password) = @_;
  my $user_check = Bibliotech::User->search(username => $username);
  my $user = $user_check->first or die "Unknown username.\n";
  $user->password eq $password or die "Incorrect password.\n";
  $self->validate_user_can_login($user);
  return $user;
}

sub allow_login_openid {
  my ($self, $openid, $get_sreg_details_sub) = @_;
  my $user = Bibliotech::User->by_openid($openid) ||
             do { my ($username, $firstname, $lastname, $email) = $get_sreg_details_sub->();
		  Bibliotech::User->create_for_openid($openid, $username, $firstname, $lastname, $email); };
  defined $user or die 'no user from create_for_openid';
  $self->validate_user_can_login($user);
  return $user;
}

sub allow_first_login {
  my ($self, $user_id) = @_;
  my $user = Bibliotech::User->retrieve($user_id) or die "Unknown user_id.\n";
  $self->validate_user_can_login($user);
  return $user;
}

sub retag {
  my ($self, $user_or_user_id, $old_tag_or_tags_ref, $new_tag_or_tags_ref) = @_;

  my $get_user_obj = sub { my $user = shift;
			   return unless defined $user;
			   return $user if UNIVERSAL::isa($user, 'Bibliotech::User');
			   return Bibliotech::User->retrieve($user) or die "user not found: $user\n";
                         };
  my $get_tags_obj_or_name = sub { my $tags = shift;
				   return () unless defined $tags;
				   return ($tags) if UNIVERSAL::isa($tags, 'Bibliotech::Tag');
				   return @{$tags} if ref $tags;
				   return ($tags);
		                 };
  my $parser = $self->parser;

  my $user = $get_user_obj->($user_or_user_id);
  my @tag1 = map { Bibliotech::Tag->new($_) or die "The tag $_ is not recognized.\n";
                 } $get_tags_obj_or_name->($old_tag_or_tags_ref) or die "Please specify an old tag.\n";
  my @tag2 = map { ref $_ or $parser->check_tag_format($_) or die "Invalid tag name: $_\n";
		   Bibliotech::Tag->new($_, 1) or die "The tag $_ is invalid.\n";
		 } $get_tags_obj_or_name->($new_tag_or_tags_ref);

  return $self->retag_normalized($user, \@tag1, \@tag2);
}

sub retag_normalized {
  my ($self, $user, $old_tags_ref, $new_tags_ref) = @_;

  $user->mark_updated;  # in case we die mid-loop below

  if (@{$old_tags_ref} == 1 and @{$new_tags_ref} == 1) {
    Bibliotech::User_Tag_Annotation->change_tag($user, $old_tags_ref->[0], $new_tags_ref->[0]);
  }

  my $count = 0;
  foreach my $tag1 (@{$old_tags_ref}) {
    my $iter = Bibliotech::User_Article_Tag->search_user_tag($user, $tag1);
    while (my $user_article_tag = $iter->next) {
      my $user_article = $user_article_tag->user_article;
      $user_article_tag->delete;
      if (@{$new_tags_ref}) {
	foreach my $tag2 (@{$new_tags_ref}) {
	  Bibliotech::User_Article_Tag->find_or_create({user_article => $user_article, tag => $tag2});
	}
      }
      else {
	if ($user_article->tags->count == 0) {
	  my $dtag = Bibliotech::Tag->new('default', 1);
	  Bibliotech::User_Article_Tag->find_or_create({user_article => $user_article, tag => $dtag});
	}
      }
      $user_article->mark_updated;  # cause user_article html_content() to notice, for caching
      $count++;
    }
    Bibliotech::User_Tag_Annotation->search(user => $user, tag => $tag1)->delete_all;
    $tag1->delete unless $tag1->count_user_articles or $tag1->user_tag_annotations->count;
  }

  $user->last_deletion_now;
  $user->mark_updated;

  return $count;
}

sub last_modified_no_cache {
  my ($self) = @_;
  $self->no_cache(1);
  return 1;
}

sub changegroup {
  my ($self, %options) = @_;

  my $action = $options{action};
  my ($add, $edit) = (0, 0);
  if (!$action or $action eq 'add') {
    $add = 1;
  }
  elsif ($action eq 'edit') {
    $edit = 1;
  }

  my $user = Bibliotech::User->normalize_option(\%options);
  my $owner = $user;

  my $name = $options{name};
  $self->parser->check_gang_format($name) or die "Invalid group name.\n";
  if ($add) {
    Bibliotech::Gang->search(name => $name)
	and die "Sorry, the group name $name is already taken; please choose another.\n";
  }
  
  my $description = $options{description};

  my $private = $options{private} ? 1 : 0;

  my @members = @{$options{members}||[]};
  if ($add) {
    die "You must specify at least one member.\n" unless @members;
  }
  if ($edit) {
    if (@members == 0) {
      if (my $gang = Bibliotech::Gang->new($name)) {
	$gang->delete;
	undef $gang;
	$owner->last_deletion_now;
	$owner->mark_updated;
      }
      return undef;
    }
  }

  if (my @noexist = grep { !defined(Bibliotech::User->new($_)) } @members) {
    my $msg = Bibliotech::Command->description_filter(\@noexist,
						      [undef,
						       ['User ', 1, ' does not exist.'],
						       ['Users ', 1, ' do not exist.']]);
    $msg =~ s| or | and |;
    die "$msg\n";
  }

  my $gang = Bibliotech::Gang->new($name, 1);
  $gang->owner($owner);
  $gang->description($description);
  $gang->private($private);
  $gang->update;
  $gang->update_links_one_to_many('Bibliotech::User' => \@members);

  return $gang;
}

sub addgroup {
  my ($self, %options) = @_;
  $options{action} = 'add';
  return $self->changegroup(%options);
}

sub editgroup {
  my ($self, %options) = @_;
  $options{action} = 'edit';
  return $self->changegroup(%options);
}

sub changeuta {
  my ($self, %options) = @_;

  my $action = $options{action};
  my ($add, $edit) = (0, 0);
  if (!$action or $action eq 'add') {
    $add = 1;
  }
  elsif ($action eq 'edit') {
    $edit = 1;
  }

  my $user = Bibliotech::User->normalize_option(\%options);
  my $tag = Bibliotech::Tag->normalize_option(\%options);
  my $tagname = $tag->name;
  $user->count_use_of_tag($tag) >= 1 or die "You are not currently using this tag; please check that you have entered it correctly.\n";
  my ($user_tag_annotation) = Bibliotech::User_Tag_Annotation->search(user => $user, tag => $tag);

  my $entry = Bibliotech::Util::sanitize($options{entry});

  if ($add) {
    if (!$entry) {
      die "You already have a note for this tag; please edit the existing note or create a new one.\n" if defined $user_tag_annotation;
      die "Please enter some text to associate with this tag.\n";
    }
    die "You already have a note for this tag; please edit the existing note or confirm the new one.\n" if defined $user_tag_annotation;
    my $comment = Bibliotech::Comment->create({entry => $entry});
    $user_tag_annotation = Bibliotech::User_Tag_Annotation->create({user => $user, tag => $tag, comment => $comment});
  }
  else {
    my $comment = $user_tag_annotation->comment;
    if ($entry) {
      $comment->entry($entry);
      $comment->mark_updated;
    }
    else {
      $user_tag_annotation->delete;  # also deletes comment
      undef $user_tag_annotation;
      $user->last_deletion_now;
      $user->update;
    }
  }

  return $user_tag_annotation;
}

sub adduta {
  my ($self, %options) = @_;
  $options{action} = 'add';
  return $self->changeuta(%options);
}

sub edituta {
  my ($self, %options) = @_;
  $options{action} = 'edit';
  return $self->changeuta(%options);
}

sub in_my_library {
  my $self = shift;
  if (my $user = $self->user) {
    my $username = $user->username;
    if (my $user_filter = $self->command->user) {
      if (grep($username eq $_, @{$user_filter})) {
	return 1;
      }
    }
  }
  return 0;
}

sub in_another_library {
  my $self = shift;
  if (my $user = $self->user) {
    my $username = $user->username;
    if (my $user_filter = $self->command->user) {
      if (@{$user_filter} and !grep($username eq $_, @{$user_filter})) {
	return 1;
      }
    }
  }
  return 0;
}

1;
__END__
