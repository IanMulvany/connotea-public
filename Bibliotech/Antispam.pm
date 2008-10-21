# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Antispam class provides routines to help catch
# incoming spam.

package Bibliotech::Antispam;
use strict;
use List::Util qw/sum/;
use List::MoreUtils qw/any all/;
use Text::CSV;
use Fcntl qw/:flock :seek/;
use Encode qw/is_utf8 encode_utf8/;
use Digest::MD5 qw/md5_hex/;
use Data::Dumper;
use Bibliotech::Config;
use Bibliotech::DBI;

our $URI_BAD_PHRASE_LIST      	  = Bibliotech::Config->get('ANTISPAM', 'URI_BAD_PHRASE_LIST')          || 
                                    Bibliotech::Config->get('ANTISPAM', 'BAD_PHRASE_LIST')              || [];
our $URI_BAD_PHRASE_SCORE     	  = Bibliotech::Config->get('ANTISPAM', 'URI_BAD_PHRASE_SCORE');
    $URI_BAD_PHRASE_SCORE         = 1 unless defined $URI_BAD_PHRASE_SCORE;
our $USERNAME_ENDS_IN_DIGIT_SCORE = Bibliotech::Config->get('ANTISPAM', 'USERNAME_ENDS_IN_DIGIT_SCORE');
    $USERNAME_ENDS_IN_DIGIT_SCORE = 1 unless defined $USERNAME_ENDS_IN_DIGIT_SCORE;
our $USERNAME_DIGIT_MIDDLE_SCORE  = Bibliotech::Config->get('ANTISPAM', 'USERNAME_DIGIT_MIDDLE_SCORE');
    $USERNAME_DIGIT_MIDDLE_SCORE  = 1 unless $USERNAME_DIGIT_MIDDLE_SCORE;
our $TAG_BAD_PHRASE_LIST          = Bibliotech::Config->get('ANTISPAM', 'TAG_BAD_PHRASE_LIST')          ||
                                    Bibliotech::Config->get('ANTISPAM', 'BAD_PHRASE_LIST')              || [];
our $TAG_BAD_PHRASE_SCORE         = Bibliotech::Config->get('ANTISPAM', 'TAG_BAD_PHRASE_SCORE');
    $TAG_BAD_PHRASE_SCORE         = 1 unless defined $TAG_BAD_PHRASE_SCORE;
our $TAG_REALLY_BAD_PHRASE_LIST   = Bibliotech::Config->get('ANTISPAM', 'TAG_REALLY_BAD_PHRASE_LIST')   || [];
our $TAG_REALLY_BAD_PHRASE_SCORE  = Bibliotech::Config->get('ANTISPAM', 'TAG_REALLY_BAD_PHRASE_SCORE');
    $TAG_REALLY_BAD_PHRASE_SCORE  = 3 unless defined $TAG_REALLY_BAD_PHRASE_SCORE;
our $WIKI_BAD_PHRASE_LIST         = Bibliotech::Config->get('ANTISPAM', 'WIKI_BAD_PHRASE_LIST')         ||
                                    Bibliotech::Config->get('ANTISPAM', 'BAD_PHRASE_LIST')              || [];
our $TAGS_TOO_MANY_MAX            = Bibliotech::Config->get('ANTISPAM', 'TAGS_TOO_MANY_MAX');
    $TAGS_TOO_MANY_MAX            = 7 unless defined $TAGS_TOO_MANY_MAX;
our $TAGS_TOO_MANY_SCORE          = Bibliotech::Config->get('ANTISPAM', 'TAGS_TOO_MANY_SCORE');
    $TAGS_TOO_MANY_SCORE          = 1 unless defined $TAGS_TOO_MANY_SCORE;
our $EMAIL_GENERIC_SERVICE_LIST   = Bibliotech::Config->get('ANTISPAM', 'EMAIL_GENERIC_SERVICE_LIST')   || [];
our $EMAIL_GENERIC_SERVICE_SCORE  = Bibliotech::Config->get('ANTISPAM', 'EMAIL_GENERIC_SERVICE_SCORE');
    $EMAIL_GENERIC_SERVICE_SCORE  = 1 unless defined $EMAIL_GENERIC_SERVICE_SCORE;
our $TAGS_TWO_ALLITERATIVE_SCORE  = Bibliotech::Config->get('ANTISPAM', 'TAGS_TWO_ALLITERATIVE_SCORE');
    $TAGS_TWO_ALLITERATIVE_SCORE  = 1 unless defined $TAGS_TWO_ALLITERATIVE_SCORE;
