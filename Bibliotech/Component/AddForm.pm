# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::AddForm class provides an add form, an edit form,
# and an add comment form.

package Bibliotech::Component::AddForm;
use strict;
use base 'Bibliotech::Component';
use List::MoreUtils qw/any/;
use Bibliotech::Const;
use Bibliotech::Component::List;
use Bibliotech::Captcha;
use Bibliotech::CitationSource::RIS;
use Bibliotech::Bookmarklets;
use Bibliotech::DBI::Citation::Identifier;

use constant LOOK_UP_LABEL => 'Look Up';

sub last_updated_basis {
  ('NOW'); # temporarily fix POST bug
  #('DBI', 'LOGIN', shift->include_basis('/addwelcome'))
}

sub html_content {
  my ($self, $class, $verbose, $main, $action) = @_;
  my $bibliotech = $self->bibliotech;
  my $command    = $bibliotech->command;
  my $popup      = $command->is_popup;
  my $cgi        = $bibliotech->cgi;
  my $location   = $bibliotech->location;

  my ($add, $addcomment, $edit) = (0, 0, 0);
  if (!$action or $action eq 'add') {
    $action = 'add';
    $add = 1;
  }
  elsif ($action eq 'addcomment') {
    $addcomment = 1;
  }
  elsif ($action eq 'edit') {
    $edit = 1;
  }

  my $user = $self->getlogin;
  unless ($user) {
    my $msg;
    if ($action eq 'add') {
      if ($popup) {
	$msg = 'to add a bookmark';
      }
      else {
	if (my $uri = $cgi->param('uri')) {
	  $self->remember_current_uri;
	  eval { $bibliotech->preadd(uri => $uri) }; # if $uri =~ /\bnature\.com\//;
	  # if the eval above catches an error just ignore it
	  die "Location: ${location}home?uri=$uri\n";
	}
	else {
	  $msg = 'to add a bookmark';
	}
      }
    }
    elsif ($action eq 'addcomment') {
      $msg = 'to add a comment';
    }
    elsif ($action eq 'edit') {
      $msg = 'to edit a bookmark';
    }
    else {
      $msg = 'to perform this action';
    }
    return $self->saylogin($msg);
  }
  return Bibliotech::Page::HTML_Content->simple('Your account is inactive.') unless $user->active;

  my $validationmsg;
  my $need_captcha = 0;
  my $collapse_citation = 1;
  my $original_captcha_karma = $user->captcha_karma;
  my $button = $cgi->param('button');
  if (($button =~ /^Add/ or
       $button =~ /^Save/ or
       ($button ne LOOK_UP_LABEL and $cgi->param('uri') and $cgi->param('tags'))
      ) and $cgi->request_method eq 'POST') {
    my $uri = eval { $self->call_action_with_cgi_params($action, $user, $cgi)->bookmark->url; };
    if (my $e = $@) {
      die $e if $e =~ / at .* line /;
      if ($e =~ /^SPAM\b/) {
	if ($e eq "SPAM (super)\n" or
	    $e eq "SPAM (known host)\n") {
	  return Bibliotech::Page::HTML_Content->simple($self->tt('compspamblock'));
	}
	$need_captcha = 1;
      }
      else {
	$validationmsg = $e;
	$collapse_citation = 0 if $validationmsg =~ /\bcitation\b/i;
      }
    }
    else {
      my $continue = $cgi->param('continue') || 'library';
      if ($continue =~ /^comments/) {
	my $hash = Bibliotech::Bookmark->new($uri)->hash;
	die "Location: $location$continue/uri/$hash\n";
      }
      return $self->on_continue_param_return_close_library_or_confirm($continue, $uri, sub {
	my %confirmation = (add        => 'Your '.URI_TERM.' has been added.',
			    edit       => 'Your changes have been saved.',
			    addcomment => 'Your comment has been added.');
	return ($cgi->p($confirmation{$action} || 'Done.').
		$cgi->p({class => 'closebutton'},
			$cgi->button(-value => 'Close',
				     -class => 'buttonctl',
				     -onclick => 'window.close()')));
      });
    }
  }

  my $uri = $cgi->param('uri');
  $uri = undef unless $main;
  if ($uri and Bibliotech::Bookmark::is_hash_format($uri)) {
    my ($bookmark) = Bibliotech::Bookmark->search(hash => $uri) or die "Hash not found as a known URI ($uri).\n";
    $cgi->param('uri', $uri = $bookmark->url);
  }

  my $title = $self->cleanparam($cgi->param('title'));
  #$cgi->param(usertitle => $title) if $title and !defined($cgi->param('usertitle'));

  my $bookmark;
  if ($uri) {
    ($bookmark) = Bibliotech::Bookmark->search(url => $uri);
    if (!$bookmark) {
      eval {
	$bookmark = $bibliotech->preadd(uri => $uri);
	if ((my $new_uri = $bookmark->url) ne URI->new($uri)) {
	  $cgi->param(uri => ($uri = $new_uri));
	}
      };
      if (my $e = $@) {
	die $e if $e =~ / at .* line /;
	$validationmsg = $e;
      }
    }
    if ($bookmark) {
      $title = $bookmark->title;
      $cgi->param(title => $title) unless $cgi->param('title');
      my $usertitle = $title;
      if (my $citation = $bookmark->citation) {
	if (my $citation_title = $citation->title) {
	  $usertitle = $citation_title;
	}
      }
      $cgi->param(usertitle => $usertitle) unless $cgi->param('usertitle');
      $bookmark->adding(1);  # temp column, suppresses copy link in html_output
      if ($validationmsg) {
	my $user_article = $user->find_bookmark($bookmark);
	$bookmark->for_user_article($user_article) if $user_article;
      }
      if (!$button or $button eq LOOK_UP_LABEL) {
	my $user_article = $user->find_bookmark($bookmark);
	if ($user_article) {
	  $bookmark->for_user_article($user_article);
	  if ($add and $main) {
	    # trying to add an already added bookmark
	    my $editlink = 'edit'.($popup ? 'popup' : '');
	    my $hash = $bookmark->hash;
	    die "Location: $location$editlink?note=alreadyknown&uri=$hash\n";
	  }
	  if ($edit) {
	    $cgi->param(usertitle => $user_article->title);
	    $cgi->param(description => $user_article->description);
	    $cgi->param(tags => join(' ', map { /[\s,]/ ? "\"$_\"" : $_ } map { $_->name } $user_article->tags));
	    my $lastcomment = $user_article->last_comment;
	    if ($lastcomment) {
	      my $entry = $lastcomment->entry;
	      $entry =~ s| *<br ?/?>|\n|g;
	      $cgi->param(lastcomment => $entry);
	    }
	    $cgi->param(private => $user_article->private);
	    if (my $private_gang = $user_article->private_gang) {
	      $cgi->param(group => $private_gang->name);
	      $cgi->param(private => 2);  # for radio group
	    }
	    if (my $private_until = $user_article->private_until) {
	      if ($private_until->has_been_reached) {
		$cgi->param(private => 0);  # for radio group
	      }
	      else {
		$cgi->param(embargo => $private_until->utc->ymdhm);
	      }
	    }
	    $cgi->param(mywork => $user_article->user_is_author);
	  }
	}
	else {
	  if (!$add and $main) {
	    # trying to edit or addcomment for a non-copied bookmark
	    my $add = 'add'.($popup ? 'popup' : '');
	    my $hash = $bookmark->hash;
	    die "Location: $location$add?uri=$hash\n";
	  }
	}
	if ($add) {
	  if (my $from = $cgi->param('from')) {
	    if (my $from_user = Bibliotech::User->normalize_option({user => $from})) {
	      my $user_article = $from_user->find_bookmark($bookmark);
	      $bookmark->for_user_article($user_article) if $user_article;
	    }
	  }
	}
      }
      if (!$button or $button eq LOOK_UP_LABEL) {
	if (my $citation = $bookmark->cite) {  # cite() will come from user or authoritative side
	  my $fill_param_and_hidden = sub { my ($param, $value) = @_;
					    $cgi->param($param     => $value);
					    $cgi->param($param.'2' => $value); };  # second copy to detect edits
	  $fill_param_and_hidden->(ctitle   => $citation->title);
	  $fill_param_and_hidden->(cjournal => do { my $j = $citation->journal;
						    defined $j ? $j->name || $j->medline_ta : undef });
	  $fill_param_and_hidden->(cvolume  => $citation->volume);
	  $fill_param_and_hidden->(cissue   => $citation->issue);
	  $fill_param_and_hidden->(cpages   => $citation->page);
	  $fill_param_and_hidden->(cdate    => do { my $d = $citation->date;
						    defined $d ? $d->citation : undef });
	  $fill_param_and_hidden->(cauthors => $citation->expanded_author_list_dont_encode);
	  $fill_param_and_hidden->(cristype => $citation->ris_type);
	  $fill_param_and_hidden->(cdoi     => $citation->doi);
	  $fill_param_and_hidden->(cpubmed  => $citation->pubmed);
	  $fill_param_and_hidden->(casin    => $citation->asin);
	}
      }
    }
  }

  # parameter cleaning - need this to keep utf-8 output from messing up on an update reload
  foreach (qw/usertitle description tags comment/) {
    my $value = $self->cleanparam($cgi->param($_));
    $cgi->param($_ => $value) if $value;
  }

  my $note = $cgi->param('note');

  my @gangnames = map($_->name, $bibliotech->user->gangs);
  if (my $loaded_gang_name = $cgi->param('group')) {
    unless (grep($loaded_gang_name eq $_, @gangnames)) {
      push @gangnames, $loaded_gang_name;
    }
  }
  my $group_control = $cgi->popup_menu(-id => 'groupselect',
				       -name => 'group',
				       -class => 'pulldownctlminor',
				       -values => ['', sort @gangnames],
				       -default => '');

  my $show_citation = defined $bookmark && $main;

  my %ttvars =
      (action => $action,
       action_with_popup => $action.($popup ? 'popup' : ''),
       is_already_known => $note && $note eq 'alreadyknown',
       is_add => $add,
       is_addcomment => $addcomment,
       is_edit => $edit,
       is_main => $main,
       is_popup => $popup,
       bookmark => $bookmark,
       show_citation => $show_citation,
       collapse_citation => $collapse_citation,
       has_groups => @gangnames > 0,
       group_control => $group_control,
       identified => (defined $bookmark ? scalar($bookmark->html_content($bibliotech, 'preadd', 1, 1)) : undef),
       look_up_button_label => LOOK_UP_LABEL,
       citation_button_label => (((defined $bookmark && $bookmark->cite) ? 'Edit' : 'Add').' Citation'),
       captcha => '',
       );

  if ($need_captcha) {
    if ($cgi->param('captchamd5sum')) {
      $user->mark_captcha_shown_repeat;
      $cgi->Delete('captchamd5sum');
      $cgi->Delete('captchacode');
    }
    else {
      $user->mark_captcha_shown_first;
    }
    my $captcha = Bibliotech::Captcha->new;
    my $md5sum  = $captcha->generate_code(5);
    my $src     = $captcha->img_href($md5sum);
    $ttvars{captcha} = $self->tt('compcaptcha', {captchasrc => $src, captchamd5sum => $md5sum});
  }

  if (!$cgi->param('button') and ($cgi->param('tags') or $cgi->param('description'))) {
    # we don't "put words in your mouth" so inclusion of tags or
    # description without button press is potentially a spam bot
    # it just gets marked so the antispam module can ponder it
    $cgi->param(prefilled => 1);
  }

  my $o = $self->tt('compadd', \%ttvars, $self->validation_exception('', $validationmsg));

  if ($action eq 'addcomment' and $main) {
    my $comments_component = Bibliotech::Component::Comments->new({bibliotech => $bibliotech});
    $o .= $comments_component->html_content($class.'comment', 1, 0, 1)->content;  # that last 1 = 'just comments'
  }

  my $javascript_popup = $self->popup_javascript;
  my $javascript_tag_list = $self->autocomplete_javascript_tag_list($user) || '';
  my $javascript_first_empty = $self->firstempty($cgi, $action, $add || $edit ? qw/uri tags usertitle description/ : 'comment');
  my $javascript_onload = join('; ',
			       grep { $_ }
			       ($show_citation
				? ($collapse_citation ? "document.getElementById('caddarea').style.display = 'none'"
				                      : "document.getElementById('editcitationbutton').value = 'Hide Form'")
				: undef,
				$popup ? 'fixsize()' : undef,
				$main  ? $javascript_first_empty : undef));
  
  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					      javascript_file => $bibliotech->location.'autocomplete.js',
					      javascript_block => $javascript_popup.$javascript_tag_list,
					      javascript_onload => $javascript_onload});
}

