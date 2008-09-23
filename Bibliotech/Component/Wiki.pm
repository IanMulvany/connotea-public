# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Wiki class provides a wiki.

package Bibliotech::Component::Wiki;
use strict;
use base 'Bibliotech::Component';
use Wiki::Toolkit;
use Wiki::Toolkit::Store::MySQL;
use Wiki::Toolkit::Formatter::Default;
use Wiki::Toolkit::Plugin::Diff;
use Encode qw/decode_utf8 encode_utf8 is_utf8/;
use List::MoreUtils qw/uniq/;
use Bibliotech::DBI;
use Bibliotech::Util;
use Bibliotech::Antispam;

our $WIKI_DBI_CONNECT   = __PACKAGE__->cfg_required('DBI_CONNECT');
our $WIKI_DBI_USERNAME  = __PACKAGE__->cfg('DBI_USERNAME');
our $WIKI_DBI_PASSWORD  = __PACKAGE__->cfg('DBI_PASSWORD');
our $WIKI_ADMIN_USERS   = __PACKAGE__->cfg('ADMIN_USERS');
our $WIKI_LOCK_TIME     = __PACKAGE__->cfg('LOCK_TIME') || '10 MINUTE';
our $WIKI_HOME_NODE     = __PACKAGE__->cfg('HOME_NODE') || 'System:Home';
our $WIKI_MAX_PAGE_SIZE = __PACKAGE__->cfg('MAX_PAGE_SIZE') || 40000;
our $WIKI_MAX_EXT_LINKS = __PACKAGE__->cfg('MAX_EXT_LINKS') || 75;
our $WIKI_SCAN          = __PACKAGE__->cfg('SCAN');
    $WIKI_SCAN          = 1 unless defined $WIKI_SCAN;
our $WIKI_ALLOW_EDIT    = __PACKAGE__->cfg('ALLOW_EDIT');
    $WIKI_ALLOW_EDIT    = 1 unless defined $WIKI_ALLOW_EDIT;

sub last_updated_basis {
  (Bibliotech::Component::Wiki::DBI->sql_last_modified_unix_timestamp->select_val);
}

sub wiki_obj {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $prefix     = $location.'wiki/';
  my $dbh        = Bibliotech::Component::Wiki::DBI->db_Main;
  my $store      = Wiki::Toolkit::Store::MySQL->new(dbh => $dbh);
  $store->{_charset} ||= 'utf8'; # 'iso-8859-1';  # fix bug where this would not be set but be expected
  my $formatter  = Bibliotech::Wiki::CGI::Formatter->new(extended_links => 1,
							 implicit_links => 1,
							 macros         => {},
							 node_prefix    => $prefix,
							 # never add allowed_tags or it will break WebAPI page
							 );
  my $wiki       = Wiki::Toolkit->new(store     => $store,
				      #search    => $search,
				      formatter => $formatter,
				     );

  $formatter->prefix($prefix);
  $formatter->bibliotech($bibliotech);
  $formatter->node_exists_callback(sub { $wiki->node_exists(@_) });

  return $wiki;
}

sub wiki_node_name_for_object {
  my ($self, $obj) = @_;
  return Bibliotech::Component::Wiki::NodeName->new(ucfirst($obj->noun).':'.$obj->label_parse_easy);
}

sub exists_wiki_page_for_object {
  my ($self, $obj) = @_;
  my $node = $self->wiki_node_name_for_object($obj);
  my $wiki = $self->wiki_obj;
  return $node if $wiki->node_exists("$node");
  return;
}

sub rss_content {
  my ($self, $verbose) = @_;
  my $wiki       = $self->wiki_obj;
  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  return $self->tt('compwikirss',
		   {changes   => [map { Bibliotech::Component::Wiki::Change->new({change    => $_,
										  component => $self,
										  wiki      => $wiki,
										 })
				      } $wiki->list_recent_changes(last_n_changes => 15)],
		    prefix    => $location.'wiki/',
		    rssurl    => $location.'rss/wiki/',
		    interwiki => do { local $_ = $bibliotech->sitename;
				      s/ (\w)/uc($1)/ge;  # WikiWord it by removing spaces before words and capitalizing
				      s/\s+//g;           # then mercilessly remove all remaining spaces
				      $_ },
		   });
}

sub _standardize_line_endings {
  local $_ = shift;
  return $_ unless $_;
  s/\r\n/\n/g;
  s/\r/\n/g;
  return $_;
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech    = $self->bibliotech;
  my $location      = $bibliotech->location;
  my $prefix        = $location.'wiki/';
  my $cgi    	    = $bibliotech->cgi;
  my $create_node   = $self->cleanparam($cgi->param('create'));
  my $user          = $bibliotech->user;
  my $username      = defined $user ? $user->username : undef;
  my $wiki          = $self->wiki_obj;
  my $action_stated = $self->cleanparam($cgi->param('action'));
  my $action 	    = $action_stated || 'display';
  my $node_stated   = Bibliotech::Component::Wiki::NodeName->new
                          ($bibliotech->command->wiki_path || $self->cleanparam($cgi->param('node')));
  my $node   	    = Bibliotech::Component::Wiki::NodeName->new($node_stated || $WIKI_HOME_NODE);
  my $node_real     = $node->clone;
  my $version  	    = do { my $v = $self->cleanparam($cgi->param('version')); $v ? int($v) : undef; };
  my $button   	    = $self->cleanparam($cgi->param('button'));
  my $action_real   = $action;
  my %vars;

  die "Location: $prefix$create_node?action=edit\n" if $create_node;

  $bibliotech->has_rss(1) if $main && !$node_stated && $node eq $WIKI_HOME_NODE;

  unless ($node->is_valid) {
    $action_real = 'display';
    $node_real = Bibliotech::Component::Wiki::NodeName->new('System:InvalidName');
  }

  # force bookmark prefixes to be the hash and not the URL
  if ($node->is_referent_bookmark) {
    unless (Bibliotech::Bookmark::is_hash_format($node->base)) {
      $action_real = 'display';
      $node_real = Bibliotech::Component::Wiki::NodeName->new('System:BookmarkNotHash');
    }
  }

  # check that user, tag, bookmark prefixed nodes are really in the database
  my $referent;
  if ($node->is_referent and $node->base) {
    unless ($referent = Bibliotech::DBI::class_for_name($node->prefix)->new($node->base)) {
      $action_real = 'display';
      $node_real = Bibliotech::Component::Wiki::NodeName->new('System:'.$node->prefix.'Invalid');
    }
  }

  my $can_edit = $self->can_edit_node($node, $user, $referent);

  # access control
  if ($action ne 'display' and $can_edit != 1) {
    $action_real = 'display';
    if ($can_edit == 0) {
      $node_real = Bibliotech::Component::Wiki::NodeName->new('System:AccessDenied');
    }
    else {
      $node_real = Bibliotech::Component::Wiki::NodeName->new('System:PleaseLogin');
      $self->remember_current_uri;
    }
  }

  if ($action eq 'edit' and !$WIKI_ALLOW_EDIT) {
    $action_real = 'display';
    $node_real = Bibliotech::Component::Wiki::NodeName->new('System:NoEdit');
  }

  if (defined $user and !$user->active) {
    $action_real = 'display';
    $node_real = Bibliotech::Component::Wiki::NodeName->new('System:AccessDenied');
  }

  # info page for User: and System: nodes
  if ($action eq 'display' and $node->prefix and !$node->base) {
    $node_real = Bibliotech::Component::Wiki::NodeName->new('Generate:PageList');
    $cgi->param(prefix => $node->prefix);
  }

  my $lock_plugin = Wiki::Toolkit::Plugin::Lock->new;
  $wiki->register_plugin(plugin => $lock_plugin);

  # multiplex buttons on edit form
  if ($action_real eq 'afteredit') {
    if ($button eq 'Save') {
      $action_real = 'commit';
    }
    elsif ($button eq 'Preview') {
      $action_real = 'edit';
    }
    elsif ($button eq 'Cancel') {
      $action_real = 'display';
      $lock_plugin->try_unlock($node, $username);
    }
  }

  if ($action_real eq 'edit') {
    my ($got_lock, $lock_username, $lock_expire)
	= $lock_plugin->try_lock($node_real, $username, $WIKI_LOCK_TIME);
    unless ($got_lock) {
      $action_real = 'display';
      $node_real = Bibliotech::Component::Wiki::NodeName->new('System:Locked');
      my $lock_expire_obj  = Bibliotech::Date->new($lock_expire)->mark_time_zone_from_db->utc;
      $vars{lock_username} = $lock_username;
      $vars{lock_expire}   = $lock_expire_obj->label_plus_time;
      $vars{lock_time}     = $lock_expire_obj->str_until_hms;
    }
  }

  my $pp;
  my $edit_validation;

  if ($action_real eq 'display') {
    $node_real     = $self->test_node_for_retrieval($wiki, $node_real) || $node_real;
    my %raw        = $self->retrieve_node($wiki, $node_real, $version, 1);
    $node          = $node_real if lc($node) eq lc($node_real);          # correct capitalization
    my $version    = $raw{version};
    my $current    = $raw{current_version};
    my $content    = $raw{content};

    unless ($raw{content}) {
      $node_real   = $self->system_redirect_for_no_content($version, $current, $can_edit);
      $version     = undef;
      %raw         = $self->retrieve_node($wiki, $node_real, $version, 1);
      $version     = $raw{version};
      $current     = $raw{current_version};
      $content     = $raw{content};
    }

    my $cooked     = $self->text_format($user, $wiki, $node, $action, $content, \%vars);
    my $updated    = $raw{content} ? Bibliotech::Date->new($raw{last_modified})->mark_time_zone_from_db->utc : undef;
    my $is_current = $raw{is_current};
    my $metadata   = $raw{metadata};
    my $m_author   = exists $metadata->{username} ? $metadata->{username}->[0] : undef;
    my $author     = $m_author ? Bibliotech::User->new($m_author) : undef;
    my $author_a   = $m_author ? $cgi->a({href => $prefix.'User:'.$m_author}, 'User:'.$m_author) : undef;
    my $comment    = exists $metadata->{comment} ? $metadata->{comment}->[0] : undef;
    my $is_admin   = $self->is_admin_user($username);

    $pp =  $self->print_page({node    	 => $node,
			      node_real  => $node_real,
			      content 	 => $cooked,
			      version    => $version,
			      current    => $current,
			      is_current => $is_current,
			      updated 	 => $updated,
			      author  	 => $author,
			      author_a   => $author_a,
			      comment    => $comment,
			      can_edit   => $can_edit,
			      is_admin   => $is_admin,
			      referent   => $referent,
			     });
  }
  elsif ($action_real eq 'commit') {
    my $submitted_content = _standardize_line_endings($self->cleanparam($cgi->param('content')));
    my $checksum          = $self->cleanparam($cgi->param('checksum'));  # as in, the old checksum
    my $comment           = $self->cleanparam($cgi->param('comment'));
    my %metadata          = (username => $username, comment => $comment);
    eval {
      _validate_submitted_content($submitted_content);
      if ($submitted_content) {
	$wiki->write_node("$node", $submitted_content, $checksum, \%metadata) or die "Checksum conflict.\n";
      }
      else {
	$wiki->delete_node("$node") if $wiki->node_exists("$node");
      }
    };
    if (my $e = $@) {
      die $e if $e =~ / at .* line /;
      $edit_validation = $e;
      $action_real = 'edit';
    }
    else {
      $referent->mark_updated if defined $referent;  # notify other components to recalc
      die "Location: ${location}wiki/$node\n";
    }
  }
  if ($action_real eq 'edit') {  # not elsif because it can fall into this from commit
    my ($content, $checksum, $preview_html, $updated);
    if ($content = _standardize_line_endings($self->cleanparam($cgi->param('content')))) {
      $cgi->param(content => $content);  # save the utf8 version so the edit form box works
      $checksum = $self->cleanparam($cgi->param('checksum'));
      if (my $comment = $self->cleanparam($cgi->param('comment'))) {
	$cgi->param(comment => $comment);
      }
      $preview_html = $self->text_format($user, $wiki, "$node", $action, $content, \%vars);
    }
    else {
      my %raw = $self->retrieve_node($wiki, $node, $version, 1);
      if ($raw{current_version}) {
	$content  = is_utf8($raw{content}) ? $raw{content} : (decode_utf8($raw{content}) || $raw{content});
	$checksum = $raw{current_checksum};  # may not be visible version checksum, allows rollback
	$updated  = Bibliotech::Date->new($raw{last_modified})->mark_time_zone_from_db->utc;
      }
      else {
	$content = $self->content_for_new_page($wiki, $node);
      }
    }
    $pp = $self->print_editform({node     => $node,
				 content  => $content,
				 checksum => $checksum,
				 preview  => $preview_html,
				 updated  => $updated,
				 error    => $edit_validation,
			        });
  }
  elsif ($action eq 'diff') {
    unless ($version) {
      my %raw = $wiki->retrieve_node("$node");
      $version = $raw{version};
    }
    my $old_version = $self->cleanparam($cgi->param('base')) || $version - 1;

    $pp =  $self->print_diff({node          => $node,
			      left_version  => $old_version,
			      right_version => $version,
			      wiki          => $wiki,
			     });
  }

  my $main_content = $pp->content;

  # wiki sidebar
  my $sb = '';
  my %vars = (action => $action, node => $node, nodeprefix => $node->prefix, basenode => $node->base);
  my $add_include = sub {
    foreach (@_) {
      if (my $add = $self->include($_, $class, $verbose, $main, \%vars)) {
	$sb .= $add;
	last;
      }
    }
  };
  my $activity = ($action eq 'afteredit' && ($button eq 'Save' || $button eq 'Cancel')) ? 'display' : $action;
  if ($activity =~ /^(?:after)?edit$/) {
    $add_include->('/wikiedithelp');
  }
  else {
    $add_include->($node->prefix ? '/wiki'.lc($node->prefix) : (), '/wikigeneral');
    $add_include->('/wikisidebar');
  }
  my $sidebar_content = $cgi->div({class => 'wikisidebar'}, $sb);

  my $interject_content = $self->possible_div_for_referent($referent);

  return Bibliotech::Page::HTML_Content->new
      ({html_parts => {main      => $main_content,
		       sidebar   => $sidebar_content,
		       interject => $interject_content,
		      },
	title => undef,
      });
}

