# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::List class is the true workhorse component where
# most of the meat is. This component draws the lists of objects that are
# returned from the queries initiated by users.

package Bibliotech::Component::List;
use strict;
use base 'Bibliotech::Component';
use Set::Array;
use List::Util qw/min max/;
use Bibliotech::Const;
use Bibliotech::Config;
use Bibliotech::DBI;
use Bibliotech::Util;
use Bibliotech::Component::Wiki;
use Bibliotech::Profile;
use Data::Dumper;
use Carp qw/cluck/;

(our $LINKED_RECENT_INTERVAL = Bibliotech::Config->get('LINKED_RECENT_INTERVAL') || '24 HOUR') =~ s|^(\d+)$|$1 HOUR|;
our $LINKED_MAX_USER_BOOKMARKS = Bibliotech::Config->get('LINKED_MAX_USER_BOOKMARKS') || 100;

sub last_updated_basis {
  ('DBI', 'LOGIN', 'USER');
}

sub heading {
  'List';
}

sub heading_dynamic {
  my ($self, $main) = @_;
  my $heading = $main ? $self->bibliotech->command->description($main) : $self->heading;
  #Don't lowercase anymore
  #$heading =~ s/\b((Home|Recent|Popular|Active|User|Tag|Bookmark|Date|Uri|URI|Comment)(\'?s)?)\b/lc $1/ge;
  return $heading;
}

sub list {
  my $self = shift;
  my $bibliotech = $self->bibliotech;
  my $func = $bibliotech->command->page;
  return $bibliotech->query->$func(@_);
}

sub calc_cabinet_set {
  my ($self, $class) = @_;

  my $quick = $Bibliotech::Apache::QUICK{'Bibliotech::Component::List::calc_cabinet_set'}->{$class};
  return $quick if defined $quick;

  my $bibliotech = $self->bibliotech;
  my $command    = $bibliotech->command;
  my $table      = $class->table;
  my $plural     = $table.'s';
  my $unique     = $class->unique;

  my $cabinet_set;
  if ($table =~ /^(user|tag|gang)$/) {
    my $other = $table eq 'user' ? 'tag' : 'user';
    $other = 'gang' if !$command->$other and $command->gang;
    my $flun = $other.'_flun';
    my @filter = $command->$flun;
    if (@filter) {
      my $otherclass = 'Bibliotech::'.ucfirst($other);
      my ($memcache, $cache_key, $last_updated);
      if ($other eq 'user' and $table eq 'tag' and @filter == 1 and $filter[0]) {
	$memcache = $bibliotech->memcache;
	if (my $viewed_user = $filter[0]->obj) {
	  my $viewed_user_id = $viewed_user->user_id;
	  my $updated = $viewed_user->updated;
	  $last_updated = $updated->epoch unless $updated->incomplete;
	  $cache_key = Bibliotech::Cache::Key->new($bibliotech,
						   class => ref $self,
						   method => 'cabinet',
						   id => $viewed_user_id,
						   effective => [undef, $viewed_user]);
	  $cabinet_set = $memcache->get_with_last_updated($cache_key, $last_updated, undef, 1);
	}
      }
      unless (defined $cabinet_set) {
	my @cabinet_set_temp;
	my $all_filters_alpha = 1;
	foreach my $obj (grep(defined $_, map($_->obj, @filter))) {
	  my $cabinet_func = $plural.'_alpha';
	  unless ($obj->can($cabinet_func)) {
	    $cabinet_func = $plural;
	    $all_filters_alpha = 0;
	  }
	  push @cabinet_set_temp, $obj->$cabinet_func;
	}
	unless ($all_filters_alpha) {
	  @cabinet_set_temp = sort {lc($a->$unique) cmp lc($b->$unique)} @cabinet_set_temp;
	}
	$cabinet_set = new Bibliotech::DBI::Set (@cabinet_set_temp);
	$cabinet_set->unique;
	$memcache->set_with_last_updated($cache_key, $cabinet_set, $last_updated) if defined $cache_key;
      }
    }
  }

  $cabinet_set = new Bibliotech::DBI::Set unless defined $cabinet_set;

  $Bibliotech::Apache::QUICK{'Bibliotech::Component::List::calc_cabinet_set'}->{$class} = $cabinet_set;
  return $cabinet_set;
}

sub calc_query_set {
  my ($self, $class, $cabinet_set) = @_;

  my $quick = $Bibliotech::Apache::QUICK{'Bibliotech::Component::List::calc_query_set'}->{$class};
  return $quick if defined $quick;

  $cabinet_set = $self->calc_cabinet_set($class) unless defined $cabinet_set;

  my $bibliotech = $self->bibliotech;
  my $command = $bibliotech->command;
  my $table = $class->table;
  my $plural = $table.'s';

  my $query_set;

  my %avoid_dump;
  unless ($command->filters_used) {
    my $time = Bibliotech::DBI->db_Main->selectrow_array('SELECT NOW() - INTERVAL '.$LINKED_RECENT_INTERVAL);
    $avoid_dump{where} = ['ub.created' => {'>=', $time}];
  }
  # note that although you go to the query object there is a limitation on the same field you ask for
  $query_set = $command->$table ? [$bibliotech->query->$plural(all => 1, %avoid_dump)] : new Set::Array;
  bless $query_set, 'Bibliotech::DBI::Set';
  $query_set->difference($cabinet_set);
  $Bibliotech::Apache::QUICK{'Bibliotech::Component::List::calc_query_set'}->{$class} = $query_set;
  return $query_set;
}

sub calc_user_bookmark_ids {
  my ($self, %options) = @_;
  return map($_->user_bookmark_id, $self->bibliotech->query->user_bookmarks(%options));
}

sub calc_linked_set {
  my ($self, $class, $cabinet_set, $query_set, $user_bookmark_ids_ref, $note) = @_;

  my $quick_key = $class.($note ? ",$note" : '');
  my $quick = $Bibliotech::Apache::QUICK{'Bibliotech::Component::List::calc_linked_set'}->{$quick_key};
  return $quick if defined $quick;

  $cabinet_set = $self->calc_cabinet_set($class)             unless defined $cabinet_set;
  $query_set   = $self->calc_query_set($class, $cabinet_set) unless defined $query_set;

  my $table = $class->table;
  my $primary = $class->primary_column;

  my @user_bookmark_ids = $user_bookmark_ids_ref ? @{$user_bookmark_ids_ref} : $self->calc_user_bookmark_ids;

  my $linked_set = do {
    if (@user_bookmark_ids) {
      my $sql_call = 'sql_joined';
      $sql_call .= '_plus_'.$table unless $table eq 'user';
      my $alias = join('', map(substr($_, 0, 1), split(/_/, $table)));
      my $sth = $class->$sql_call(join(', ', map("$alias.$_", $class->_essential)).', COUNT(ub.user_bookmark_id) as sort',
				  'AND ub.user_bookmark_id IN ('.join(',', map('?', @user_bookmark_ids)).')',
				  "GROUP BY $primary", '', 'ORDER BY sort DESC', 'LIMIT 50');
      $sth->execute(@user_bookmark_ids);
      Bibliotech::DBI::Set->new(map { $class->construct($_) } $sth->fetchall_hash);
    }
    else {
      Bibliotech::DBI::Set->new();
    }
  };

  $linked_set->difference($cabinet_set);
  $linked_set->difference($query_set);

  $Bibliotech::Apache::QUICK{'Bibliotech::Component::List::calc_linked_set'}->{$quick_key} = $linked_set;
  return $linked_set;
}