our $LIBRARY_EMPTY_SCORE          = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_EMPTY_SCORE');
    $LIBRARY_EMPTY_SCORE          = 1 unless defined $LIBRARY_EMPTY_SCORE;
our $LIBRARY_TAGS_TOO_MANY_MAX    = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_TAGS_TOO_MANY_MAX');
    $LIBRARY_TAGS_TOO_MANY_MAX    = 50 unless defined $LIBRARY_TAGS_TOO_MANY_MAX;
our $LIBRARY_TAGS_TOO_MANY_SCORE  = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_TAGS_TOO_MANY_SCORE');
    $LIBRARY_TAGS_TOO_MANY_SCORE  = 1 unless defined $LIBRARY_TAGS_TOO_MANY_SCORE;
our $LIBRARY_RECENT_ACTIVE_MAX    = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_RECENTLY_ACTIVE_MAX');
    $LIBRARY_RECENT_ACTIVE_MAX    = 5 unless defined $LIBRARY_RECENT_ACTIVE_MAX;
our $LIBRARY_RECENT_ACTIVE_WINDOW = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_RECENTLY_ACTIVE_WINDOW');
    $LIBRARY_RECENT_ACTIVE_WINDOW = '24 HOUR' unless defined $LIBRARY_RECENT_ACTIVE_WINDOW;
our $LIBRARY_RECENT_ACTIVE_SCORE  = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_RECENTLY_ACTIVE_SCORE');
    $LIBRARY_RECENT_ACTIVE_SCORE  = 1 unless defined $LIBRARY_RECENT_ACTIVE_SCORE;
our $LIBRARY_HAS_HOST_MAX         = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_HAS_HOST_MAX');
    $LIBRARY_HAS_HOST_MAX         = 3 unless defined $LIBRARY_HAS_HOST_MAX;
our $LIBRARY_HAS_HOST_WHITE_LIST  = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_HAS_HOST_WHITE_LIST')  || [];
our $LIBRARY_HAS_HOST_SCORE       = Bibliotech::Config->get('ANTISPAM', 'LIBRARY_HAS_HOST_SCORE');
    $LIBRARY_HAS_HOST_SCORE       = 1 unless defined $LIBRARY_HAS_HOST_SCORE;
our $DESCRIPTION_BAD_PHRASE_LIST  = Bibliotech::Config->get('ANTISPAM', 'DESCRIPTION_BAD_PHRASE_LIST')  ||
                                    Bibliotech::Config->get('ANTISPAM', 'BAD_PHRASE_LIST')              || [];
our $DESCRIPTION_BAD_PHRASE_SCORE = Bibliotech::Config->get('ANTISPAM', 'DESCRIPTION_BAD_PHRASE_SCORE');
    $DESCRIPTION_BAD_PHRASE_SCORE = 1 unless defined $DESCRIPTION_BAD_PHRASE_SCORE;
our $COMMENT_TAGS_SCORE           = Bibliotech::Config->get('ANTISPAM', 'COMMENT_TAGS_SCORE');
    $COMMENT_TAGS_SCORE           = 1 unless defined $COMMENT_TAGS_SCORE;
our $URI_BAD_TLD_LIST             = Bibliotech::Config->get('ANTISPAM', 'URI_BAD_TLD_LIST')             || [];
our $URI_BAD_TLD_SCORE            = Bibliotech::Config->get('ANTISPAM', 'URI_BAD_TLD_SCORE');
    $URI_BAD_TLD_SCORE            = 1 unless defined $URI_BAD_TLD_SCORE;
our $TITLE_BAD_PHRASE_LIST        = Bibliotech::Config->get('ANTISPAM', 'TITLE_BAD_PHRASE_LIST')        ||
                                    Bibliotech::Config->get('ANTISPAM', 'BAD_PHRASE_LIST')              || [];
our $TITLE_BAD_PHRASE_SCORE       = Bibliotech::Config->get('ANTISPAM', 'TITLE_BAD_PHRASE_SCORE');
    $TITLE_BAD_PHRASE_SCORE       = 1 unless defined $TITLE_BAD_PHRASE_SCORE;
our $URI_BAD_HOST_LIST            = Bibliotech::Config->get('ANTISPAM', 'URI_BAD_HOST_LIST')            || [];
our $URI_BAD_HOST_SCORE           = Bibliotech::Config->get('ANTISPAM', 'URI_BAD_HOST_SCORE');
    $URI_BAD_HOST_SCORE           = 1 unless defined $URI_BAD_HOST_SCORE;