sub _without_wiki_explicit_links_and_spaces {
  local $_ = $_;
  s/\[[^\]]*\]//gs;
  s/\s+//gs;
  return $_;
}

sub _validate_submitted_content {
  local $_ = shift or return;
  length($_) > $WIKI_MAX_PAGE_SIZE
      and die "Sorry, each wiki page source text is limited to $WIKI_MAX_PAGE_SIZE characters at maximum.\n";
  do { my @count = uniq(/(?:https?|ftp:[^\]\|\s]+)/g); scalar @count; } > $WIKI_MAX_EXT_LINKS
      and die "Sorry, too many external hyperlinks.\n";  # antispam, intentionally omit http/https/ftp or number
  m!\[https?://[^|]+\|[^\]]*(click here|online here|for sale here|>>>[\w ]+<<<)[^\]]*\]!i
      and die "Sorry, spam link detected.\n";    # antispam, intentionally omit trigger phrase
  $WIKI_SCAN == 1 && Bibliotech::Antispam::Util::scan_text_for_really_bad_phrases($_)
      and die "Sorry, spam phrase detected.\n";  # antispam, intentionally omit trigger phrase
  $WIKI_SCAN == 2 && Bibliotech::Antispam::Util::scan_text_for_bad_phrases($_)
      and die "Sorry, spam phrase detected.\n";  # antispam, intentionally omit trigger phrase
  length(_without_wiki_explicit_links_and_spaces($_)) == 0
      and die "Sorry, a wiki page may not consist solely of explicit links.\n";
}

sub plain_content {
  my ($self, $class, $verbose) = @_;

  my $bibliotech    = $self->bibliotech;
  my $location      = $bibliotech->location;
  my $prefix        = $location.'wiki/';
  my $cgi           = $bibliotech->cgi;
  my $user          = $bibliotech->user;
  my $username      = defined $user ? $user->username : undef;
  my $wiki          = $self->wiki_obj;
  my $action_stated = $self->cleanparam($cgi->param('action'));
  my $action        = $action_stated || 'display';
  my $action_real   = $action;
  my $node_stated   = Bibliotech::Component::Wiki::NodeName-> new
                          ($bibliotech->command->wiki_path || $self->cleanparam($cgi->param('node')));
  my $node          = Bibliotech::Component::Wiki::NodeName->new($node_stated || $WIKI_HOME_NODE);
  my $node_real     = $node->clone;
  my $version       = do { my $v = $self->cleanparam($cgi->param('version')); $v ? int($v) : undef; };

  die "HTTP 404\n" unless $node->is_valid;

  # force bookmark prefixes to be the hash and not the URL
  if ($node->is_referent_bookmark) {
    unless (Bibliotech::Bookmark::is_hash_format($node->base)) {
      die "HTTP 404\n";   
    }
  }

  # check that user, tag, bookmark prefixed nodes are really in the database
  my $referent;
  if ($node->is_referent and $node->base) {
    unless ($referent = Bibliotech::DBI::class_for_name($node->prefix)->new($node->base)) {
      die "HTTP 404\n";   
    }
  }

  if (defined $user and !$user->active) {
    die "HTTP 403\n";
  }

  # info page for User: and System: nodes
  if ($action eq 'display' and $node->prefix and !$node->base) {
    $node_real = Bibliotech::Component::Wiki::NodeName->new('Generate:PageList');
    $cgi->param(prefix => $node->prefix);
  }

  if ($action_real eq 'display') {

    $node_real     = $self->test_node_for_retrieval($wiki, $node_real) || $node_real;
    my %raw        = $self->retrieve_node($wiki, $node_real, $version, 0);
    $node          = $node_real if lc($node) eq lc($node_real);          # correct capitalization
    my $version    = $raw{version};
    my $current    = $raw{current_version};
    my $content    = $raw{content};

    unless ($raw{content}) {
      $node_real   = $self->system_redirect_for_no_content($version, $current, 0);
      $version     = undef;
      %raw         = $self->retrieve_node($wiki, $node_real, $version, 0);
      $version     = $raw{version};
      $current     = $raw{current_version};
      $content     = $raw{content};
    }

    return $content;
  }
  else {
    die "Only display action is support in txt or plain modes.\n";
  }
}

sub txt_content {
  my $self = shift;
  return $self->plain_content(@_);
}