sub calc_related_set {
  my ($self, $class, $cabinet_set, $query_set, $linked_set, $user_bookmark_ids_ref) = @_;

  my $quick = $Bibliotech::Apache::QUICK{'Bibliotech::Component::List::calc_related_set'}->{$class};
  return $quick if defined $quick;

  $cabinet_set = $self->calc_cabinet_set($class)                          unless defined $cabinet_set;
  $query_set   = $self->calc_query_set($class, $cabinet_set)              unless defined $query_set;
  $linked_set  = $self->calc_linked_set($class, $cabinet_set, $query_set) unless defined $linked_set;

  my $table = $class->table;
  my $primary = $class->primary_column;

  my @user_bookmark_ids = $user_bookmark_ids_ref ? @{$user_bookmark_ids_ref} : $self->calc_user_bookmark_ids;

  my $related_set = do {
    if (@user_bookmark_ids) {
      my $sql_call = 'sql_joined';
      $sql_call .= '_plus_'.$table unless $table eq 'user';
      $sql_call .= '_related_'.$table;
      my $sth = $class->$sql_call(join(', ', map("r.$_", $class->_essential)).', COUNT(ub2.user_bookmark_id) as sort',
				  'AND ub.user_bookmark_id IN ('.join(',', map('?', @user_bookmark_ids)).')',
				  "GROUP BY r.$primary", '', 'ORDER BY sort DESC', 'LIMIT 50');
      $sth->execute(@user_bookmark_ids);
      Bibliotech::DBI::Set->new(map { $class->construct($_) } $sth->fetchall_hash);
    }
    else {
      Bibliotech::DBI::Set->new();
    }
  };

  $related_set->difference($cabinet_set);
  $related_set->difference($query_set);
  $related_set->difference($linked_set);

  $Bibliotech::Apache::QUICK{'Bibliotech::Component::List::calc_related_set'}->{$class} = $related_set;
  return $related_set;
}

sub is_tag_linked {
  my ($self, $tag) = @_;
  my @set = $self->bibliotech->query->tags(all => 1,
					   no_freematch => 1,
					   where => ['t5.tag_id' => [$tag->tag_id]]);
  return scalar @set;
}

# works for side bars when main is of type user_bookmark
sub list_multipart_from_user_bookmarks {
  my ($self, $class) = @_;
  my %parts = %{$self->parts||{}};
  my (@final, $cabinet_set, $query_set, $linked_set, $related_set);

  $cabinet_set = $self->calc_cabinet_set($class);
  push @final, Cabinet => @{$cabinet_set} if @{$cabinet_set} and $parts{cabinet};

  if ($parts{query} || $parts{linked} || $parts{related} || $parts{main}) {
    $query_set = $self->calc_query_set($class, $cabinet_set);
    push @final, Query => @{$query_set} if @{$query_set} and $parts{query};

    if ($parts{linked} || $parts{related} || $parts{main}) {
      my @ids = $self->calc_user_bookmark_ids;

      $linked_set = $self->calc_linked_set($class, $cabinet_set, $query_set, \@ids);
      push @final, Linked => @{$linked_set} if @{$linked_set} and $parts{linked};

      if ($parts{related} || $parts{main}) {
	$related_set = $self->calc_related_set($class, $cabinet_set, $query_set, $linked_set, \@ids);
	push @final, Related => @{$related_set} if @{$related_set} and $parts{related};
      }
    }
  }

  return @final;
}

sub plain_content {
  my ($self, $verbose) = @_;
  my @list = $self->list(main => 1) or return wantarray ? () : '';
  my @output = map(scalar $_->plain_content($verbose), @list);
  return wantarray ? @output : join('', map("$_\n", @output));
}

sub txt_content {
  my ($self, $verbose) = @_;
  my @list = $self->list(main => 1) or return wantarray ? () : '';
  my @output = map(scalar $_->txt_content($verbose), @list);
  return wantarray ? @output : join('', map("$_\n", @output));
}

sub tt_content {
  my ($self, $verbose) = @_;
  my @list = $self->list(main => 1) or return '';
  my @output = map(scalar $_->tt_content($verbose), @list);
  return join('', map("$_\n", @output));
}

sub html_content_num_options {
  my ($self) = @_;

  my @choices = (10, 25, 50, 100);

  my $bibliotech = $self->bibliotech;
  my $cgi = $bibliotech->cgi;
  my $location = $bibliotech->location;
  my $command = $bibliotech->command;

  my $current_num = $command->num;
  my $query_count = $bibliotech->query->lastcount;

  # list sub that finds the next highest element of a presorted list of numbers given a target number
  my $next_highest = sub { my $testval = shift; foreach (@_) { return $_ if $testval < $_; } return undef; };
  my $next_highest_choice = $next_highest->($query_count => @choices);
  my @numlinks = map {
    eval {
      return $cgi->span({class => 'current_num'}, $_) if $current_num == $_;
      return $cgi->span({class => 'higher_num'}, $_) if defined $next_highest_choice and $_ > $next_highest_choice;
      return $cgi->a({class => 'possible_num', href => $command->canonical_uri($location, {num => [set => $_]})}, $_);
    };
  } @choices;
  return $cgi->div({ id => 'sort-and-number-bar' },
           $cgi->div({ id => 'sort' }, '&nbsp;'),
           $cgi->div({id => 'number'}, 
             $cgi->span({ class => 'number-label' }, 'Number of bookmarks per page: '), 
             $cgi->div({ id => 'number-buttons' },
               join(' | ', @numlinks)
             )
           )
         );       
}