sub autocomplete_html {
  return <<'EOH';
   <div id="tbox-closed" class="auto-complete">
     Tags will appear here as you type in the tags box above.
   </div>
   <div id="tbox-suggest-wrapper">
   <div id="tbox-suggest" class="auto-complete" style="display:none">
     <div id="slink-alpha">
     </div>
     <div id="slink-usage" style="display:none">
     </div>
     <div id="add-form-ac-results-suggest" class="add-form-ac-results"></div>
   </div>
   </div>
   <div id="tbox-all-usage" class="auto-complete" style="display:none">
     <div id="add-form-ac-results-usage" class="add-form-ac-results"></div>
   </div>
   <div id="tbox-all-alpha" class="auto-complete" style="display:none">
     <div id="add-form-ac-results-alpha" class="add-form-ac-results"></div>
   </div>
EOH
}

sub popup_javascript {
  "function rec_popup_width()  { return $Bibliotech::Bookmarklets::POPUP_WIDTH; }\n".
  "function rec_popup_height() { return $Bibliotech::Bookmarklets::POPUP_HEIGHT; }\n";
}

sub autocomplete_javascript_tag_list {
  my ($self, $user) = @_;
  return unless defined $user;

  my $o .= 'var tags = {';
  $o .= join(', ',
	     map { my $label = $_->label_with_single_quotes_escaped;
		   my $score = $_->memory_score;
		   "\'$label\':$score";
		 } $user->my_tags_alpha
	     );
  $o .= "};\n";

  return $o;
}