sub text_format {
  my ($self, $user, $wiki, $node, $action, $content, $special_vars) = @_;
  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $prefix     = $location.'wiki/';
  my %vars       = (node => $node, action => $action, prefix => $prefix, %{$special_vars||{}});
  my $allowable  = _censor_verbatim_for_untrusted_content($content, $node);
  my $coded  	 = $bibliotech->replace_text_variables([$allowable], $user, \%vars)->[0];
  my $cooked 	 = $coded ? $wiki->format($coded) : '';
  return $cooked;
}

sub _censor_verbatim_for_untrusted_content {
  local $_ = shift;
  my $node = shift;
  $node =~ /^(?:Generate|System):/ or s/!FASTHTML://g;
  return $_;
}

sub retrieve_node {
  my ($self, $wiki, $node, $version, $for_html_output) = @_;
  return unless defined $node;
  my %raw = eval {
    if ($node->prefix eq 'Generate') {
      my %current = $self->generate_node($node, $wiki, $for_html_output);
      $current{is_current}       = 1;
      $current{current_version}  = $current{version};
      $current{current_checksum} = $current{checksum};
      return %current;
    }
    my %current = $wiki->retrieve_node("$node");
    my %asked   = $version ? $wiki->retrieve_node(name => "$node", version => $version)
	                   : %current;
    $asked{is_current}       = $current{version} == $asked{version} ? 1 : 0;
    $asked{current_version}  = $current{version};
    $asked{current_checksum} = $current{checksum};
    return %asked;
  };
  die $@ if $@;
  return $raw{content} unless wantarray;
  return %raw;
}

# problem: CGI::Wiki::Store::Database and MySQL 5.0.18 interact to create a bug because although MySQL
# normally is case insensitive for name='BlahBlah' where clauses, for some reason the exact SQL query
# SELECT MAX(version) FROM content WHERE name='BlahBlah' enforces sensitivity so Blahblah and BlahBlah
# are different.
# solution: this routine checks for a wiki node and normalizes the case
# alternate solutions: using retrieve_node() will trigger the error, unless you patch the module
# using node_exists() is not sufficient because it won't normalize the case
sub test_node_for_retrieval {
  my ($self, $wiki, $node) = @_;
  return $node if $node->is_generate;
  my $sth = Bibliotech::Component::Wiki::DBI->sql_test_node_for_retrieval;
  $sth->execute("$node") or die $sth->errstr;
  my $node_authoritative;
  ($node_authoritative) = $sth->fetch if $sth->rows;
  $sth->finish;
  return Bibliotech::Component::Wiki::NodeName->new($node_authoritative);
}

sub list_only_edited_by_username {
  my ($self, $wiki, $username) = @_;
  my $sth = Bibliotech::Component::Wiki::DBI->sql_list_only_edited_by_username;
  $sth->execute($username, $username) or die $sth->error;
  my @nodes;
  while (my ($node_id, $node, $version, $max_version, $others) = $sth->fetchrow_array) {
    push @nodes, Bibliotech::Component::Wiki::NodeName->new($node);
  }
  return @nodes;
}

# in:
#   $self
#   $node - node name object
#   $user - current user object (Bibliotech::User)
#   $referent - wiki pages referent object (e.g. Bibliotech::Tag)
# out:
#    1 = yes, can edit
#    0 = no, cannot edit
#   -1 = maybe, need to login and be a user
#   -2 = maybe, need to login and be an admin user
sub can_edit_node {
  my ($self, $node, $user, $referent) = @_;
  return  0 if !$node;
  return  0 if $node->is_generate;
  return  0 if !$node->base;
  return -2 if $node->is_system && !defined($user);
  return -1 if !defined($user);
  return  1 if !$node->prefix;
  if (defined $referent) {
    return $user->user_id == $referent->user_id    ? 1 : 0 if $referent->isa('Bibliotech::User');
    return $referent->is_accessible_by_user($user) ? 1 : 0 if $referent->isa('Bibliotech::Gang');
    return 1;
  }
  return  1 if $node->is_system && $self->is_admin_user($user->username);
  return  0;
}

sub is_admin_user {
  my $username = pop or return;
  $WIKI_ADMIN_USERS && ref $WIKI_ADMIN_USERS eq 'ARRAY' or return;
  return grep { $username eq $_ } @{$WIKI_ADMIN_USERS};
}

sub generate_node {
  my ($self, $node, $wiki, $for_html_output) = @_;
  my %raw = $self->generate_node_inner($node, $wiki) or return ();
  $raw{content} =~ s/!FASTHTML:{([^}]*)}{([^}]*)}/$1/g unless $for_html_output;
  # add common metadata for Generate: nodes
  $raw{last_modified} ||= Bibliotech::Util::now->mysql_datetime;
  $raw{comment}       ||= 'auto';
  return %raw;
}

sub generate_node_inner {
  my ($self, $node, $wiki) = @_;
  return $self->generate_node_list($wiki)           if $node eq 'Generate:PageList';
  return $self->generate_node_history($wiki, $node) if $node =~ /^Generate:History_/;
  return $self->generate_node_system_links($wiki)   if $node eq 'Generate:SystemLinks';
  return $self->generate_recent_changes($wiki)      if $node eq 'Generate:RecentChanges';
  return;
}

sub generate_node_list_intro {
  my ($self, $wiki, $nodeprefix) = @_;
  if ($nodeprefix) {
    my $saved = $self->retrieve_node($wiki, Bibliotech::Component::Wiki::NodeName->new('System:'.$nodeprefix.'Prefix'));
    return $saved if $saved;
  }
  return '= '.($nodeprefix || 'Page')." List =\n";
}

sub generate_node_list {
  my ($self, $wiki, $nodeprefix) = @_;
  my $cgi = $self->bibliotech->cgi;
  return (content => join('',
			  $self->generate_node_list_intro($wiki, $nodeprefix),
			  "\n",
			  $self->optimized_cheat_on_bullet_list_of_pagelinks(
			    map { "    * pagelink=$_=\n" }
			    sort { lc($a) cmp lc($b) }
			    grep { $nodeprefix ? /^$nodeprefix:/ : !/^System:/ }
			    $wiki->list_all_nodes)));
}

sub optimized_cheat_on_bullet_list_of_pagelinks {
  my $self = shift;
  my $cgi = $self->bibliotech->cgi;
  my $formatter = $self->wiki_obj->formatter;
  return '!FASTHTML:{'.join('', @_).'}{'.
      $cgi->ul(
	map {
	  m|^    \* pagelink=(.+)=\n$|;
	  $cgi->li($formatter->wikilink($1, undef, undef, undef, 1))."\n";
	} @_).
      "}\n";
}

sub versions_of_node {
  my ($self, $wiki, $node) = @_;

  my %node = $wiki->retrieve_node("$node");
  my $current = $node{version};

  my @versions;
  foreach my $version (1 .. $current) {
    push @versions, {$wiki->retrieve_node(name => "$node", version => $version)};
  }

  return wantarray ? @versions : \@versions;
}

sub version_line {
  my ($self, $node, $node_hashref) = @_;
  my %node     = %{$node_hashref};
  my $version  = $node{version};
  my $last     = $version > 1 ? $version - 1 : undef;
  my $username = $node{metadata}->{username}->[0];
  my $comment  = $node{metadata}->{comment}->[0];
  return join(' ',
	      "    * wikilink=${node}\#${version}=",
	      '('.($last ? "wikilink=${node}\#${version}\#\#${last}=\"diff from last\" | " : '').
	      "wikilink=${node}\#\#${version}=\"diff to current\")",
	      grep { $_ } ($username ? "edited by User:$username" : undef,
			   $comment  ? "($comment)" : undef,
			   )
	      )."\n";
}

sub generate_node_history {
  my ($self, $wiki, $node) = @_;
  $node =~ /^Generate:History_([\w: \-]+)$/;
  my $target = $1;
  return (content => join('',
			  "= Page History for $target =\n",
			  map { $self->version_line($target, $_) }
			  reverse $self->versions_of_node($wiki, $target)));
}

sub generate_recent_changes {
  my ($self, $wiki) = @_;
  $self->bibliotech->has_rss(1);
  return (content => join('',
			  "= Recent Changes =\n",
			  "{>RSS}\n",
			  map { $self->version_line($_->{name}, $_) }
			  $wiki->list_recent_changes(last_n_changes => 30)));
}

sub system_links {
  ('System:Home',            # home page text
   'System:AccessDenied',    # tried to edit a page not allowed to edit
   'System:NoEdit',          # tried to edit a page but editing is temporarily suspended wiki-wide
   'System:PleaseLogin',     # could maybe edit if were logged in, can't tell
   'System:SystemPrefix',    # asked for System: with no base node
   'System:GeneratePrefix',  # asked for Generate: with no base node
   'System:UserPrefix',      # asked for User: with no base node
   'System:TagPrefix',       # asked for Tag: with no base node
   'System:BookmarkPrefix',  # asked for Bookmark: with no base node
   'System:GroupPrefix',     # asked for Group: with no base node
   'System:InvalidName',     # asked for a bad tag name, most likely an incorrect prefix
   'System:CreateMe',        # page does not exist
   'System:CannotCreateMe',  # page does not exist and it's very unlikely that you can create it
   'System:VersionUnknown',  # version parameter supplied yielded no result
   'System:LoadError',       # generic load error fetching node
   'System:BookmarkNotHash', # asked for Bookmark:... where ... was an URL instead of required MD5 hash
   'System:UserInvalid',     # asked for User:... where ... does not exist in database
   'System:TagInvalid',      # asked for Tag:... where ... does not exist in database
   'System:BookmarkInvalid', # asked for Bookmark:... where ... does not exist in database
   'System:Locked',          # the page you wanted to edit is locked
   );
}