sub html_content_geoinfo {
  my ($self, $geocount) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $location   = $bibliotech->location;
  my $docroot    = $bibliotech->docroot;
  my $geo_href   = $bibliotech->command->geo_href($bibliotech);

  return $cgi->div({id => 'geoinfo'}, 
		   $cgi->div({class => 'geoinfo_link'},
			     'View in Google Earth:',
			     $cgi->a({href => $geo_href},
				     (-e $docroot.'geo_data.gif'
				        ? $cgi->img({src => $location.'geo_data.gif', alt => 'GEO DATA',
						     border => 0, title => 'Geographical Data'})
				        : 'Geo')),
			     $cgi->a({href => $location.'guide#geodata'},
				     (-e $docroot.'help_button.gif'
				        ? $cgi->img({src => $location.'help_button.gif',
						     border => 0, title => 'What does this mean?', alt => '?'})
				        : '?'))),
		   $cgi->div({class => 'geoinfo_text'},
			     "Geographical data are available for $geocount of these links."));
}

sub html_content_wikiinfo {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $sitename   = $bibliotech->sitename;
  my $command    = $bibliotech->command;
  my ($referent,
      $node,
      $exists)   = Bibliotech::Component::Wiki::command_is_for_referent_with_wiki_page
	             ($command, $bibliotech);
  return unless defined $referent;
  my $cgi        = $bibliotech->cgi;
  my $location   = $bibliotech->location;
  my $docroot    = $bibliotech->docroot;
  my $wiki_href  = "${location}wiki/$node";
  my $wiki_home  = "${location}wiki/";
  my ($prefix)   = $node =~ /^(\w+):/;
  my $noun       = lc $prefix;
  my @link;

  if ($referent->isa('Bibliotech::User')) {
    if ($bibliotech->in_my_library) {
      if ($exists) {
	@link = ('Go to my', $cgi->a({href => $wiki_href}, 'Community Pages Profile').'.');
      }
      else {
	@link = ('Create a', $cgi->a({href => $wiki_href}, 'Profile'),
		 'on the', $cgi->a({href => $wiki_home}, 'Community Pages').'.');
      }
    }
    else {
      if ($exists) {
	@link = ('This user has a', $cgi->a({href => $wiki_href}, 'profile'),
		 'on the', $sitename, $cgi->a({href => $wiki_home}, 'Community Pages').'.');
      }
      else {
	@link = ('This user doesn\'t have a profile on the', $sitename,
		 $cgi->a({href => $wiki_home}, 'Community Pages'), 'yet.');
      }
    }
  }
  elsif ($referent->isa('Bibliotech::Gang')) {
    if ($referent->is_accessible_by_user($bibliotech->user)) {
      if ($exists) {
	@link = ('Go to my', $cgi->a({href => $wiki_href}, 'Community Pages Group Page').'.');
      }
      else {
	@link = ('Create a', $cgi->a({href => $wiki_href}, 'Group Page'),
		 'on the', $sitename, $cgi->a({href => $wiki_home}, 'Community Pages'),
		 'for my group.');
      }
    }
    else {
      if ($exists) {
	@link = ('This group has a', $cgi->a({href => $wiki_href}, 'page'),
		 'on the', $sitename, $cgi->a({href => $wiki_home}, 'Community Pages').'.');
      }
      else {
	@link = ('This group hasn\'t created a page on the', $sitename,
		 $cgi->a({href => $wiki_home}, 'Community Pages'), 'yet.');
      }
    }
  }
  elsif ($referent->isa('Bibliotech::Tag')) {
    if ($exists) {
      @link = ('There is a', $sitename, $cgi->a({href => $wiki_href}, 'Community Page'), 'for this tag.');
    }
    else {
      @link = ('Create a', $sitename, $cgi->a({href => $wiki_href}, 'Community Page'), 'about this tag.');
    }
  }
  elsif ($referent->isa('Bibliotech::Bookmark')) {
    #if ($exists) {
      #@link = ('There is a', $sitename, $cgi->a({href => $wiki_href}, 'Community Page'), 'for this bookmark.');
    #}
    #else {
      #@link = ('Create a', $sitename, $cgi->a({href => $wiki_href}, 'Community Page'), 'about this bookmark.');
    #}
  }
  else {
    if ($exists) {
      @link = ('A',
	       $cgi->a({href => $wiki_href}, 'community page'),
	       'has been established for this', $noun.'.');
    }
  }

  return unless @link;
  return $cgi->div({id => 'wikiinfo'}, 
		   $cgi->div({class => 'wikiinfo_link'},
			     @link,
			     $cgi->a({href => $location.'guide#communitypages'},
				     (-e $docroot.'help_button.gif'
				        ? $cgi->img({src => $location.'help_button.gif',
						     border => 0, title => 'What does this mean?', alt => '?'})
				        : '?'))));
}

# find global tags, users, etc named like your freematch search and provide alternative links
# this is not the place to change freematch results (see Bibliotech::DBI for that)
sub html_content_freematch_notes {
  my ($self, $freematch_obj) = @_;
  my $freematch = "$freematch_obj";

  my $bibliotech = $self->bibliotech;
  my $cgi = $bibliotech->cgi;

  my $make_link = sub {
    my ($obj, $obj_type, $href_type) = @_;
    return $obj->link($bibliotech, 'freematch_'.$obj_type, 'href_search_'.$href_type, undef, 1);
  };

  my $report_my_tag = sub {
    my $user = $bibliotech->user or return undef;
    my $user_id = $user->user_id;
    my ($tag, $tag_users_ref) = @_;
    my @users = $tag_users_ref ? @{$tag_users_ref} : $tag->users;
    return undef unless grep($_->user_id == $user_id, @users);
    return join(' ',
		'the tag',
		$make_link->($tag, 'tag', 'global_user'),
		'that you have used in your library');
  };

  my $report_global_tag = sub {
    my ($tag, $tag_users_ref) = @_;
    my @users = $tag_users_ref ? @{$tag_users_ref} : $tag->users;
    if (my $user = $bibliotech->user) {
      my $user_id = $user->user_id;
      return undef unless grep($_->user_id != $user_id, @users);
    }
    else {
      return undef unless @users;
    }
    return join(' ',
		'the global tag',
		$make_link->($tag, 'tag', 'global'));
  };

  my $report_linked_tag = sub {
    my $tag = shift;
    return undef unless $bibliotech->command->filters_used;
    return undef if $bibliotech->in_my_library;
    return undef unless $self->is_tag_linked($tag);
    return join(' ',
		'the tag',
		$make_link->($tag, 'tag', 'additive_and'),
		'used in this collection');
  };

  my @freematch;
  foreach ('tag', 'user', 'gang') {
    my $class = "Bibliotech::\u$_";
    if (my $obj = $class->new($freematch)) {
      push @freematch, [$_, $obj];
    }
  }  

  my (@pretext, @text);
  foreach my $match (@freematch) {
    my ($type, $obj) = @{$match};
    if ($type eq 'tag') {
      my @users  = $obj->users;
      my $mine   = $report_my_tag->($obj, \@users);
      my $linked = $report_linked_tag->($obj);
      my $global = $report_global_tag->($obj, \@users);
      push @pretext, grep(defined $_, $mine, $linked);
      push @text, grep(defined $_, $global);
    }
    else {
      push @text, join(' ',
		       $obj->noun,
		       $make_link->($obj, $type, 'global'));
    }
  }

  return '' unless @pretext || @text;

  my @note = ('Note: Your search term matches');
  if (@pretext) {
    my $first = shift @pretext;  # only use one, push rest to @text
    push @note, $first.'.';
    push @text, @pretext;
    push @note, 'It also matches' if @text;
  }
  if (@text) {
    push @note, Bibliotech::Util::speech_join(and => @text).'.';
  }
  return $cgi->div({id => 'freematch'}, @note);
}