our $TAG_POPULAR_SCORE            = Bibliotech::Config->get('ANTISPAM', 'TAG_POPULAR_SCORE');
    $TAG_POPULAR_SCORE            = 1 unless defined $TAG_POPULAR_SCORE;
our $STRANGE_TAG_COMBO_LIST       = Bibliotech::Config->get('ANTISPAM', 'STRANGE_TAG_COMBO_LIST')       || [];
our $STRANGE_TAG_COMBO_SCORE      = Bibliotech::Config->get('ANTISPAM', 'STRANGE_TAG_COMBO_SCORE');
    $STRANGE_TAG_COMBO_SCORE      = 1 unless defined $STRANGE_TAG_COMBO_SCORE;
our $DESCRIPTION_HAS_TITLE_SCORE  = Bibliotech::Config->get('ANTISPAM', 'DESCRIPTION_HAS_TITLE_SCORE');
    $DESCRIPTION_HAS_TITLE_SCORE  = 1 unless defined $DESCRIPTION_HAS_TITLE_SCORE;
our $TOO_MANY_COMMAS_MAX          = Bibliotech::Config->get('ANTISPAM', 'TOO_MANY_COMMAS_MAX');
    $TOO_MANY_COMMAS_MAX          = 3 unless defined $TOO_MANY_COMMAS_MAX;
our $TOO_MANY_COMMAS_SCORE        = Bibliotech::Config->get('ANTISPAM', 'TOO_MANY_COMMAS_SCORE');
    $TOO_MANY_COMMAS_SCORE        = 1 unless defined $TOO_MANY_COMMAS_SCORE;
our $REPEATED_WORDS_SCORE         = Bibliotech::Config->get('ANTISPAM', 'REPEATED_WORDS_SCORE');
    $REPEATED_WORDS_SCORE         = 1 unless defined $REPEATED_WORDS_SCORE;
our $REPEATED_WORDS_URI_BONUS     = Bibliotech::Config->get('ANTISPAM', 'REPEATED_WORDS_URI_BONUS');
    $REPEATED_WORDS_URI_BONUS     = 1 unless defined $REPEATED_WORDS_URI_BONUS;
our $PREFILLED_ADD_FORM_SCORE     = Bibliotech::Config->get('ANTISPAM', 'PREFILLED_ADD_FORM_SCORE');
    $PREFILLED_ADD_FORM_SCORE     = 1 unless defined $PREFILLED_ADD_FORM_SCORE;
our $AUTHORITATIVE_CITATION_SCORE = Bibliotech::Config->get('ANTISPAM', 'AUTHORITATIVE_CITATION_SCORE');
    $AUTHORITATIVE_CITATION_SCORE = -1 unless defined $AUTHORITATIVE_CITATION_SCORE;
our $USERNAME_CONSONANTS_SCORE    = Bibliotech::Config->get('ANTISPAM', 'USERNAME_CONSONANTS_SCORE');
    $USERNAME_CONSONANTS_SCORE    = 1 unless defined $USERNAME_CONSONANTS_SCORE;
our $TITLE_SITEMAP_SCORE    	  = Bibliotech::Config->get('ANTISPAM', 'TITLE_SITEMAP_SCORE');
    $TITLE_SITEMAP_SCORE    	  = 2 unless defined $TITLE_SITEMAP_SCORE;
our $I_AM_SPAM_SCORE              = Bibliotech::Config->get('ANTISPAM', 'I_AM_SPAM_SCORE');
    $I_AM_SPAM_SCORE              = 10 unless defined $I_AM_SPAM_SCORE;
our $SCORE_MAX                    = Bibliotech::Config->get('ANTISPAM', 'SCORE_MAX');
    $SCORE_MAX                    = 4 unless defined $SCORE_MAX;
our $SCORE_SUPER_MAX              = Bibliotech::Config->get('ANTISPAM', 'SCORE_SUPER_MAX');
    $SCORE_SUPER_MAX              = 10 unless defined $SCORE_SUPER_MAX;
our $TRUSTED_USER_LIST            = Bibliotech::Config->get('ANTISPAM', 'TRUSTED_USER_LIST') || [];

sub is_not_spam_or_die_with_special {
  my ($is_spam, $check_captcha, $over_max, $over_super_max, $scorelist) = check(@_);
  return unless $is_spam;
  die "SPAM (super)\n" if $over_super_max;
  die "SPAM (known host)\n" if $over_max && defined $scorelist && $scorelist->get('uri_bad_host');
  die "SPAM\n";
}

sub is_spam {
  check(@_);
}