sub generate_node_system_links {
  my ($self, $wiki) = @_;
  return (content => join('',
			  "= System-Used Pages =\n",
			  $self->optimized_cheat_on_bullet_list_of_pagelinks(
			    map { "    * pagelink=$_=\n" }
			    $self->system_links)));
}

sub system_redirect_for_no_content {
  my ($self, $version, $current_version, $can_edit) = @_;
  my $name = eval {
    return 'System:CannotCreateMe' if !$current_version && ($can_edit == -2 || $can_edit == 0);
    return 'System:CreateMe'       if !$current_version;
    return 'System:VersionUnknown' if $version > $current_version;
    return 'System:LoadError';
  };
  return Bibliotech::Component::Wiki::NodeName->new($name);
}

sub content_for_new_page {
  my ($self, $wiki, $node) = @_;
  my $phrase = $self->main_heading_calc($node);
  $phrase =~ s/^.*?: ?//;
  return "= $phrase =\n";
}

sub version_counter {
  my ($self, $node, $version) = @_;

  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $cgi    	 = $bibliotech->cgi;

  my $o = 'Version '.$version;

  if ($version > 1) {
    my $last = $version - 1;
    $o .= ' '.$cgi->a({href => "${location}wiki/$node?action=diff&base=$last"}, 'Changes');
  }

  $o .= ' ('.$cgi->a({href => "${location}wiki/$node"}, 'Current');
  $o .= ' or ' if $version != 1;
  my $count = $version - 1;
  $count = 10 if $count > 10;
  my $start = $version - 1;
  my $end   = $version - $count;
  for (my $older = $start; $older >= $end; $older--) {
    $o .= ' '.$cgi->a({href => "${location}wiki/$node?version=$older"}, $older);
  }
  $o .= ')';

  return $o;
}

sub possible_div_for_system_node {
  my ($self, $node) = @_;
  return if !$node->is_system;
  return if $node->base eq 'Home';  # just hide it for home
  return $self->bibliotech->cgi->div
      ({class => 'wikisystem'},
       'Note: This is a wiki system page. This content is used indirectly.');
}

sub possible_div_for_older_node {
  my ($self, $node, $version, $current_version, $current_link, $rollback_link) = @_;
  return if !$version or !$current_version or $version == $current_version;
  my $cgi = $self->bibliotech->cgi;
  return $cgi->div
      ({class => 'wikisystem'},
       "Note: You are viewing an older version of this page (viewing \#${version};",
       $cgi->a({href => $current_link}, "current \#${current_version}").').',
       $rollback_link ? ' '.$cgi->a({href => $rollback_link}, 'Rollback to #'.$version).'.' : (),
       );
}

sub possible_div_for_edit_overlay {
  my ($self, $edit_link, $node_real) = @_;
  return unless $edit_link;
  return if $node_real eq 'System:CreateMe';
  my $cgi = $self->bibliotech->cgi;
  return $cgi->div({class => 'wikibigedit'}, $cgi->a({href => $edit_link}, 'Edit This Page'));
}

sub possible_div_for_referent {
  my ($self, $referent) = @_;
  return unless defined $referent;
  my $bibliotech = $self->bibliotech;
  return $referent->visit_link($bibliotech, 'wikireferent') if $referent->can('visit_link');
  return $bibliotech->cgi->div({class => 'wikireferent'},
			       'Visit the ',
			       $bibliotech->sitename,
			       'page for the',
			       $referent->noun,
			       $referent->link($bibliotech, undef, 'href_search_global', undef, 1).'.'
			       );
}

sub print_page {
  my ($self, $options) = @_;

  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $prefix     = $location.'wiki/';
  my $cgi    	 = $bibliotech->cgi;
  my $node    	 = $options->{node};
  my $node_real	 = $options->{node_real};
  my $content 	 = $options->{content};
  my $version 	 = $options->{version};
  my $is_current = $options->{is_current};
  my $current    = $options->{current};
  my $updated 	 = $options->{updated};
  my $author 	 = $options->{author};
  my $author_a   = $options->{author_a};
  my $comment 	 = $options->{comment};
  my $homelink   = $prefix;
  my $listlink   = $prefix.'Generate:PageList';
  my $chgslink   = $prefix.'Generate:RecentChanges';
  my $can_edit   = $options->{can_edit};
  my $currlink   = $prefix.$node;
  my $editlink   = $can_edit == 1 || $node !~ /:/ ? $currlink.'?action=edit' : undef;
  my $rolllink   = $editlink ? "${editlink}&version=${version}&comment=Rollback+to+version+${version}" : undef;
  my $histlink   = $editlink ? "${prefix}Generate:History_$node" : undef;
  my $is_admin   = $options->{is_admin};
  my $linklink   = $is_admin ? "${prefix}Generate:SystemLinks" : undef;
  my $referent   = $options->{referent};

  return Bibliotech::Page::HTML_Content->simple
      ([$self->possible_div_for_system_node($node),
	$self->possible_div_for_older_node($node, $version, $current, $currlink, $rolllink),
	$cgi->div({class => 'wikiwrapper'},
		  $self->possible_div_for_edit_overlay($editlink, $node_real),
		  $cgi->div({class => 'wikibody'}, $content),
		  ),
	$cgi->div({class => 'wikifooter'},
		  $cgi->div({class => 'wikicontrols'},
			    join(' | ',
				 $editlink ? $cgi->a({href => $editlink}, 'Edit Page') : (),
				 $histlink ? $cgi->a({href => $histlink}, 'Page History') : (),
				 $homelink ? $cgi->a({href => $homelink}, 'Wiki Home Page') : (),
				 $chgslink ? $cgi->a({href => $chgslink}, 'Recent Changes') : (),
				 $listlink ? $cgi->a({href => $listlink}, 'Page List') : (),
				 $linklink ? $cgi->a({href => $linklink}, 'System Links') : (),
				 ),
			    ),
		  $cgi->div({class => 'wikiversionline'},
			    join(' | ',
				 $version ? $self->version_counter($node, $version) : (),
				 $updated ? 'Last updated: '.$updated->label_plus_time.
				            (defined $author ? ' by '.$author_a : '').
				            ($comment ? " ($comment)" : '')
				          : (),
				 ) || '&mdash;'
			    ),
		  ),
		]);
}

sub main_heading_calc {
  my ($self, $node, $action) = @_;

  my $base = eval {
    return 'Community Pages: '.$node              if !$node->prefix;
    return 'Community Profiles: '.$node->base     if $node->is_referent_user;
    return 'Community Pages: Tag: '.$node->base   if $node->is_referent_tag;
    return 'Community Pages: Group: '.$node->base if $node->is_referent_group;
    if ($node->is_referent_bookmark) {
      my $bookmark = Bibliotech::Bookmark->new($node->base);
      my $url = defined $bookmark ? $bookmark->url : '(undef)';
      return 'Community Pages: Bookmark: '.$url;
    }
    return 'Wiki: '.$node;
  };
  die $@ if $@;

  return ($action && $action eq 'edit' ? 'Editing ' : '').$base;
}

sub main_heading {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $command    = $bibliotech->command;
  my $cgi        = $bibliotech->cgi;
  my $node       = Bibliotech::Component::Wiki::NodeName->new
                     ($self->cleanparam($command->wiki_path || $cgi->param('node')) || $WIKI_HOME_NODE);
  my $action     = $self->cleanparam($cgi->param('action')) || 'display';
  return $self->main_heading_calc($node, $action);
}

sub print_editform {
  my ($self, $options) = @_;

  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $cgi    	 = $bibliotech->cgi;
  my $node    	 = $options->{node};
  my $content 	 = $options->{content};
  my $checksum 	 = $options->{checksum};
  my $preview 	 = $options->{preview};
  my $updated 	 = $options->{updated};
  my $error 	 = $options->{error};
  my $formaction = "${location}wiki";
  my $formname   = 'wiki';
  my $main       = 1;

  my $o = $cgi->start_div({class => 'wikibody'});

  $o .= $cgi->h1($self->main_heading);

  $o .= $cgi->start_form(-method => 'POST',
			 -action => $formaction,
			 -name   => $formname);

  $o .= $cgi->div({class => 'errormsg'}, $error) if $error;

  if ($preview and !$error) {
    my $closejs = "getElementById(\'wikipreviewwrapper\').style.display = \'none\'";
    $o .= $cgi->div({id => 'wikipreviewwrapper'},
		    $cgi->div({class => 'wikipreviewclose'},
			      $cgi->a({href => '#', onclick => $closejs}, 'Close preview')),
		    $cgi->h2({class => 'wikipreviewtitle'}, 'Preview'),
		    $cgi->div({class => 'wikipreview'}, $cgi->div({class => 'wikibody'}, $preview)),
		    );
  }

  $o .= $cgi->textarea(-id      => 'wikicontentbox',
		       -class   => 'textareactl',
		       -name    => 'content',
		       -default => $content,
		       -rows    => 40,
		       -columns => 80,
		       );

  $o .= $cgi->br;

  $o .= 'Note about your change: '.$cgi->textfield(-id        => 'wikicommentbox',
						   -name      => 'comment',
						   -size      => 55,
						   -maxlength => 100);

  $o .= $cgi->br;

  $o .= $cgi->submit(-accesskey => 's',
		     -id    => 'savebutton',
		     -class => 'buttonctl',
		     -name  => 'button',
		     -value => 'Save');

  $o .= $cgi->submit(-accesskey => 'p',
		     -id    => 'previewbutton',
		     -class => 'buttonctl',
		     -name  => 'button',
		     -value => 'Preview');

  $o .= $cgi->submit(-accesskey => 'c',
		     -id    => 'cancelbutton',
		     -class => 'buttonctl',
		     -name  => 'button',
		     -value => 'Cancel');

  $o .= $cgi->hidden('node' => $node);
  $o .= $cgi->hidden('checksum' => $checksum);
  $cgi->param(action => 'afteredit');  # override edit
  $o .= $cgi->hidden('action');

  $o .= $cgi->end_form;

  $o .= $cgi->end_div;

  my $javascript_first_empty = $self->firstempty($cgi, $formname, qw/content/);

  return new Bibliotech::Page::HTML_Content ({html_parts => {main => $o},
					      javascript_onload => ($main ? $javascript_first_empty : undef)});
}