sub html_content_status_line {
  my ($self) = @_;

  my $bibliotech = $self->bibliotech;
  my $command    = $bibliotech->command;
  my $query      = $bibliotech->query;
  my $cgi        = $bibliotech->cgi;
  my $location   = $bibliotech->location;
  my $start      = $query->start || 0;
  my $num        = $query->num;
  my $max        = $query->lastcount;

  return undef unless $start > 0 or defined $num;

  return html_content_status_line_calc($start, $num, $max,
				       sub {
					 $cgi->escapeHTML(@_);
				       },
				       sub {
					 my $start = shift;
					 $command->canonical_uri($location, {start => [set => $start ? $start : undef]});
				       },
				       sub {
					 my ($href, $text) = @_;
					 $cgi->a({href => $href}, $text);
				       },
				       sub {
					 my ($prevlink, $nextlink, $status) = @_;
					 my $spacing = '&nbsp;' x 4;
					 $cgi->br.$cgi->div({id => 'status'}, $prevlink, $spacing, $status, $spacing, $nextlink);
				       });
}


sub html_content_status_line_calc {
  my ($start, $num, $max, $escape_sub, $canonical_url_sub, $a_tag_sub, $status_sub) = @_;
  return $status_sub->(do {
    my $newstart = max($start - $num, 0);
    my $newnum   = min($num, $start);
    html_content_status_line_next_prev_calc($newstart, $newnum, $start,
					    sub { $escape_sub->('<< Prev '.shift()) },
					    $canonical_url_sub, $a_tag_sub);
  },
  do {
    my $newstart = min($start + $num, $max);
    my $newnum   = min($num, $max - $newstart);
    html_content_status_line_next_prev_calc($newstart, $newnum, $start,
					    sub { $escape_sub->('Next '.shift().' >>') },
					    $canonical_url_sub, $a_tag_sub);
  },
  do {
    my $last  = min($start + $num, $max);
    my $first = $last != 0 ? $start + 1 : 0;
    join(' ', 'Showing entries', $first, 'to', $last, 'of', $max, 'total');
  });
}

sub html_content_status_line_next_prev_calc {
  my ($newstart, $newnum, $start, $text_sub, $canonical_url_sub, $a_tag_sub) = @_;
  my $text = $text_sub->($newnum);
  return $text unless $newstart != $start && $newnum > 0;
  return $a_tag_sub->($canonical_url_sub->($newstart), $text);
}

sub html_content_heading {
  my ($self, $main) = @_;
  die 'specify main as true or false' unless defined $main;

  my $bibliotech      = $self->bibliotech;
  my $command  	      = $bibliotech->command;
  my $cgi      	      = $bibliotech->cgi;
  my $location 	      = $bibliotech->location;
  my $docroot         = $bibliotech->docroot;
  my $heading_dynamic = $self->heading_dynamic($main);
  my $rss_href        = $command->rss_href($bibliotech);
  my $export_href     = $command->export_href($bibliotech);

  return $cgi->div({id => 'mybookmark-title'}, $heading_dynamic) unless $main and $rss_href;

  return $cgi->div({id => 'mybookmark-title'},
		   $cgi->div({id => 'mybookmarkrss'},
			     $cgi->a({href => $export_href},
				     (-e $docroot.'exportlist_button.gif'
				        ? $cgi->img({src => $location.'exportlist_button.gif',
						     alt => 'EXPORT LIST',
						     title => 'Export this list to a local reference manager',
						     class => 'rssicon'})
				        : 'EXPORT')) . ' ' .
			     $cgi->a({href => $rss_href},
				     (-e $docroot.'rss_button.gif'
				        ? $cgi->img({src => $location.'rss_button.gif',
						     alt => 'RSS',
						     title => 'RSS',
						     class => 'rssicon'})
				        : 'RSS')),
			     $cgi->a({href => $location.'guide#rss'},
				     (-e $docroot.'help_button.gif'
				        ? $cgi->img({src => $location.'help_button.gif',
						     alt => '?',
						     title => 'What are these ?',
						     class => 'helpicon'})
				        : '?'))),
		   $cgi->div({id => 'mybookmarktitle'}, $heading_dynamic));
}

sub html_content_memory_scores_javascript {
  my $self              = shift;
  my $memory_scores_ref = shift                 or return undef;
  my @memory_scores     = @{$memory_scores_ref} or return undef;
  my $count             = 0;
  return join('',
	      "// tags is sorted by score and the label is given a number representing score rank\n",
	      'var tags = {',    # sorted by score (usage): label=>score
	      join(', ',
		   map { my $label = $_->[0];
			 $label =~ s/\'/\\\'/g;
			 $count++;
			 "\'$label\':$count";
		       } sort {$b->[1] <=> $a->[1]} @memory_scores
		   ),
	      "};\n",
	      "// tagids is sorted by alpha and the label is given the tag_id number\n",
	      'var tagids = {',  # sorted by alpha: label=>id
	      join(', ',
		   map { my $label = $_->[0];
			 $label =~ s/\'/\\\'/g;
			 my $id = $_->[2];
			 "\'$label\':\'$id\'";
		       } @memory_scores
		   ),
	      "};\n",
	      "\n",
	      html_content_memory_scores_javascript_helpers());
}