sub is_not_spam {
  !check(@_);
}

sub check {
  my ($user, $bookmark, $tags_ref, $description, $title, $comment, $has_citation, $citation_understands_score, $prefilled, $popular_tags_ref, $captcha, $is_karma_bad, $scorelog, $captchalog) = @_;
  my $username = $user->username;
  return wantarray ? (0) : 0 if grep {$username eq $_} @{$TRUSTED_USER_LIST};
  my @basics = (unique_id($username, $bookmark->uri, $tags_ref, $description, $title, $comment),
		$user, $bookmark, $tags_ref, $description, $title, $comment,
		$has_citation, $citation_understands_score, $prefilled,
		$popular_tags_ref);
  return check_captcha(@basics, $captcha, $is_karma_bad, $captchalog) if $captcha or $is_karma_bad;
  return check_raw    (@basics, $scorelog);
}

sub check_raw {
  my ($id, $user, $bookmark, $tags_ref, $description, $title, $comment, $has_citation, $citation_understands_score, $prefilled, $popular_tags_ref, $logfilename) = @_;
  my $scorelist = score($user, $bookmark, $tags_ref, $description, $title, $comment, $has_citation, $citation_understands_score, $prefilled, $popular_tags_ref);
  write_score_log($logfilename, $id, $user->username, $bookmark->url, $tags_ref, $description, $title, $comment, $scorelist);
  my $score = $scorelist->total;
  my $check = $score > $SCORE_MAX;
  return $check unless wantarray;
  my $super = $score > $SCORE_SUPER_MAX;
  my $check_captcha = 0;
  return ($check, $check_captcha, $check, $super, $scorelist);
}

sub check_captcha {
  my ($id, $user, $bookmark, $tags_ref, $description, $title, $comment, $has_citation, $citation_understands_score, $prefilled, $popular_tags_ref, $captcha, $is_karma_bad, $logfilename) = @_;
  write_captcha_log($logfilename, $id, $captcha) if $captcha;
  my $check = $captcha != 1;
  return $check unless wantarray;
  my $scorelist = score($user, $bookmark, $tags_ref, $description, $title, $comment, $has_citation, $citation_understands_score, $prefilled, $popular_tags_ref);
  my $score = $scorelist->total;
  my $check_score = $score > $SCORE_MAX;
  my $super = $score > $SCORE_SUPER_MAX;
  return ($check, $check, $check_score, $super, $scorelist);
}

sub score_log_entry {
  my ($id, $username, $uri, $tags_ref, $description, $title, $comment, $scorelist) = @_;
  return log_entry_macro([ID          => $id],
			 [User        => $username],
			 [URI         => "$uri"],
			 [Tags        => join(', ', @{$tags_ref})],
			 [Description => $description],
			 [Title       => $title],
			 [Comment     => $comment],
			 $scorelist->records,
			 [Total       => $scorelist->total],
			 );
}

sub captcha_log_entry {
  my ($id, $captcha) = @_;
  return log_entry_macro([ID          => $id],
			 [Pass        => ($captcha ==  1 ? 1 : 0)],
			 [Fail        => ($captcha == -1 ? 1 : 0)],
			 );
}

sub log_entry_macro {
  my $csv = Text::CSV->new;
  my $combine_with_error_check = sub {
    my $csv = shift;
    $csv->combine(map { s/[^[:ascii:]]/_/g; s/[\r\n]/_/g; $_; } @_) and return $csv->string."\n";
    return 'err: '.$csv->error_input.' ... '.join(',', map { s/[\r\n]/_/g; $_; } @_)."\n";
  };
  return wantarray ? (do { $combine_with_error_check->($csv, map { $_->[0] } @_); },
		      do { $combine_with_error_check->($csv, map { $_->[1] } @_); })
                   :  do { $combine_with_error_check->($csv, map { $_->[1] } @_); },
}

sub write_score_log {
  my ($filename, $id, $username, $uri, $tags_ref, $description, $title, $comment, $scorelist) = @_;
  write_log_macro($filename, score_log_entry($id, $username, $uri, $tags_ref, $description, $title, $comment, $scorelist));
}

sub write_captcha_log {
  my ($filename, $id, $captcha) = @_;
  write_log_macro($filename, captcha_log_entry($id, $captcha));
}

sub write_log_macro {
  my ($filename, @log) = @_;
  return unless $filename;
  my $existed = -s $filename;
  shift @log if $existed;
  append($filename, \@log);
}