sub print_diff {
  my ($self, $options) = @_;

  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $cgi        = $bibliotech->cgi;
  my $node    	 = $options->{node};
  my $wiki    	 = $options->{wiki};
  my $left_version  = $options->{left_version};
  my $right_version = $options->{right_version};

  my $plugin = Wiki::Toolkit::Plugin::Diff->new;
  $wiki->register_plugin(plugin => $plugin);   # called before any node reads
  my %diff = $plugin->differences(node          => "$node",
				  left_version  => $left_version,
				  right_version => $right_version,
				  );

  my $diffrow = sub {
    my $diff  = shift;
    my $left  = $diff->{left};
    my $right = $diff->{right};
    if ($left =~ /^== Line \d+ ==/ or $right =~ /^== Line \d+ ==/) {
      $left   =~ /^== Line (\d+) ==/;
      my $leftline  = $1 + 1;
      $right  =~ /^== Line (\d+) ==/;
      my $rightline = $1 + 1;
      my $leftstr  = $leftline  ? 'Line '.$leftline  : '&nbsp;';
      my $rightstr = $rightline ? 'Line '.$rightline : '&nbsp;';
      return $cgi->Tr($cgi->td({class => 'diffcell diffhead diff1head'}, $leftstr),
		      $cgi->td({class => 'diffcell diffhead diff2head'}, $rightstr));
    }
    return $cgi->Tr($cgi->td({class => 'diffcell diffdata diff1data'}, $left  || '&nbsp;'),
		    $cgi->td({class => 'diffcell diffdata diff2data'}, $right || '&nbsp;'));
  };

  return Bibliotech::Page::HTML_Content->simple
      ([$cgi->div({class => 'wikibody'},
		  $cgi->h1("Differences between $node \#$left_version and \#$right_version"),
		  $cgi->table({class => 'wikidifftable'}, map { $diffrow->($_) } @{$diff{diff}}))]);
}

sub command_is_for_referent_with_wiki_page {
  my $command    = shift or die 'no command object';
  my $bibliotech = shift or die 'no bibliotech object';
  my $referent = $command->referent_if_one_filter_used_only_single or return;
  my $wiki = Bibliotech::Component::Wiki->new({bibliotech => $bibliotech});
  return wantarray ? ($referent,
		      $wiki->wiki_node_name_for_object($referent),
		      $wiki->exists_wiki_page_for_object($referent) ? 1 : 0)
                   :  $wiki->exists_wiki_page_for_object($referent);
}

package Bibliotech::Component::Wiki::NodeName;
use overload '""' => 'node', fallback => 1;
use Encode qw/decode_utf8/;

sub new {
  my ($class, $node_str_or_obj) = @_;
  return $node_str_or_obj if UNIVERSAL::isa($node_str_or_obj, 'Bibliotech::Component::Wiki::NodeName');
  my $node_str = "$node_str_or_obj";
  my $node     = decode_utf8($node_str) || $node_str;
  my $valid    = $node =~ /^((Generate):)([\w: \-]*)$/ ||
                 $node =~ /^((System|User|Bookmark|Tag|Group):)?([\w \-]*)$/;
  my ($nodeprefix, $basenode) = ($2, $3);
  return bless [$node, $nodeprefix, $basenode, $valid], ref $class || $class;
}

sub clone {
  my $self = shift;
  return bless [@{$self}], ref $self;
}

sub node {
  shift->[0];
}

sub prefix {
  shift->[1];
}

sub base {
  shift->[2];
}

sub is_valid {
  shift->[3];
}

sub is_generate {
  shift->prefix eq 'Generate';
}

sub is_system {
  shift->prefix eq 'System';
}

sub is_generate_or_system {
  shift->prefix =~ /^(?:Generate|System)$/;
}

sub is_referent {
  shift->prefix =~ /^(?:User|Bookmark|Tag|Group)$/;
}

sub is_referent_bookmark {
  shift->prefix eq 'Bookmark';
}

sub is_referent_user {
  shift->prefix eq 'User';
}

sub is_referent_tag {
  shift->prefix eq 'Tag';
}

sub is_referent_group {
  shift->prefix eq 'Group';
}

package Bibliotech::Wiki::CGI::Formatter;
use base ('Wiki::Toolkit::Formatter::Default', 'Class::Accessor::Fast');
use Parse::RecDescent;
use Bibliotech::DBI;
use HTML::Entities;
use Encode qw/decode_utf8 encode_utf8 is_utf8/;

__PACKAGE__->mk_accessors(qw/bibliotech prefix node_exists_callback trace/);

our $grammar = <<'EOG';

# bold, italic, and highlighted auto-reject if the immediate concern
# is the same type of production this avoids some confusion when it
# comes to disambiguating ** from * and so on this is why they have
# e.g. 'bold' and 'bold_inner' productions
bold_inner              : <rulevar: local $word_avoid = 'bold'>
                        | '*' segment '*'
                          { "<b>$item[2]</b>" }
bold                    : <reject: $word_avoid eq 'bold'> bold_inner

italic_inner            : <rulevar: local $word_avoid = 'italic'>
                        | "''" segment "''"
                          { "<i>$item[2]</i>" }
italic                  : <reject: $word_avoid eq 'italic'> italic_inner

highlighted_inner       : <rulevar: local $word_avoid = 'highlighted'>
                        | '**' segment '**'
                          { "<span class=\"wikihighlight\">$item[2]</span>" }
highlighted             : <reject: $word_avoid eq 'highlighted'> highlighted_inner