sub html_content_memory_scores_javascript_helpers {
  return <<'EOJ';
// global variable to hold currently selected value for tag order
var tag_order = 'alpha';

function usageorder(a, b) {
  return tags[a] - tags[b];
}

function alphaorder(a, b) {
  var al = a.toLowerCase();
  var bl = b.toLowerCase();
  return ((al < bl) ? -1 : ((al > bl) ? 1 : 0));
}

function reorder(orderfunc, filterstr) {
  var filterstr_lc = filterstr.toLowerCase();
  var all          = new Array();
  var filtered_in  = new Array();
  var filtered_out = new Array();
  // populate all, filtered_in, filtered_out arrays from global tags array
  for (var tag in tags) {
    var tag_lc = tag.toLowerCase();
    if (filterstr_lc == null || filterstr_lc.length == 0 ||
	tag_lc.match(filterstr_lc)) {
	//tag_lc.indexOf(filterstr_lc) != -1) {
      filtered_in.push(tag);
    }
    else {
      filtered_out.push(tag);
    }
    all.push(tag);
  }
  // sort the filtered_in set only, because filtered_out will not be shown
  filtered_in.sort(orderfunc);
  var filtered_in_num  = filtered_in.length;
  var filtered_out_num = filtered_out.length;
  var all_num  = all.length;
  var temp_in  = new Array();
  var temp_out = new Array();
  var cabinet  = get_cabinet_element();
  var holding  = get_hidden_cabinet_element();
  var i;
  // put copies of filtered in elements into temp in array, and copies of filtered out elements into temp out array
  for (i = 0; i < filtered_in_num; i++) {
    temp_in.push(document.getElementById(tagids[filtered_in[i]]).cloneNode(true));
  }
  for (i = 0; i < filtered_out_num; i++) {
    temp_out.push(document.getElementById(tagids[filtered_out[i]]).cloneNode(true));
  }
  // remove all from visible cabinet and holding cabinet
  for (i = 0; i < all_num; i++) {
    var node = document.getElementById(tagids[all[i]]);
    if (node.parentNode.id == cabinet.id) {
      cabinet.removeChild(node);
    }
    else {
      holding.removeChild(node);
    }
  }
  // repopulate cabinets from prepared temp arrays
  for (i = 0; i < filtered_in_num; i++) {
    cabinet.appendChild(temp_in[i]);
  }
  for (i = 0; i < filtered_out_num; i++) {
    holding.appendChild(temp_out[i]);
  }
}

function reorder_global(e) {
  if (e && (e.which ? e.which : e.keyCode) == 13) return go_to_first_tag();
  reorder((tag_order == 'alpha') ? alphaorder : usageorder,
	  document.getElementById('tagfilter').value);
}

function set_tags_alpha() {
  tag_order = 'alpha';
  reorder_global();
}

function set_tags_usage() {
  tag_order = 'usage';
  reorder_global();
}

function go_to_first_tag() {
  var cabinet      = get_cabinet_element();
  var links        = cabinet.getElementsByTagName('a');
  var links_length = links.length;
  var dest;
  for (var i = 0; i < links_length && dest == null; i++) {
    if (links[i].getAttribute('class') == 'listoftags' &&
	links[i].parentNode.parentNode.getAttribute('id') == cabinet.getAttribute('id')) {
      dest = links[i].getAttribute('href');
    }
  }
  if (dest != null) location = dest;
  return false;
}

function get_cabinet_element() {
  var override = document.getElementById('justtags');
  if (override) return override;
  return document.getElementById('sidetags_cabinet');
}

function get_hidden_cabinet_element() {
  return document.getElementById('sidetags_cabinet_hidden');
}

EOJ
}

sub html_content_se_annotations {
  my ($self) = @_;

  my $bibliotech = $self->bibliotech;
  my $command    = $bibliotech->command;

  return if $bibliotech->user;
  return if $command->start;
  return unless (my @filters = $command->filters_used) == 1;
  return unless $command->filters_used_only_single(@filters);

  if (my @users = $command->user_flun) {
    return $self->tt('compannuser', {viewed_user => $users[0]});
  }

  if (my @tags = $command->tag_flun) {
    return $self->tt('companntag', {viewed_tag => $tags[0]});
  }

  return;
}