sub append {
  my ($filename, $lines_ref) = @_;
  open  LOG, '>>'.$filename or die "cannot open $filename: $!";
  flock LOG, LOCK_EX;
  seek  LOG, 0, SEEK_END;
  print LOG @{$lines_ref};
  flock LOG, LOCK_UN;
  close LOG;
}

sub score {
  my ($user, $bookmark, $tags_ref, $description, $title, $comment, $has_citation, $citation_understands_score, $prefilled, $popular_tags_ref) = @_;
  my $uri      = $bookmark->url;
  my $username = $user->username;
  my $email    = $user->email;
  my $scorelist = Bibliotech::Antispam::ScoreList->new
      ([[uri_bad_phrase             => uri_bad_phrase($uri)],
	[uri_bad_host               => uri_bad_host($uri)],
	[uri_bad_tld                => uri_bad_tld($uri)],
	[username_ends_in_digit     => username_ends_in_digit($username)],
	[username_digit_middle      => username_digit_middle($username)],
	[username_consonants        => username_consonants($username)],
	[email_generic_service      => email_generic_service($email)],
	[library_empty              => library_empty($user)],
	[library_tags_too_many      => library_tags_too_many($user)],
	[library_recent_active      => library_recent_active($user)],
	[library_has_host           => library_has_host($user, $uri, $has_citation, $citation_understands_score)],
	[tag_bad_phrase_list        => tag_bad_phrase_list($tags_ref)],
	[tag_really_bad_phrase_list => tag_really_bad_phrase_list($tags_ref)],
	[tags_too_many              => tags_too_many($tags_ref)],
	[tags_two_alliterative      => tags_two_alliterative($tags_ref)],
	[tag_popular                => tag_popular($tags_ref, $popular_tags_ref)],
	[strange_tag_combo          => strange_tag_combo($tags_ref)],
	[title_bad_phrase           => title_bad_phrase($title)],
	[title_sitemap              => title_sitemap($title)],
	[description_bad_phrase     => description_bad_phrase($description)],
	[description_has_title      => description_has_title($description, $title)],
	[comment_tags               => comment_tags($comment, $tags_ref)],
	[repeated_words             => repeated_words($uri, $title, $description, $tags_ref)],
	[too_many_commas            => too_many_commas($description, $comment)],
	[prefilled_add_form         => prefilled_add_form($prefilled)],
	[authoritative_citation     => authoritative_citation($has_citation, $citation_understands_score)],
	[i_am_spam                  => i_am_spam($uri, $tags_ref)],
	]);
  return $scorelist;
}

sub unique_id {
  # Digest::MD5 is giving an error for wide characters so encode to bytes
  my $joined = join(':', map { ref $_ eq 'ARRAY' ? join('/', @{$_}) : "$_" } @_);
  return md5_hex(is_utf8($joined) ? encode_utf8($joined) : $joined);
}

# wrap all the calls above in score to get a profiling
sub profile {
  my ($name, $action_sub) = @_;
  Bibliotech::Profile::start('antispam '.$name);
  my $score = $action_sub->();
  Bibliotech::Profile::stop();
  return $score;
}

sub _uri_bad_phrase {
  my ($uri_obj, $phrase_list, $score) = @_;
  return 0 if !$score;
  my $uri = "$uri_obj";
  #$uri =~ s/\W//g;
  return (any { $uri =~ /\b$_/i } @{$phrase_list}) ? $score : 0;
}

sub uri_bad_phrase {
  my $uri = shift;
  return _uri_bad_phrase($uri, $URI_BAD_PHRASE_LIST, $URI_BAD_PHRASE_SCORE);
}

sub _username_ends_in_digit {
  my ($username, $score) = @_;
  return 0 if !$score;
  return ($username =~ /\d$/) ? $score : 0;
}

sub username_ends_in_digit {
  my $username = shift;
  return _username_ends_in_digit($username, $USERNAME_ENDS_IN_DIGIT_SCORE);
}

sub _username_digit_middle {
  my ($username, $score) = @_;
  return 0 if !$score;
  return $username =~ /\D\d+\D/ ? $score : 0;
}

sub username_digit_middle {
  my $username = shift;
  return _username_digit_middle($username, $USERNAME_DIGIT_MIDDLE_SCORE);
}

sub _tag_bad_phrase_list {
  my ($tags_ref, $phrase_list, $score) = @_;
  return 0 if !$score;
  foreach my $tag (@{$tags_ref}) {
    $tag =~ s/[-_]/ /g;
    return $score if any { $tag =~ /^\Q$_\E$/i } @{$phrase_list};
  }
  return 0;
}