# many of the conditional <reject> clauses are merely speed
# optimizations, including this one in 'styled_segment'
styled_segment_inner    : highlighted | bold | italic
styled_segment          : <reject: $text !~ /^[\*\']/ > styled_segment_inner

escaped_bold            : <rulevar: local $word_avoid = 'escaped'>
                        | '*' segment "\\" '*'
                          { "*$item[2]*" }
escaped_italic          : <rulevar: local $word_avoid = 'escaped'>
                        | "''" segment "\\" "''"
                          { my $e = HTML::Entities::encode_entities($item[1]);
			    "$e$item[2]$e";
			  }
escaped_highlighted     : <rulevar: local $word_avoid = 'escaped'>
                        | '**' segment "\\" '**'
                          { "**$item[2]**" }
escaped_styled_segment_2: escaped_highlighted | escaped_bold | escaped_italic
escaped_styled_segment  : <reject: $text !~ /^[\*\']/ > escaped_styled_segment_2

# $word_avoid is a local variable recursively applicable that tells
# the code what characters to avoid to prevent gobbling the terminator
# of the current construct - see the 'word' production
word                   	: <matchrule:word_${word_avoid}>
word_                  	: /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-\"=+\*\'\|]+/
word_escaped          	: /[\w\.,!:;\#\/\$\%\^\&\?\@\(\)<>\-\"=+\*\'\|]+/
word_bold              	: /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-\"=+\'\|]+/
word_highlighted       	: /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-\"=+\'\|]+/
word_wikilink_name     	: /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-=+\*\'\|]+/
word_table_cell        	: /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-\"=+\*\']+/
# you can grab an equals as long as the word doesn't go to the end of the line, otherwise, back off it
word_heading           	: /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-\"=+\*\'\|]+/ ...!/ *\n/
                       	  { $item[1] }
                       	| /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-\"+\*\'\|]+/
# italic is looking for two consecutive single quotes only so allow lone single quotes to pass
word_italic             : /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-\"=+\*\'\|]+/ <reject: $item[1] =~ /\'\'/>
                          { $item[1] }
                        | /[\w\.,!:;\#\\\/\$\%\^\&\?\@\(\)<>\-\"=+\*\|]+/

# call this production to get back a plain or encoded word
word_encoded            : word
                          { $item[1] =~ /^[\w\.,]+$/ ? $item[1] :
				($item[1] =~ /&\w+;/ ? $item[1] :  # not perfect*
				 HTML::Entities::encode_entities($item[1]))
			  }
# * we are skipping encoding if it appears the word already has
# entities, which would make it seem that the author has already
# escaped for us - not a perfect assumption but we can't have this
# being too slow

# please correspond 'node' to Bibliotech::Parser grammar production 'wiki_path'
node                   	: /[\w:\- ]+/
node_without_space     	: /[\w:\-]+/
quoted_node            	: '"' node '"'
                       	  { $item[2] }

entity_type            	: /(User|Bookmark|Tag|Group)/
node_prefix            	: /(User|Bookmark|Tag|Group|Generate|System)/

wikiword_link          	: wikiword
                       	  { $thisparser->{wikilink}->($item[1]) }
#wikiword               	: /(?:[A-Z][a-z0-9][\w:\-]+){2,}/
wikiword               	: /(?:[[:upper:]][[:lower:][:digit][\w:\-]+){2,}/
prefixed_wikiword_link 	: prefixed_wikiword
                       	  { $thisparser->{wikilink}->($item[1]) }
prefixed_wikiword      	: node_prefix ':' prefixed_wikiword_node
                       	  { join('', @item[1..3]) }
prefixed_wikiword_node 	: node_without_space | quoted_node

# a whole special setup to accommodate [Tag:blah blah|booya]
prefixed_wikiword_link_with_spaces : prefixed_wikiword_with_spaces
                             	     { $thisparser->{wikilink}->($item[1]) }
prefixed_wikiword_with_spaces      : node_prefix ':' node
                       	             { join('', @item[1..3]) }

implicit_link           : <reject: $text !~ /^[A-Z]/ > implicit_link_inner
implicit_link_inner     : prefixed_wikiword_link | wikiword_link

explicit_link 	       	: '[' explicit_link_inner ']'
              	       	  { $item[2] }
explicit_link_inner    	: url_or_local / ?\| ?/ explicit_link_name   #/(emacs font-lock)
                       	  { join('', ('<a ',
				      $item[1] =~ /^[a-z]{1,8}:/ &&
				      $item[1] !~ /^mailto:/ ? 'rel="nofollow" ' : '',
				      "href=\"$item[1]\">$item[3]</a>")) }
                       	| explicit_link                         # redundant brackets: [[http://...]]
                       	| implicit_link ...!/ ?\|/ ...!'?'      # superfluous brackets: [WikiWord]
                       	  { $item[1] }
                       	| url_or_local
                       	  { join('', ('<a ',
				      $item[1] =~ /^[a-z]{1,8}:/ &&
				      $item[1] !~ /^mailto:/? 'rel="nofollow" ' : '',
				      "href=\"$item[1]\">$item[1]</a>")) }
explicit_link_name     	: embeddable_token_stream

url_or_local 	       	: url
             	       	| local_url
             	       	  { $thisparser->{wikihref}->($item[1]) }
                        | prefixed_wikiword_link_with_spaces
local_url 	       	: node node_params(?)
          	       	  { join('', $item[1], @{$item[2]}) }
                        | /[\/\#][^|\]]*[^|\] ]/
url                    	: /[a-z]{1,8}:[^|\]]*[^|\] ]/
node_params            	: /\?[\w:=%&;]+/

easy_wikilink 	       	: 'pagelink=' <commit> node '='
         	       	  { $thisparser->{wikilink}->($item[3], undef, undef, undef, 1) }
wikilink 	       	: 'wikilink=' <commit> node wikilink_version(?) wikilink_base(?) '=' wikilink_name(?)
         	       	  { $thisparser->{wikilink}->($item[3], $item[4]->[0], $item[5]->[0], $item[7]->[0], 0) }
wikilink_version       	: '#' /\d+/
wikilink_base          	: '##' /\d+/
wikilink_name 	       	: <rulevar: local $word_avoid = 'wikilink_name'>
              	       	| '"' embeddable_token_stream '"'
              	       	  { $item[2] }

biblink 	       	: '@' /[>*]/ entity_type '(' <commit> entity_label ')'
        	       	  { $thisparser->{biblink}->($item[2], $item[3], $item[6]) }
entity_label           	: /[^\)]+/

macro 		       	: '{' macro_inner '}'
                       	  { $item[2] }
macro_inner            	: height_macro_inner | rss_macro_inner | contents_macro_inner
                        | literal_macro_inner | plain_macro_inner
height_macro_inner     	: '^' /\d+/
                       	  { "<div style=\"height: $item[2]px\"></div>" }
rss_macro_inner        	: /[<>]?/ 'RSS'
                       	  { $thisparser->{rssicon}->($item[1]) }
contents_macro_inner    : 'TOC'
                          { '{:::TOC:::}' }  # handle in post-processing
literal_macro           : '{' literal_macro_inner '}'
                       	  { $item[2] }
literal_macro_inner     : 'LITERAL:' /[^<>]*?(?=})(?<!\\)/
                          { my $x = $item[2]; $x =~ s/\\}/}/g; $x; }
plain_macro             : '{' plain_macro_inner '}'
                       	  { $item[2] }
plain_macro_inner       : 'PLAIN:' /.*?(?=})(?<!\\)/
                          { my $x = $item[2]; $x =~ s/\\}/}/g; HTML::Entities::encode_entities($x); }

image 		       	: /(http:\/\/|\/)/ /[\w:\/\\\-\.,;?&=]+\.(?:gif|jpg|jpeg|png)/ / ?/ image_options(?)
      		       	  { $thisparser->{wikiimg}->($item[1].$item[2], $item[4]->[0]) }
image_options 	       	: '(' /[^\)]+/ ')'
              	       	  { $item[2] }

embeddable_token_stream : spacing(?) <leftop: embeddable_token spacing embeddable_token > spacing(?)
                          { join('', @{$item[1]}, @{$item[2]}, @{$item[3]}) }
embeddable_token        : styled_segment | word_encoded | literal_macro | plain_macro

# 'segment' is the main source of recursion to support constructs
# inside constructs
segment 		: token_stream / */
        		  { $item[1].($item[2]||'') }

# we care about, and return, the spacing here
token_stream 		: spacing(?) <leftop: token spacing token >
             		  { join('', @{$item[1]}, @{$item[2]}) }

# 'quick_tokens' will actually give you more than one, but 'token'
# bubbles up to a context which is interested in the whitespace
# between tokens anyway (see 'token_stream') so it's ok
token                   : quick_tokens
                        | explicit_link | implicit_link | easy_wikilink | wikilink
                        | escaped_token
                        | image | macro | biblink | embeddable_token

escaped_token           : "\\" escapable_part
escapable_part          : "\\" ...escapable_part
                          { $item[1] }
                        | '['
                        | ']'
                        | 'pagelink='
                        | 'wikilink='
                        | 'http:'
                        | '/'
                        | '{'
                        | '}'
                        | '@>'
                          { HTML::Entities::encode_entities($item[1]) }
                        | '@*'
                        | prefixed_wikiword
                        | wikiword
                        | escaped_styled_segment