sub html_content_annotations {
  my ($self) = @_;

  my $bibliotech = $self->bibliotech;
  my $command = $bibliotech->command;
  my $cgi = $bibliotech->cgi;

  my @users = $command->user_flun;
  my @tags = $command->tag_flun;
  if (@users and @tags) {
    my @user_tag_annotations;
    foreach my $user_tag_annotation (Bibliotech::User_Tag_Annotation->by_users_and_tags([map($_->obj, @users)], [map($_->obj, @tags)])) {
      push @user_tag_annotations, $user_tag_annotation->html_content($bibliotech, 'annotation', 1, 1);
    }
    return @user_tag_annotations ? $cgi->div({class => 'user_tag_annotations'}, @user_tag_annotations) : undef;
  }
  elsif (!defined($bibliotech->user) and !$command->start and (my @filters = $command->filters_used) == 1) {
    if ($command->filters_used_only_single(@filters)) {
      my $register = $self->pleaseregister;
      my $text;
      if (@tags) {
	#my $obj = $tags[0]->obj;
	#$text = $obj->standard_annotation_text($bibliotech, $register) if $obj;
      }
      elsif (@users) {
	#my $obj = $users[0]->obj;
	#$text = $obj->standard_annotation_text($bibliotech, $register) if $obj;
      }
      elsif (my @gangs = $command->gang_flun) {
	my $obj = $gangs[0]->obj;
	$text = $obj->standard_annotation_text($bibliotech, $register) if $obj;
      }
      elsif (my @dates = $command->date_flun) {
	my $obj = $dates[0]->obj;
	$text = $obj->standard_annotation_text($bibliotech, $register) if $obj;
      }
      elsif (my @bookmarks = $command->bookmark_flun) {
	my $obj = $bookmarks[0]->obj;
	$text = $obj->standard_annotation_text($bibliotech, $register) if $obj;
      }
      if ($text) {
	my $html = Bibliotech::Annotation->standard_annotation_html_content($bibliotech, 'annotation', 1, 1, $text);
        return $html ? $cgi->div({class => 'standard_annotations'}, $html) : undef;
      }
    }
  }
  return undef;
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  $main ||= 0;  # couple places where undef is not as good

  my $bibliotech = $self->bibliotech;
  my $command    = $bibliotech->command;
  my @users      = $command->user_flun;
  my $cgi        = $bibliotech->cgi;

  $bibliotech->has_rss(1) if $main;  # do this before caching so it gets set even when output is sent from cache

  my $cache_user_id = $self->last_updated_basis_includes_login ? undef : 'anyone';
  my ($viewed_user, $viewed_user_id);
  @users == 1 and $viewed_user = $users[0]->obj and $viewed_user_id = $viewed_user->user_id;
  my $openurl = 'noopenurl';
  if (my $activeuser = $bibliotech->user) {
    $openurl = defined $activeuser ? $activeuser->openurl_resolver.'/'.$activeuser->openurl_name : 'noopenurl';
  }
  my $cached = $self->memcache_check($bibliotech,
				     class => ref($self), method => 'html_content',
				     ($viewed_user_id
				      ? (id => $viewed_user_id, effective => [undef, $viewed_user])
				      : (user => $cache_user_id)),
				     ($main
				      ? (path => undef)
				      : (path_without_args => undef)),
				     id => $openurl,
				     options => $self->parts,
				     options => $self->options,
				     options => {class => $class, verbose => $verbose, main => $main},
				     ($cgi->param('designtest')
				      ? (options => {designtest => $cgi->param('designtest')})
				      : ())
				     );
  return $cached if defined $cached;

  my @list = $self->list(main => $main);

  my $location = $bibliotech->location;
  my $query = $bibliotech->query;
  my $heading = $self->heading;
  my %output;
  my $javascript_block = '';
  my $section = 'main';
  my @nonmain;
  my $href_type        = $self->options->{href_type} ? 'href_search_'.$self->options->{href_type} : undef;
  my $add              = sub { push    @{$output{$section}}, grep(defined $_, @_); };
  my $add_main         = sub { push    @{$output{main}},     grep(defined $_, @_); };
  my $add_main_nonmain = sub { $add_main->(map(@{$output{$_}}, @nonmain)); };
  my $close_div = 0;

  if ($main and ref($self) eq 'Bibliotech::Component::ListOfRecent') {
    Bibliotech::Profile::start('duties of main component');
    my $any_filters = $command->filters_used;
    my $freematch   = $command->freematch;
    my $geocount    = $any_filters ?$query->full_geocount : 0;
    $add->($self->html_content_se_annotations);
    $add->($self->html_content_heading($main))              unless $self->options->{noheading};
    $add->($self->html_content_annotations);
    $add->($self->html_content_wikiinfo);
    $add->($self->html_content_geoinfo($geocount))          if $any_filters and $geocount;
    $add->($self->html_content_freematch_notes($freematch)) if $freematch;
    $add->($self->html_content_num_options)                 if $any_filters or $freematch;
    Bibliotech::Profile::stop();
  }

  my @tags = $command->tag_flun;
  my @memory_scores;
  my $create_memory_scores;

  my $designtest = $cgi->param('designtest');
  my $do_close_div = sub {
    if ($designtest eq 'cabscroll2' or $designtest eq 'cabparts') {
      while ($close_div) {
	$add->($cgi->end_div);
	$close_div--;
      }
    }
  };

  Bibliotech::Profile::start('list loop');
  #warn 'parts = '.Dumper($self->parts);
  foreach (@list) {
    if (!ref $_) {
      $do_close_div->();
      $create_memory_scores = 0;
      my $text = $_;
      my $links;
      #warn "text:$text heading:$heading\n";
      if ($text eq 'Cabinet') {
	if ($heading eq 'Tags') {
	  #warn Dumper([map { ref $_ ? ref($_).":$_" : $_ } @list]);
	  #cluck 'Cabinet Tags';
	  if (@users) {  # created above
	    $text = $command->description_filter(\@users, [['Tags', 0, undef],
							   [undef, 1, "\'s tags"],
							   ['Tags for ', 1, undef]]);
	  }
	  else {
	    my @gangs = $command->gang_flun;
	    $text = $command->description_filter(\@gangs, [['Tags', 0, undef],
							   ['Group ', 1, "\'s tags"],
							   ['Tags for groups ', 1, undef]]);
	  }
 	  $links = $cgi->div({ id => 'alphatoggle' },
                     $cgi->div({ class => 'alphatoggleborder' },
                       $cgi->div({ class => 'togglewrap' },
                         $cgi->a({href => "javascript:set_tags_alpha()", class => 'actionlink'}, 'A &ndash; Z')
                       )
                     )
                   ) .  
                   $cgi->div({ id => 'usagetoggle' },
                     $cgi->div({ class => 'usagetoggleborder' },
                       $cgi->div({ class => 'togglewrap' },
                         $cgi->a({href => "javascript:set_tags_usage()", class => 'actionlink'}, 'By Usage')
                       )
                     )
                   ) .
		   $cgi->div({ id => 'tagfilterbox' },
			     $cgi->div({id => 'sidetags_cabinet_hidden', style => 'display: none'}, '&nbsp;'),
			     'Find:',
			     $cgi->textfield(-id => 'tagfilter', -name => 'tagfilter', -size => 8,
					     onkeyup => 'reorder_global(event)'));
	  $create_memory_scores = 1;
	  #warn "\$create_memory_scores = 1;";
	}
	elsif ($heading eq 'Users') {
	  if (@tags) {  # created above
	    $text = $command->description_filter(\@tags, [['Users', 0, undef],
							  ['Users who used ', 1, undef],
							  ['Users who used ', 1, undef]]);
	  }
	  else {
	    my @gangs = $command->gang_flun;
	    $text = $command->description_filter(\@tags, [['Users', 0, undef],
							  ['Users in group ', 1, undef],
							  ['Users in groups ', 1, undef]]);
	  }
	}
	elsif ($heading eq 'Groups') {
	  # @users created above
	  $text = $command->description_filter(\@users, [['Groups', 0, undef],
							 [undef, 1, "\'s groups"],
							 ["Groups for ", 1, undef]]);
	}
	$href_type = 'href_search_replacitive';
	push @nonmain, $section = 'cabinet';
      }
      elsif ($text eq 'Query') {
	$text = 'Current view';
	$href_type = 'href_search_replacitive';
	push @nonmain, $section = 'query';
      }
      elsif ($text eq 'Linked') {
	if ($heading eq 'Tags') {
	  $text = 'Tags describing these bookmarks';
	}
	elsif ($heading eq 'Users') {
	  $text = 'Users who posted these bookmarks';
	}
	else {
	  $text = 'Linked '.lc($heading);
	}
	$href_type = 'href_search_replacitive';
	push @nonmain, $section = 'linked';
      }
      elsif ($text eq 'Related') {
	$text = 'Related '.lc($heading);
	$href_type = 'href_search_global';
	push @nonmain, $section = 'related';
      }
      $add->($cgi->h3({class => 'sectiontitle'}, $text.':')) unless $self->options->{noheading};
      if ($links) {
	$add->($cgi->div({class => 'toggles'}, $links),
	       ($designtest eq 'cabscroll2' ? 
		($cgi->start_div({id => 'justtags_wrapper',
				  onmouseover => 'this.style.marginRight = 0; '.
				                 'this.style.overflow = "scroll";',
				  onmouseout  => 'this.style.marginRight = "12px"; '.
				                 'this.style.overflow = "hidden";',
			        }),
		 $cgi->start_div({id => 'justtags',
				})) : (),
		),
	       ($designtest eq 'cabparts' ?
		($cgi->div({id => 'cabparts'},
			   map { $cgi->a({href => '#', onclick => 'document.getElementById("justtags").style.display = "block"; document.getElementById("tagfilter").value = "^'.$_->[1].'"; reorder_global(); return false;'}, $_->[0]) } ((map { [$_,$_] } ('a'..'z')), ['#!','0'])),
		 $cgi->start_div({id => 'justtags_wrapper',
				}),
		 $cgi->start_div({id => 'justtags',
				}),
		 )
		: ()
		)
	       );
	$close_div += 2;
      }
    }
    else {
      (my $id = $_->table.'_'.$_->unique_value) =~ s/\W/_/g;
      push @memory_scores, [$_->label, $_->memory_score, $id] if $create_memory_scores;
      $add->("\n".$cgi->div({class => ($main ? 'content-mybookmark' : 'content-side'), id => $id},
			    scalar $_->html_content($bibliotech, $class, $verbose, $main, $href_type)));
    }
  }
  $do_close_div->();
  Bibliotech::Profile::stop();

  $javascript_block = $self->html_content_memory_scores_javascript(\@memory_scores) if !$main and @memory_scores;

  $add_main_nonmain->();

  $add_main->($self->html_content_status_line) if $main and $verbose;

  my $pobj = Bibliotech::Page::HTML_Content->new({html_parts => \%output,
						  javascript_block => $javascript_block});
  #warn Dumper($pobj);
  return $self->memcache_save($pobj);
}