sub tag_bad_phrase_list {
  my $tags_ref = shift;
  return _tag_bad_phrase_list([map { "$_" } @{$tags_ref || []}], $TAG_BAD_PHRASE_LIST, $TAG_BAD_PHRASE_SCORE);
}

sub tag_really_bad_phrase_list {
  my $tags_ref = shift;
  # use same inner routine:
  return _tag_bad_phrase_list([map { "$_" } @{$tags_ref || []}], $TAG_REALLY_BAD_PHRASE_LIST, $TAG_REALLY_BAD_PHRASE_SCORE);
}

sub _tags_too_many {
  my ($tags_ref, $max, $score) = @_;
  return 0 if !$score;
  return (@{$tags_ref} > $max) ? $score : 0;
}

sub tags_too_many {
  my $tags_ref = shift;
  return _tags_too_many($tags_ref || [], $TAGS_TOO_MANY_MAX, $TAGS_TOO_MANY_SCORE);
}

sub _email_generic_service {
  my ($email, $domain_list, $score) = @_;
  return 0 if !$score;
  return (any { $email =~ /\Q$_\E$/ } @{$domain_list}) ? $score : 0;
}

sub email_generic_service {
  my $email = shift;
  return _email_generic_service($email, $EMAIL_GENERIC_SERVICE_LIST, $EMAIL_GENERIC_SERVICE_SCORE);
}

sub _alliterative {
  return   if @_ == 0;
  return 1 if @_ == 1;
  my $char = substr(shift, 0, 1);
  return all { substr($_, 0, 1) eq $char } @_;
}

sub _tags_two_alliterative {
  my ($tags_ref, $score) = @_;
  return 0 if !$score;
  return 0 if @{$tags_ref} != 2;
  return _alliterative(@{$tags_ref}) ? $score : 0;
}

sub tags_two_alliterative {
  my $tags_ref = shift;
  return _tags_two_alliterative($tags_ref || [], $TAGS_TWO_ALLITERATIVE_SCORE);
}

sub _library_empty {
  my ($is_empty, $score) = @_;
  return 0 if !$score;
  return $is_empty ? $score : 0;
}

sub library_empty {
  my $user = shift;
  return _library_empty($user->is_library_empty, $LIBRARY_EMPTY_SCORE);
}

sub _library_tags_too_many {
  my ($tag_count, $max, $score) = @_;
  return 0 if !$score;
  return $tag_count > $max ? $score : 0;
}

sub library_tags_too_many {
  my $user = shift;
  return _library_tags_too_many($user->count_tags_no_privacy, $LIBRARY_TAGS_TOO_MANY_MAX, $LIBRARY_TAGS_TOO_MANY_SCORE);
}

sub _library_recent_active {
  my ($post_count, $max, $score);
  return 0 if !$score;
  return $post_count > $max ? $score : 0;
}

sub library_recent_active {
  my $user = shift;
  return _library_recent_active($user->count_recent_posts_no_privacy($LIBRARY_RECENT_ACTIVE_WINDOW),
				$LIBRARY_RECENT_ACTIVE_MAX, $LIBRARY_RECENT_ACTIVE_SCORE);
}

sub _library_has_host {
  my ($host_post_count, $host, $has_citation, $citation_understands_score, $white_list, $max, $score) = @_;
  return 0 if !$score;
  return 0 if $has_citation and defined $citation_understands_score and $citation_understands_score == 1;
  return 0 if any { $host =~ /$_/ } @{$white_list};
  return $host_post_count > $max ? $score : 0;
}

sub library_has_host {
  my ($user, $uri, $has_citation, $citation_understands_score) = @_;
  return 0 unless UNIVERSAL::can($uri, 'host');
  return _library_has_host(do { my $host = $uri->host;
				($user->count_host_posts_no_privacy($host), $host); },
			   $has_citation, $citation_understands_score,
			   $LIBRARY_HAS_HOST_WHITE_LIST, $LIBRARY_HAS_HOST_MAX, $LIBRARY_HAS_HOST_SCORE);
}

sub _description_bad_phrase {
  my ($description, $phrase_list, $score) = @_;
  return 0 if !$score;
  #$description =~ s/\W//g;
  return (any { $description =~ /\b$_/ } @{$phrase_list}) ? $score : 0;
}

sub description_bad_phrase {
  my $description = shift;
  return _description_bad_phrase($description, $DESCRIPTION_BAD_PHRASE_LIST, $DESCRIPTION_BAD_PHRASE_SCORE);
}