# the 'quick_tokens' production tries to grab long strings of boring
# characters, avoiding constructs that would need the other rules - a
# speed optimization
quick_tokens            : /([\w\.,;()\-]([a-z0-9\.,;()\-]*|[A-Z]+)(\b| ) *)*[\w\.,;()\-]([a-z0-9\.,;()\-]*|[A-Z]+)((?= )|(?<=\()|$)(?!:)/

# separate production so that 'token_stream' can capture it in <leftop>
spacing 	        : / +/
        	        | { '' } # nothing

# the 'heading' production has a first stab that is faster than
# relying on the formal 'heading_line'
heading 	       	: <skip:''> /^(={1,4}) [\w\-\', ]+ \1\n+/ <reject: $item[2] =~ /(?:[^ ][A-Z]|\'\')/ >
      	       	          { my $heading = $item[2];
			    $heading =~ /^(={1,4})/;
			    my $level = length($1);
			    $heading =~ s/^=+ //;
			    $heading =~ s/ =+\n+\z//m;
			    $heading =~ s/\'/\&\#39;/g;  # production regex is weak enough that this is fine
			    my $anchor = 'hn'.@{$thisparser->{for_toc}};
			    push @{$thisparser->{for_toc}}, [$level, $anchor, $heading];
			    "<a name=\"$anchor\"></a><h$level>$heading</h$level>";
			  }
              	       	| heading_line
heading_line 		: <rulevar: local $word_avoid = 'heading'>
        		| <skip:''> /^={1,4}/ / +/ <commit> token_stream / +$item[2] *\n+/
        		  { my $level = length($item[2]);
			    my $heading = $item[5];
			    my $anchor = 'hn'.@{$thisparser->{for_toc}};
			    push @{$thisparser->{for_toc}}, [$level, $anchor, $heading];
			    "<a name=\"$anchor\"></a><h$level>$heading</h$level>";
			  }

paragraph 		: <reject: $text =~ /^(?:=|\||----|    |\t|\n)/> paragraph_line(s / *\n/) / *\n+/
          		  { '<p>'.join('<br />', @{$item[2]}).'</p>' }
paragraph_line          : <reject: $text =~ /^(?:=|\||----|    |\t|\n)/> <skip:''> token_stream

rule                    : /----+ *\n+/
                          { '<hr />' }

quote 			: quote_line(s /\n/) /\n+/
      			  { '<pre><code>'.
				HTML::Entities::encode_entities(join("\n", @{$item[1]})).
				'</code></pre>'
			  }
quote_line 		: /^(    |\t)/ /.*/
           		  { $item[1] eq "\t" ? '    '.$item[2] : $item[2] }

bullet_list 		: <reject: $text !~ /^(    |\t) *\* */> bullet_line(s /\n/)   #/(emacs font-lock)
            		  { "<ul>\n".join('', @{$item[2]}).'</ul>' }
bullet_line 		: <rulevar: local $list_indent = defined $list_indent ? $list_indent.' ' : ''>
            		| /^(    |\t)$list_indent\* */ segment
            		  { '<li>'.($item[1] =~ /^\t/ ? '    '.$item[2] : $item[2])."</li>\n" }
            		| <reject: do { length($list_indent) > 4 } > bullet_list { $item[2]."\n" }
            		| <reject: do { length($list_indent) > 4 } > number_list { $item[2]."\n" }

number_list 		: <reject: $text !~ /^(    |\t) *(\d+|\#|[AaIi])\. */> number_line(s /\n/)   #/(emacs font-lock)
            		  { "<ol>\n".join('', @{$item[2]}).'</ol>' }
number_line 		: <rulevar: local $list_indent = defined $list_indent ? $list_indent.' ' : ''>
            		| /^(    |\t)$list_indent(\d+|\#|[AaIi])\. */ segment
            		  { # construct attributes on the <li> that match the calling construct
			    my ($moniker) = $item[1] =~ /(\S+)\. $/;
			    my $value = ($moniker =~ /^\d+$/    ? $moniker : undef);
			    my $type  = ($moniker =~ /^[AaIi]$/ ? $moniker : undef);
			    '<li'.($type ? " type=\"$type\"" : '').($value ? " value=\"$value\"" : '').'>'.
				($item[1] =~ /^\t/ ? '    '.$item[2] : $item[2]).
				"</li>\n"
			  }
	    		| <reject: do { length($list_indent) > 4 } > number_list { $item[2]."\n" }
            		| <reject: do { length($list_indent) > 4 } > bullet_list { $item[2]."\n" }

table 			: <reject: $text !~ /^\|/ > table_line(s /\n/) /\n+/
      			  { $thisparser->{maketable}->(join("\n", @{$item[2]})) }
table_line 		: <rulevar: local $word_avoid = 'table_cell'>
           		| <skip:''> /^\|/ table_cell(s)
           		  { join('', '|', @{$item[3]}) }
table_cell 		: segment(?) '|'
           		  { join('', @{$item[1]}, '|') }

blank                   : / *\n+/
                          { "\n" }

# this is only allowed for Generate: prefix nodes, checked separately.
verbatim                : '!FASTHTML:{' /[^}]*/ '}{' /[^}]*/ '}'
                          { $item[4] }

# the production of last resort, just to keep things moving
# just spit out the remainder of the line in a <p> tag all-escaped
error 			: /.+/
      			  { '<p class="wikiparsefail"><!-- parser failed: -->'.
				HTML::Entities::encode_entities($item[1]).
				'<!-- end --></p>'
			  }

block                   : verbatim | paragraph | heading | bullet_list | number_list | quote | rule | table | blank | error

wikitext 		: <skip:''> block(s)
             		  { join("\n", grep($_ ne "\n", @{$item[2]})) }
EOG

our $PARSER = Parse::RecDescent->new($grammar);

sub wikihref {
  my ($self, $name, $version, $base, $edit_flag) = @_;
  return $name if $name =~ m|[/\#]|;  # bail out of local or anchor links, that's not a wikiword
  my $href = $self->prefix.$name;
  return $href unless $version || $base || $edit_flag;
  $href .= '?';
  return $href.'action=edit' if $edit_flag;
  if ($base) {
    $href .= 'action=diff&base='.$base;
    $href .= '&' if $version;
  }
  $href .= 'version='.$version if $version;
  return $href;
}

sub wikiname {
  my ($self, $name, $version, $base, $edit_flag) = @_;
  return $name if $edit_flag;
  return $name unless $version || $base;
  if ($base) {
    $name .= " \#$base -";
    $name .= 'Current' unless $version;
  }
  $name .= ' #'.$version if $version;
  return $name;
}

sub wikilink {
  my ($self, $node_cooked, $version, $base, $custom_name, $guaranteed_exists, $cgi) = @_;

  $cgi = $self->bibliotech->cgi unless defined $cgi;  # so $self can be a classname instead of an object

  # remove UTF8 escaping used by format() to get around
  # Parse::RecDescent's inability to parse through UTF8
  # (although apparently creating it is ok)
  (my $node = $node_cooked) =~ s/-UTF8:char(\d+)-/chr($1)/ge;

  my $exists = $guaranteed_exists || do { my $callback = $self->node_exists_callback;
					  defined $callback ? $callback->($node) : 0; };
  my $text   = $custom_name || $self->wikiname($node, $version, $base, !$exists);
  my $href   =                 $self->wikihref($node, $version, $base, !$exists);

  return $cgi->a({href => $href, class => 'wikilink wikiexist'   }, $text)
      if $exists;
  return $cgi->a({href => $href, class => 'wikilink wikinotexist'}, $text).
	 $cgi->span({class => 'wikidunno'}, '?');
}

sub biblink {
  my ($self, $output, $type, $id) = @_;
  my $bibliotech = $self->bibliotech;
  my $cgi = $bibliotech->cgi;
  my $entity = Bibliotech::DBI::class_for_name($type)->new($id)
      or return $cgi->span({class => 'wikispoterror'}, 'unknown entity');
  return $entity->html_content($bibliotech, 'wiki', 1, 1)                   if $output eq '*';
  return $entity->link($bibliotech, 'wiki', 'href_search_global', undef, 1) if $output eq '>';
  return $entity->id;
}

sub maketable {
  my $self = shift;
  my $fmt = shift;
  $fmt =~ s/\r//g;
  $fmt =~ s!<br />!!g;
  my @lines = split(/\n/, $fmt);
  my @rows = map {
    s/^\|//;
    s/\|\s*$//;
    my @cells = split(/\|/, "$_|x");  # perl split will delete trailing empties, prevent with fake entry
    pop @cells;                       # ...and pop off fake entry
    [map {
      my ($ls, $bold, $celltext, undef, $rs) = /^(\s*)((?:<b>)?)(.*?)((?:<\/b>)?)(\s*)$/;
      my $method = $bold ? 'th' : 'td';
      my $align = eval { my $lls = length($ls || '');
			 my $lrs = length($rs || '');
			 return 'right' if $lls > $lrs;
			 return 'left'  if $lls < $lrs;
			 return 'center';
			 };
      [$method, {align => $align}, $celltext];
    } @cells];
  } @lines;
  for (my $i = 0; $i <= $#rows; $i++) {
    for (my $j = 0; $j <= $#{$rows[$i]}; $j++) {
      if ($rows[$i]->[$j]->[2] eq '^') {
	my $k = $i;
	while ($k >= 0 && $rows[$k]->[$j]->[2] eq '^') {
	  $k--;
	}
	if ($k >= 0) {
	  $rows[$i]->[$j]->[2] = undef;
	  $rows[$k]->[$j]->[1]->{rowspan} ||= 1;
	  $rows[$k]->[$j]->[1]->{rowspan}++;
	}
      }
      elsif ($rows[$i]->[$j]->[2] eq '') {
	my $l = $j;
	while ($l >= 0 && $rows[$i]->[$l]->[2] eq '') {
	  $l--;
	}
	if ($l >= 0) {
	  $rows[$i]->[$j]->[2] = undef;
	  $rows[$i]->[$l]->[1]->{colspan} ||= 1;
	  $rows[$i]->[$l]->[1]->{colspan}++;
	}
      }
    }
  }
  my $cgi = $self->bibliotech->cgi;
  return $cgi->table
      ({class => 'wikitable'},
       map {
	 $cgi->Tr({class => 'wikitablerow '.(($_+1) % 2 == 0 ? 'wikitableevenrow' : 'wikitableoddrow')},
		  map {
		    my ($method, $attributes, $celltext) = @{$_};
		    defined $celltext
			? $cgi->$method({class => 'wikitablecell', %{$attributes||{}}},
					$celltext)
			: ();
		  } @{$rows[$_]});
       } (0 .. $#rows));
}

sub rssicon {
  my $self        = shift;
  my $directional = shift;
  my $bibliotech  = $self->bibliotech;
  my $cgi         = $bibliotech->cgi;

  my $decode_directional = sub {
    my $symbol = shift;
    return 'left'  if $symbol eq '<';
    return 'right' if $symbol eq '>';
    return '';
  };

  return $cgi->a({href => $bibliotech->command->rss_href($bibliotech),
		  class => 'rsslink'.$decode_directional->($directional)},
		 $cgi->img({src => $bibliotech->location.'rss_button.gif', border => 0}));
}

sub wikiimg {
  my ($self, $src, $attributes) = @_;

  my $bibliotech  = $self->bibliotech;
  my $cgi         = $bibliotech->cgi;
  my $location    = $bibliotech->location;

  return $cgi->span({class => 'wikispoterror'}, 'image not local') unless $src =~ /^(?:\Q$location\E|\.\.|\/)/;
  return $cgi->span({class => 'wikispoterror'}, 'bad attributes')  if $attributes =~ /(url|href|src|http)/i;

  my $img = $cgi->img({src => $src, border => 0});
  $img =~ s/<img /<img $attributes / if $attributes;
  return $img;
}

sub parse {
  my ($self, $content) = @_;
  $::RD_HINT = $::RD_TRACE = 1 if $self->trace;
  my $prd = $PARSER;
  defined $prd && UNIVERSAL::isa($prd, 'Parse::RecDescent') or die 'no parser object';
  $prd->{cgi}       = $self->bibliotech->cgi;
  $prd->{wikihref}  = sub { $self->wikihref(@_)  };
  $prd->{wikilink}  = sub { $self->wikilink(@_)  };
  $prd->{biblink}   = sub { $self->biblink(@_)   };
  $prd->{maketable} = sub { $self->maketable(@_) };
  $prd->{rssicon}   = sub { $self->rssicon(@_)   };
  $prd->{wikiimg}   = sub { $self->wikiimg(@_)   };
  $prd->{for_toc}   = [];
  return $prd->wikitext($content);
}

sub format {
  my ($self, $content) = @_;
  $content = decode_utf8($content) || decode_utf8(encode_utf8($content)) || $content unless is_utf8($content);
  $content =~ s/\r\n/\n/g;                                   	     # Win to Unix
  $content =~ s/\r/\n/g;                                     	     # Mac to Unix
  $content =~ s/([^\n])\z/$1\n/m;  	                     	     # append final line ending if necessary
  $content =~ s/([^[:ascii:]])/'-UTF8:char'.ord($1).'-'/ge;  	     # Parse::RecDescent cannot handle utf8
  $content =~ s/\[ ?([a-z]{1,8}:[^|\]]*[^|\] ]) ?\| ?\1 ?\]/[$1]/g;  # speed optimization: [url|url] -> [url]
  my $cooked = $self->parse($content);
  my $prd = $PARSER;
  $cooked =~ s/{:::TOC:::}/my $toc = $prd->{for_toc}; $prd->{for_toc} = []; $self->format_contents($toc)/eg;
  $cooked =~ s/-UTF8:char(\d+)-/chr($1)/ge;                          # quoted utf8 characters to originals
  return _format_div($cooked);
}

sub _format_div {
  "<div class=\"wikistartdisplay\"></div>\n".shift()."\n<div class=\"wikienddisplay\"></div>\n";
}

sub format_contents {
  my ($self, $list) = @_;
  return '' unless $list and @{$list};
  my $cgi = $self->bibliotech->cgi;
  return $cgi->div({class => 'wikitoc'},
		   $cgi->p('Table of Contents'),
		   $self->parse(join('', map {
		     my ($level, $anchor, $title) = @{$_};
		     my $indent = ' ' x (3 + $level);
		     "$indent* [#$anchor|{LITERAL:$title}]\n";
		   } @{$list}))
		   );
}

package Bibliotech::Component::Wiki::DBI;
use base 'Class::DBI';

__PACKAGE__->connection($WIKI_DBI_CONNECT, $WIKI_DBI_USERNAME, $WIKI_DBI_PASSWORD);

__PACKAGE__->set_sql(last_modified_unix_timestamp => <<'');
SELECT 	 UNIX_TIMESTAMP(MAX(modified))
FROM     node

__PACKAGE__->set_sql(test_node_for_retrieval => <<'');
SELECT 	 name
FROM     node
WHERE  	 name = ?
LIMIT    1

__PACKAGE__->set_sql(list_only_edited_by_username => <<'');
SELECT   m.node_id, n2.name, m.version, (SELECT MAX(n.version) FROM node n WHERE n.id=m.node_id) AS max_version,
         (SELECT COUNT(*) FROM metadata m2 WHERE m2.node_id = m.node_id AND metadata_type = 'username' and metadata_value != ?) as others
FROM     metadata m
         LEFT JOIN node n2 ON (m.node_id=n2.id)
WHERE    m.metadata_type = 'username'
AND      m.metadata_value = ?
HAVING   version = max_version
AND      others = 0

package Bibliotech::Component::Wiki::Change;
# wrapper for hash sent by Wiki::Toolkit::list_recent_changes() for each change
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/change component wiki/);

sub name      	      { shift->change->{name} }
sub version   	      { shift->change->{version} }
sub metadata  	      { shift->change->{metadata} }
sub comment   	      { shift->metadata->{comment}->[0] }
sub username  	      { shift->metadata->{username}->[0] }
sub user      	      { Bibliotech::User->new(shift->username) }
sub host      	      { shift->metadata->{host}->[0] }
sub last_modified_raw { shift->change->{last_modified} }
sub last_modified     { Bibliotech::Date->new(shift->last_modified_raw)->mark_time_zone_from_db->utc }
sub major_change_raw  { shift->metadata->{major_change}->[0] }
sub major_change      { my $mc = shift->major_change_raw; defined $mc ? $mc : 1 }
sub status            { shift->version == 1 ? 'new' : 'updated' }
sub importance        { shift->major_change ? 'major' : 'minor' }
sub username_or_host  { $_[0]->username || $_[0]->host }

sub diff_html {
  my $self    = shift;
  my $version = $self->version;
  return if $version < 2;
  my $diff    = $self->component->print_diff({node 	    => $self->name,
					      wiki 	    => $self->wiki,
					      left_version  => ($version - 1),
					      right_version => $version,
					    });
  return $diff->content;
}

package Wiki::Toolkit::Plugin::Lock;
use strict;
use warnings;
use base 'Wiki::Toolkit::Plugin';

our $plugin_key = 'lock';
our $table = 'p_'.$plugin_key.'_node';  # per docs for read/write tables

sub dbh {
  shift->datastore->dbh;
}

sub has_table {
  my $dbh = shift->dbh;
  my $sth = $dbh->prepare('show tables like ?') or die $dbh->errstr;
  $sth->execute($table) or die $sth->errstr;
  my $has_table = $sth->rows > 0;
  $sth->finish;
  return $has_table;
}

sub create_table {
  my $dbh = shift->dbh;
  my $sql = "create table $table ".
            '(name varchar(200) not null primary key, username varchar(200), expire datetime)';
  $dbh->do($sql) or die $dbh->errstr;
  $dbh->commit unless $dbh->{AutoCommit};
}

sub on_register {
  my $self = shift;
  $self->create_table unless $self->has_table;
  return 1;
}

sub post_write {
  my ($self, %options) = @_;
  $self->unlock_node($options{node}) if $options{node};
  return 1;
}

sub lock_node {
  my ($self, $node, $username, $time_t) = @_;
  $time_t =~ /^(\d+) (SECOND|MINUTE|HOUR)S?$/i or die 'bad time parameter: '.$time_t;
  my $time = "$1 $2";
  my $dbh = $self->dbh;
  my ($exists) = $dbh->selectrow_array("select count(*) from $table where name = ?", undef, $node) or die $dbh->errstr;
  if (!$exists) {
    my $sql = "insert into $table (name, username, expire) values (?, ?, NOW() + INTERVAL $time)";
    my $sth = $dbh->prepare($sql) or die $dbh->errstr;
    $sth->execute($node, $username) or die $sth->errstr;
  }
  else {
    my $sth = $dbh->prepare("update $table set username = ?, expire = NOW() + INTERVAL $time where name = ?") or die $dbh->errstr;
    $sth->execute($username, $node) or die $sth->errstr;
  }
  $dbh->commit unless $dbh->{AutoCommit};
  return 1;
}

sub unlock_node {
  my ($self, $node) = @_;
  my $dbh = $self->dbh;
  $dbh->do("delete from $table where name = ?", undef, $node) or die $dbh->errstr;
  $dbh->commit unless $dbh->{AutoCommit};
  return 1;
}

sub is_locked {
  my ($self, $node) = @_;
  my $dbh = $self->dbh;
  my $sth = $dbh->prepare("select username, expire from $table where name = ? and (expire IS NULL or NOW() <= expire) order by expire desc limit 1") or die $dbh->errstr;
  $sth->execute($node) or die $sth->errstr;
  unless ($sth->rows) {
    $sth->finish;
    return;
  }
  unless (wantarray) {
    $sth->finish;
    return 1;
  }
  my ($username, $expire) = $sth->fetchrow_array;
  $sth->finish;
  return ($username, $expire);
}

sub try_lock {
  my ($self, $node, $username, $time) = @_;
  my ($locked_username, $locked_expire) = $self->is_locked($node);
  if ($locked_username and $locked_username ne $username) {
    return wantarray ? (0, $locked_username, $locked_expire) : 0;
  }
  eval {
    $self->lock_node($node, $username, $time);
  };
  die "try_lock: $@" if $@;
  ($locked_username, $locked_expire) = $self->is_locked($node);
  $locked_username eq $username or die "failed to confirm lock (\'$locked_username\' ne \'$username\')";
  return wantarray ? (1, $locked_username, $locked_expire) : 1;
}

sub try_unlock {
  my ($self, $node, $username) = @_;
  my ($locked_username, $locked_expire) = $self->is_locked($node);
  if ($locked_username and $locked_username ne $username) {
    return wantarray ? (0, $locked_username, $locked_expire) : 0;
  }
  eval {
    $self->unlock_node($node, $username);
  };
  die "try_unlock: $@" if $@;
  ($locked_username, $locked_expire) = $self->is_locked($node);
  !$locked_username or die "failed to confirm unlock (\'$locked_username\')";
  return wantarray ? (1, undef, undef) : 1;
}

1;
__END__