sub rss_content {
  my ($self, $verbose) = @_;
  my $bibliotech = $self->bibliotech;
  my @output;
  my $iterator = $self->list(main => 1) or return ();
  Bibliotech::Profile::start('converting user_bookmark objects to rss hash data');
  my $obj = $iterator->first;
  while (defined $obj) {
    push @output, scalar $obj->rss_content($bibliotech, $verbose);
    $obj = $iterator->next;
  }
  Bibliotech::Profile::stop();
  return @output;
}

sub ris_content {
  my ($self, $verbose) = @_;
  my $bibliotech = $self->bibliotech;
  my @output;
  my $iterator = $self->list(main => 1) or return ();
  my $obj = $iterator->first;
  while (defined $obj) {
    push @output, scalar $obj->ris_content($bibliotech, $verbose);
    $obj = $iterator->next;
  }
  return @output;
}

sub geo_content {
  my ($self, $verbose) = @_;
  my $bibliotech = $self->bibliotech;
  my @output;
  my $iterator = $self->list(main => 1) or return ();
  my $obj = $iterator->first;
  while (defined $obj) {
    push @output, scalar $obj->geo_content($bibliotech, $verbose);
    $obj = $iterator->next;
  }
  return @output;
}

package Bibliotech::Component::ListOfBookmarks;
use base 'Bibliotech::Component::List';

sub heading {
  'Bookmarks';
}

sub list {
  shift->bibliotech->query->bookmarks(@_);
}

package Bibliotech::Component::ListOfUsers;
use base 'Bibliotech::Component::List';

sub heading {
  'Users';
}

sub list {
  my $self = shift;
  my %options = @_;
  return $self->list_multipart_from_user_bookmarks('Bibliotech::User') unless $options{main};
  return $self->bibliotech->query->users(sortdir => 'DESC', %options);
}

package Bibliotech::Component::ListOfActiveUsers;
use base 'Bibliotech::Component::ListOfUsers';

our $ACTIVE_USERS_WINDOW = Bibliotech::Config->get('ACTIVE_USERS_WINDOW') || '60 DAY';

sub heading {
  'Active Users';
}

sub last_updated_basis {
  ('DBI');
}

sub list {
  Bibliotech::User->search_most_active_in_window($ACTIVE_USERS_WINDOW, 1);  # 1 = act as visitor
}

sub lazy_update {
  1;
}

package Bibliotech::Component::ListOfGangs;
use base 'Bibliotech::Component::List';

sub heading {
  'Groups';
}

sub list {
  my $self = shift;
  my %options = @_;
  return $self->list_multipart_from_user_bookmarks('Bibliotech::Gang') unless $options{main};
  return $self->bibliotech->query->gangs(sortdir => 'DESC', %options);
}

package Bibliotech::Component::ListOfMyGangs;
use base 'Bibliotech::Component::List';

sub heading {
  'My groups';
}

sub list {
  my $self = shift;
  my $user = $self->bibliotech->user or return ();
  return Bibliotech::Gang->search(owner => $user);
}

package Bibliotech::Component::ListOfGangPeers;
use base 'Bibliotech::Component::List';

sub heading {
  'Members';
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;
  my $cgi = $self->bibliotech->cgi;
  my $heading = $self->heading;
  my $href_type = 'href_search_replacitive';
  my @output;
  foreach ($self->list(main => $main || 0)) {
    push @output, $cgi->div({class => "content-side"}, scalar $_->html_content($self->bibliotech, $class, $verbose, $main, $href_type));
  }
  return Bibliotech::Page::HTML_Content->blank unless @output;
  my $gang_ref = $self->bibliotech->command->gang or return ();
  @{$gang_ref} == 1 or return ();
  my $gang_name = $gang_ref->[0];
  $heading .= ' of group '.$gang_name.':';
  unshift @output, $cgi->h3({class => 'sectiontitle'}, $heading) unless $self->options->{noheading};
  return Bibliotech::Page::HTML_Content->simple(\@output);
}

sub list {
  my $self = shift;
  my $gang_ref = $self->bibliotech->command->gang or return ();
  @{$gang_ref} == 1 or return ();
  my $gang_name = $gang_ref->[0];
  my $gang = new Bibliotech::Gang ($gang_name) or return ();
  return map($_->user, Bibliotech::User_Gang->search(gang => $gang));
}

package Bibliotech::Component::ListOfTags;
use base 'Bibliotech::Component::List';

sub heading {
  'Tags';
}

sub list {
  my $self = shift;
  my %options = @_;
  return $self->list_multipart_from_user_bookmarks('Bibliotech::Tag') unless $options{main};
  return $self->bibliotech->query->tags(sortdir => 'DESC', %options);
}

package Bibliotech::Component::ListOfActiveTags;
use base 'Bibliotech::Component::ListOfTags';

our $ACTIVE_TAGS_WINDOW = Bibliotech::Config->get('ACTIVE_TAGS_WINDOW') || '30 DAY';

sub heading {
  'Active Tags';
}

sub list {
  Bibliotech::Tag->search_most_active_in_window($ACTIVE_TAGS_WINDOW, 1);  # 1 = act as visitor
}

sub lazy_update {
  1;
}

package Bibliotech::Component::ListOfRecent;
use base 'Bibliotech::Component::List';