sub _comment_tags {
  my ($comment, $tags_ref, $score) = @_;
  return 0 if !$score;
  return (all { $comment =~ /\Q$_\E/ } @{$tags_ref}) ? $score : 0;
}

sub comment_tags {
  my ($comment, $tags_ref) = @_;
  return _comment_tags($comment, $tags_ref, $COMMENT_TAGS_SCORE);
}

sub _uri_bad_tld {
  my ($uri, $tlds_ref, $score) = @_;
  die 'need a URI object' unless UNIVERSAL::isa($uri, 'URI');
  return 0 if !$score;
  return 0 unless $uri->can('host');
  my $host = $uri->host;
  return (any { $host =~ /\.\Q$_\E$/i } @{$tlds_ref}) ? $score : 0;
}

sub uri_bad_tld {
  my $uri = shift;
  return _uri_bad_tld($uri, $URI_BAD_TLD_LIST, $URI_BAD_TLD_SCORE);
}

sub _title_bad_phrase {
  my ($title, $phrase_list, $score) = @_;
  return 0 if !$score;
  return (any { $title =~ /$_/ } @{$phrase_list}) ? $score : 0;
}

sub title_bad_phrase {
  my $title = shift;
  return _title_bad_phrase($title, $TITLE_BAD_PHRASE_LIST, $TITLE_BAD_PHRASE_SCORE);
}

sub _uri_bad_host {
  my ($uri, $hosts_ref, $score) = @_;
  die 'need a URI object' unless UNIVERSAL::isa($uri, 'URI');
  return 0 if !$score;
  return 0 unless $uri->can('host');
  my $host = $uri->host;
  return (any { $host eq $_ } @{$hosts_ref}) ? $score : 0;
}

sub uri_bad_host {
  my $uri = shift;
  return _uri_bad_host($uri, $URI_BAD_HOST_LIST, $URI_BAD_HOST_SCORE);
}

sub _tag_popular {
  my ($tags_ref, $popular_tags_ref, $score) = @_;
  return 0 if !$score;
  return (any { my $usertag = $_; any { $_ eq $usertag } @{$popular_tags_ref} } @{$tags_ref}) ? $score : 0;
}

sub tag_popular {
  my ($tags_ref, $popular_tags_ref) = @_;
  return _tag_popular($tags_ref || [], $popular_tags_ref || [], $TAG_POPULAR_SCORE);
}

sub _strange_tag_combo {
  my ($tags_ref, $combo_list, $score) = @_;
  return 0 if !$score;
  return 0 if @{$tags_ref} < 2;
  return (any { all { my $combotag = $_; any { $_ eq $combotag } @{$tags_ref} } @{$_} } @{$combo_list})? $score : 0;
}

sub strange_tag_combo {
  my $tags_ref = shift;
  return _strange_tag_combo($tags_ref || [], $STRANGE_TAG_COMBO_LIST, $STRANGE_TAG_COMBO_SCORE);
}

sub _description_has_title {
  my ($description, $title, $score) = @_;
  return 0 if !$score;
  return $description =~ /\Q$title\E/i ? $score : 0;
}

sub description_has_title {
  my ($description, $title) = @_;
  return _description_has_title($description, $title, $DESCRIPTION_HAS_TITLE_SCORE);
}

sub _repeated_words {
  my ($uri, $title, $description, $tags_ref, $score1, $score2) = @_;
  return 0 if !$score1 and !$score2;
  my @skip = qw/the a an i me you all any/;
  my $str = join(' ', $title, $description, @{$tags_ref});
  $str =~ s/\W/ /g;
  my %words;
  foreach (grep { my $word = $_; all { $word ne $_ } @skip } map { lc $_ } split(/\s+/, $str)) {
    $words{$_} = 0 unless exists $words{$_};
    $words{$_}++;
  }
  my $total_count = %words;
  return 0 if $total_count < 5;
  my $twenty_percent = $total_count / 5;
  foreach (%words) {
    if ($words{$_} > $twenty_percent) {
      return $uri =~ /\b\Q$_\E\b/i ? $score2 : $score1;
    }
  }
  return 0;
}

sub repeated_words {
  my ($uri, $title, $description, $tags_ref) = @_;
  return _repeated_words($uri, $title, $description, $tags_ref,
			 $REPEATED_WORDS_SCORE, $REPEATED_WORDS_SCORE + $REPEATED_WORDS_URI_BONUS);
}