sub call_action_with_cgi_params {
  my ($self, $action, $user, $cgi) = @_;
  my $bibliotech = $self->bibliotech;

  my @params = qw/uri comment/;
  push @params, qw/title usertitle description tags mywork private group embargo lastcomment from/
      if $action eq 'add' or $action eq 'edit';

  my %fields = map { $_ => $self->cleanparam($cgi->param($_)); } @params;

  # private = 0  no privacy
  # private = 1  private to me
  # private = 2  private to group
  if (!$fields{private}) {
    die "You cannot choose to share with all and specify a private group.\n" if $fields{group};
    die "You cannot choose to share with all and specify a release date.\n"  if $fields{embargo};
  }
  elsif ($fields{private} == 2) {
    die "You must specify a private group.\n" unless $fields{group};
    $fields{private} = 0;
  }

  if ($fields{embargo}) {
    die "You cannot choose to share with all and specify a release date.\n"
	unless $fields{private} || $fields{group};
    $fields{embargo} =~ s|\b(\d+:\d+)\b|$1:00|;  # add seconds
    $fields{embargo} =~ s/(?<! UTC)$/ UTC/;      # add UTC time zone
  }
  else {
    $fields{embargo} = undef;
  }

  $fields{group} ||= undef;

  if ($action eq 'add' or $action eq 'edit') {
    $fields{tags} or
        die "You must provide at least one tag. A tag can be any descriptive word about this article.\n";
    my @tags = $bibliotech->parser->tag_list($fields{tags}) or
	die "Missing tags, malformed tags, or use of a reserved keyword as a tag.\n";
    $fields{tags} = \@tags;
  }

  $fields{user} = $user;

  if (my $md5sum = $cgi->param('captchamd5sum')) {
    if (my $code = $cgi->param('captchacode')) {
      my $captcha = Bibliotech::Captcha->new;
      my $result  = $captcha->check_code($code, $md5sum);
      if ($result == 1) {
	$fields{captcha} = 1;
	$user->mark_captcha_passed;
      }
      else {
	$fields{captcha} = -1;
	$user->mark_captcha_failed;
      }
    }
  }

  if (_check_if_citation_edited($cgi)) {
    $fields{user_citation} = $self->hashref_for_user_citation($cgi);
    _validate_user_citation_standardized_identifiers($fields{user_citation});
  }

  $fields{prefilled} = 1 if $cgi->param('prefilled');

  return $bibliotech->$action(%fields);  # Bibliotech::add() or Bibliotech::edit()
}