sub heading {
  'Bookmarks';
}

sub list {
  shift->bibliotech->query->recent(@_);
}

package Bibliotech::Component::ListOfPopular;
use base 'Bibliotech::Component::List';

our $POPULAR_WINDOW = Bibliotech::Config->get('POPULAR_WINDOW') || '60 DAY';

sub heading {
  'Bookmarks';
}

sub last_updated_basis {
  ('DBI', 'USER');
}

sub list {
  my ($self, %options) = @_;
  my $bibliotech = $self->bibliotech;
  #my $time = Bibliotech::DBI->db_Main->selectrow_array('SELECT NOW() - INTERVAL 4 DAY'); #'.$POPULAR_WINDOW);
#  $bibliotech->query->popular($bibliotech->command->user ? () : (having => [sortvalue => {'>', 1}], [where => ['ub.created' => {'>', $time}], where => ['ub.updated' => {'>', $time}]]), %options);
  #$bibliotech->query->popular($bibliotech->command->user ? () : (having => [sortvalue => {'>', 1}], where => ['ub.created' => {'>', $time}]), %options);
  $bibliotech->query->popular($bibliotech->command->user ? () : (having => [sortvalue => {'>', 1}]), %options);
}

sub lazy_update {
  1;
}

package Bibliotech::Component::Comments;
use base 'Bibliotech::Component::List';
use Bibliotech::Const;
use Bibliotech::Component::AddCommentForm;

sub heading {
  'Comments';
}

sub list {
  shift->bibliotech->query->bookmarks(@_);
}

sub html_content {
  my ($self, $class, $verbose, $main, $just_comments) = @_;

  my $bibliotech = $self->bibliotech;
  my $command    = $bibliotech->command;
  my $popup      = $command->is_popup;
  my $cgi        = $bibliotech->cgi;
  my $location   = $bibliotech->location;
  my $activeuser = $bibliotech->user;

  my $uri;
  if ($uri = $cgi->param('uri')) {
    # hack to avoid /uri/xxx?bookmarklet=yyy because /uri/http://... must be the last thing on the url
    my $uri_namepart = Bibliotech::Parser::NamePart->new($uri, 'Bibliotech::Bookmark');
    my $bookmark_filter = $command->bookmark;
    defined $bookmark_filter
      ? $bookmark_filter->push($uri_namepart)
      : $command->bookmark(Bibliotech::Parser::NamePartSet->new($uri_namepart));
    $cgi->Delete('uri');
  }
  else {
    my $bookmark_filter = $command->bookmark;
    $uri = $bookmark_filter->[0] if $bookmark_filter;
  }

  my $make_add_link = sub {
    # uses $popup, $activeuser, and $cgi from outer sub
    # optionally pass in a $bookmark, otherwise uses $uri from outer sub
    my $bookmark = shift;
    return undef if !defined($bookmark) and Bibliotech::Bookmark::is_hash_format($uri);
    my $new_uri = defined $bookmark ? $bookmark->hash : $uri;
    my $comments = 'comments'.($popup ? 'popup' : '');
    my ($href, $text);
    if (defined $activeuser) {
      my $add = 'add'.($popup ? 'popup' : '');
      $href = "$location$add?continue=$comments&uri=$new_uri";
      $text = 'Add this '.URI_TERM.' to your library';
    }
    else {
      my $comments = 'comments'.($popup ? 'popup' : '');
      my $login = 'login'.($popup ? 'popup' : '');
      my $lpath = URI->new($location)->path;
      $href = "$location$login?dest=$lpath$comments?continue=confirm_AMP_uri=$new_uri";
      $text = 'Login to add or comment on this '.URI_TERM;
    }
    return $cgi->a({href => $href}, $text);
  };

  my @output;
  push @output, $cgi->h1($self->heading_dynamic($main)) unless $just_comments;
  my @bookmarks = $self->list(main => $main || 0);
  if (@bookmarks) {
    foreach my $bookmark (@bookmarks) {
      push @output, $cgi->div(scalar $bookmark->html_content($bibliotech, $class, 1, $main)) unless $just_comments;
      if (my @user_bookmark_comments = $bookmark->user_bookmark_comments) {
	foreach my $user_bookmark_comment (@user_bookmark_comments) {
	  my $user_bookmark = $user_bookmark_comment->user_bookmark;
	  my $user = $user_bookmark->user;
	  my $comment = $user_bookmark_comment->comment;
	  push @output, $cgi->div({class => 'commentdisplay'},
				  $cgi->div({class => 'commentbyline'},
					    $user->link($bibliotech, 'commentator', 'href_search_global', undef, $verbose),
					    'said on',
					    $comment->created->link($bibliotech, 'commentdate', 'href_search_global', undef, $verbose).':'),
				  scalar $comment->html_content($bibliotech, 'comment', $verbose, $main));
	}
      }
      else {
	push @output, $cgi->p('There are currently no comments for this '.URI_TERM.'.');
      }
      unless ($just_comments) {
	# if logged in, show AddCommentForm if user has the bookmark linked, or an add link; if not logged in, just show add link
	if ($bookmark->is_linked_by($activeuser)) {  # the fact that $activeuser may be undef is ok
	  my $save_uri = $cgi->param('uri');
	  my $save_continue = $cgi->param('continue');
	  $cgi->param(uri => $bookmark->hash);
	  $cgi->param('continue' => 'comments'.($popup ? 'popup' : ''));
	  my $addcomment_component = Bibliotech::Component::AddCommentForm->new({bibliotech => $bibliotech});
	  push @output, $addcomment_component->html_content($class.'addcomment', 0, 0)->content;
	  $save_uri ? $cgi->param(uri => $save_uri) : $cgi->Delete('uri');
	  $save_continue ? $cgi->param('continue' => $save_continue) : $cgi->Delete('continue');
	}
	else {
	  push @output, $cgi->p($make_add_link->($bookmark));
	}
      }
    }
  }
  else {
    my $sitename = $bibliotech->sitename;
    push @output, $cgi->p(['This '.URI_TERM." has not yet been added to $sitename.", $make_add_link->()]);
  }
  unless ($just_comments) {
    my $continue = $cgi->param('continue') || 'none';
    if ($continue eq 'return') {
      push @output, $cgi->p($cgi->a({href => $uri}, 'Return to '.URI_TERM)) if $uri;
    }
    elsif ($continue eq 'close' or $continue eq 'confirm' or $popup) {
      push @output, $cgi->p({class => 'closebutton'},
			    $cgi->button(-value => 'Close',
					 -class => 'buttonctl',
					 -onclick => 'window.close()'));
    }
  }
  return Bibliotech::Page::HTML_Content->simple(\@output);
}

1;
__END__