sub _too_many_commas {
  my ($description, $comment, $max, $score) = @_;
  return 0 if !$score;
  return $score if ($description =~ tr/,//) > $max;
  return $score if ($comment     =~ tr/,//) > $max;
  return 0;
}

sub too_many_commas {
  my ($description, $comment) = @_;
  return _too_many_commas($description, $comment, $TOO_MANY_COMMAS_MAX, $TOO_MANY_COMMAS_SCORE);
}

sub _prefilled_add_form {
  my ($prefilled, $score) = @_;
  return 0 if !$score;
  return $prefilled ? $score : 0;
}

sub prefilled_add_form {
  my ($prefilled) = @_;
  return _prefilled_add_form($prefilled, $PREFILLED_ADD_FORM_SCORE);
}

sub _authoritative_citation {
  my ($has_citation, $citation_understands_score, $score) = @_;
  return 0 if !$score;
  return 0 if defined $citation_understands_score && $citation_understands_score != 1;
  return $has_citation ? $score : 0;
}

sub authoritative_citation {
  my ($has_citation, $citation_understands_score) = @_;
  return _authoritative_citation($has_citation, $citation_understands_score, $AUTHORITATIVE_CITATION_SCORE);
}

sub _username_consonants {
  my ($username, $score) = @_;
  return $username =~ /[bcdfghjklmnpqrstvwxyz]{3,}/i && $username =~ /\d/ ? $score : 0;
}

sub username_consonants {
  my $username = shift;
  return _username_consonants($username, $USERNAME_CONSONANTS_SCORE);
}

sub _title_sitemap {
  my ($title, $score) = @_;
  return $title =~ /sitemap/ ? $score : 0;
}

sub title_sitemap {
  my $title = shift;
  return _title_sitemap($title, $TITLE_SITEMAP_SCORE);
}

sub _i_am_spam {
  my ($uri, $tags_ref, $score) = @_;
  return 0 if !$score;
  return ($1 ? int($2) : $score) if $uri =~ m|i_am_spam(/(\d+))?|;
  return $score if any { $_ eq 'i_am_spam' } @{$tags_ref};
  return 0;
}

sub i_am_spam {
  my ($uri, $tags_ref) = @_;
  return _i_am_spam($uri, $tags_ref || [], $I_AM_SPAM_SCORE);
}


package Bibliotech::Antispam::ScoreList;
use List::Util qw/first sum/;

sub new {
  my ($class, $records) = @_;
  return bless [undef, $records], ref $class || $class;
}

sub get {
  my ($self, $testname) = @_;
  my $record = first { $_->[0] eq $testname } @{$self->[1]} or return;
  return $record->[1];
}

sub set {
  my ($self, $testname, $new_score) = @_;
  my $record = first { $_->[0] eq $testname } @{$self->[1]};
  if (defined $record) {
    $record->[1] = $new_score;
  }
  else {
    push @{$self->[1]}, [$testname => $new_score];
  }
  $self->[0] = undef;
  return $new_score;
}

sub records {
  my $self = shift;
  return @{$self->[1]};
}

sub total {
  my $self = shift;
  $self->[0] = sum map { $_->[1] } @{$self->[1]} unless defined $self->[0];
  return $self->[0];
}

sub report {
  my $self = shift;
  return sprintf("Antispam Score List:\nTotal = %d\n%s",
		 $self->total,
		 join('', map { sprintf("%-24s%3d\n", @{$_}) } $self->records));
}


package Bibliotech::Antispam::Util;
# for use in non-posting situations; wiki, etc.

sub _scan_text_for_really_bad_phrases {
  my ($text, $phrase_list, $score) = @_;
  return 0 if !$score;
  $text =~ s/[-_]/ /g;
  foreach my $bad (@{$phrase_list}) {
    $text =~ m/\b\Q$bad\E\b/i and return wantarray ? ($score, $bad) : $score;
  }
  return 0;
}

sub scan_text_for_really_bad_phrases {
  _scan_text_for_really_bad_phrases(pop, $Bibliotech::Antispam::TAG_REALLY_BAD_PHRASE_LIST, 1);
}

sub scan_text_for_bad_phrases {
  _scan_text_for_really_bad_phrases(pop, $Bibliotech::Antispam::TAG_BAD_PHRASE_LIST, 1);
}

sub scan_wiki_text_for_bad_phrases {
  _scan_text_for_really_bad_phrases(pop, $Bibliotech::Antispam::WIKI_BAD_PHRASE_LIST, 1);
}

sub scan_text_for_bad_uris {
  _scan_text_for_really_bad_phrases(pop, $Bibliotech::Antispam::URI_BAD_HOST_LIST, 1);
}