our @citation_field_names = qw/ctitle cjournal cvolume cissue cpages cdate cauthors cristype cdoi cpubmed casin/;

sub _check_if_citation_edited {
  my $cgi = shift;
  my $new = sub { local $_ = shift; $cgi->param($_)||''; };
  my $old = sub { local $_ = shift; $cgi->param($_.'2')||''; };
  return any { $new->($_) ne $old->($_) } @citation_field_names;
}

sub hashref_for_user_citation {
  my ($self, $cgi) = @_;
  my %citation;
  foreach my $c_field (@citation_field_names) {
    my $value = $self->cleanparam($cgi->param($c_field)) or next;
    (my $field = $c_field) =~ s/^c//;
    $citation{$field} = $value;
  }
  return \%citation;
}

sub _validate_user_citation_standardized_identifiers {
  my $citation = shift;
  if (my $pubmed = $citation->{pubmed}) {
    Bibliotech::Citation::Identifier::Pubmed->new($pubmed)
	or die "Provided PMID does not appear to be valid (use digits only).\n";
  }
  if (my $doi = $citation->{doi}) {
    Bibliotech::Citation::Identifier::DOI->new($doi)
	or die "Provided DOI does not appear to be valid (use identifier beinging with \"10.\").\n";
  }
  if (my $asin = $citation->{asin}) {
    Bibliotech::Citation::Identifier::ASIN->new($asin)
	or die "Provided ASIN does not appear to be valid (use only digits and letters).\n";
  }
}

1;
__END__
