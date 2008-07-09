# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# An object of the Bibliotech::Command class is returned by Bibliotech::Parser
# for each query that is sent in. Bibliotech::Command is able to store,
# describe, and provide a canonical URI for any command.

package Bibliotech::Command;
use strict;
use base 'Class::Accessor::Fast';
use Set::Array;
use URI;
use URI::QueryParam;
use Encode qw/encode_utf8/;
use Bibliotech::FilterNames;
use Bibliotech::Util;

__PACKAGE__->mk_accessors(map($_->{name}, @FILTERS),
			  qw/verb output page start num sort freematch wiki_path/);

BEGIN {
  no strict 'refs';
  foreach my $filter (map($_->{name}, @FILTERS)) {
    *{$filter.'_flun'} = sub {
      my $self = shift;
      my $contents = $self->$filter or return ();
      return $contents->flatten->unique;
    };
  }
}

sub page_or_inc {
  my $page = shift->page;
  return $page->[0] if ref $page;
  return $page;
}

sub page_or_inc_filename {
  my $self = shift;
  return $self->inc_filename || $self->page;
}

sub inc_filename {
  my $page = shift->page;
  return $page->[1] if ref $page;
  return;
}

sub is_popup {
  shift->page =~ /popup$/;
}

sub is_login_or_logout {
  shift->page =~ /^log(in|out)$/
}

sub is_searchable_query {
  my $self = shift;
  my $page = $self->page_or_inc;
  return $self->filters_used && !$self->is_bookmark_command && grep { $page eq $_ } qw(home recent export);
}

sub filters_used {
  my $self = shift;
  return grep { my $value = $self->$_; $value && @{$value}; } map($_->{name}, @FILTERS);
}

sub filters_used_arrayref {
  [shift->filters_used];
}

sub one_filter_used {
  shift->filters_used == 1;
}

sub referent_if_one_filter_used_only_single {
  my $self = shift;
  my @filters = $self->filters_used;
  return unless @filters == 1;
  my $name  = $filters[0];
  my $class = $FILTERS{$name}->{class};
  my $flun  = $name.'_flun';
  my @parts = $self->$flun;
  return unless @parts == 1;
  my $part = $parts[0];
  return $self->obj_for_part($part, $class);
}

sub filters_used_only {
  my ($self, @match) = @_;
  return Set::Array->new($self->filters_used)->is_equal(Set::Array->new(@match));
}

sub filters_used_only_single {
  my ($self, @match) = @_;
  return 0 unless $self->filters_used_only(@match);
  return 0 if grep { !$_ || @{$_} != 1 || ref $_->[0] eq 'ARRAY'; } map($self->$_, @match);
  return 1;
}

sub is_user_command {
  shift->filters_used_only_single('user');
}

sub is_bookmark_command {
  shift->filters_used_only_single('bookmark');
}

sub obj_for_part {
  my ($self, $part, $class) = @_;
  return unless defined $part;
  return $part->obj if ref $part eq 'Bibliotech::Parser::NamePart';
  return $class->new($part) if $class;
  return;
}

sub description_part {
  my ($self, $jointype, $part_ref, $class) = @_;
  return undef unless defined $part_ref and @{$part_ref};
  my @str;
  foreach (@{$part_ref}) {
    my $part = $_;  # copy so as not to modify $part_ref structure
    if (ref($part) eq 'ARRAY') {
      $part = $self->description_part(and => $part, $class);
      $part = "($part)" if @{$part_ref} > 1;
    }
    else {
      if ($class) {
	if (my $obj = $self->obj_for_part($part, $class)) {
	  $part = $obj->label_short;
	}
      }
      $part = "\"$part\"" if $part =~ /\s/ and $part !~ /^\w+: .+$/;
    }
    push @str, $part;
  }
  return Bibliotech::Util::speech_join($jointype, @str);
}

sub description_filter {
  my ($self, $part_ref, $text_ref) = @_;
  my $count = 0;
  if ($part_ref and @{$part_ref}) {
    $count = Set::Array->new(@{$part_ref})->flatten->length;
    $count = 2 if $count > 2;
  }
  my ($prefix, $show, $postfix);
  ($prefix, $show, $postfix) = @{$text_ref->[$count]} if $text_ref and $text_ref->[$count];
  return join('', grep(defined($_),
		       $prefix,
		       $show
		       ? $self->description_part(or => $part_ref, ($show =~ /\D/ ? $show : undef))
		       : undef,
		       $postfix));
}

sub _strip_popup {
  local $_ = pop;
  s/popup$//;
  return $_;
}

sub description {
  my ($self, %options) = @_;
  my $user_block      = $options{user_block}       || [['Bookmarks', 1, undef],
						       [undef, 1, "\'s bookmarks"],
						       ['Bookmarks for ', 1, undef]];
  my $gang_block      = $options{gang_block}       || [undef,
						       ['by group ', 1, undef],
						       ['by group ', 1, undef]];
  my $tag_block       = $options{tag_block}        || [undef,
						       ['matching tag ', 1, undef],
						       ['matching tags ', 1, undef]];
  my $date_block      = $options{date_block}       || [undef,
						       ['on ', 1, undef],
						       ['on ', 1, undef]];
  my $bookmark_block  = $options{bookmark_block}   || [undef,
						       ['for ', 'Bibliotech::Bookmark', undef],
						       ['for ', 'Bibliotech::Bookmark', undef]];
  my $freematch_block = $options{freematch_block}  || [undef,
						       ['with search term ', 1, undef],
						       ['with search terms ', 1, undef]];
  my $prefix  	      = $options{prefix};
  my $postfix 	      = $options{postfix};
  my $freematch       = $self->freematch;
  my @freematch       = $freematch ? @{$freematch->terms} : ();
  my $freematch_data  = @freematch ? [\@freematch] : undef;
  local $_ = join(' ', grep($_,
			    $prefix,
			    $self->description_filter($self->user,     $user_block),
			    $self->description_filter($self->gang,     $gang_block),
			    $self->description_filter($self->tag,      $tag_block),
			    $self->description_filter($self->date,     $date_block).
			    $self->description_filter($self->bookmark, $bookmark_block),
			    $self->description_filter($freematch_data, $freematch_block),
			    $postfix));
  my $page 	= $self->page;
  my $noun 	= $page =~ /^(home|popular|recent)$/ ? 'Bookmarks' : _strip_popup(ucfirst($page));
  my $adjective = $page eq 'popular' ? 'Popular' : undef;
  my $bookmarks = ($adjective ? $adjective.' ' : '').$noun;
  s/Bookmarks/$bookmarks/g;
  s/bookmarks/\l$bookmarks/g;
  return $_;
}

sub canonical_uri {
  my ($self, $location, $override, $show_home) = @_;
  ($location ||= '/') =~ s|/$||;
  $override ||= {};

  # drop gang if switching user; drop user if switching gang
  $override->{gang} = [set => undef] if $override->{user} and $self->gang and !$override->{gang};
  $override->{user} = [set => undef] if $override->{gang} and $self->user and !$override->{user};

  my $output = $override->{output} ? $override->{output}->[1] : $self->output;
  my $page   = $override->{page}   ? $override->{page}->[1]   : $self->page;

  my @slashparts;

  my $wiki_path = $self->wiki_path;
  unshift @slashparts, ('wiki', $wiki_path) if $wiki_path;

  my ($changed_filter, $used_filter) = (0, 0);
  foreach my $filter_setup (@FILTERS) {
    my $filter = $filter_setup->{name};
    my $data = $self->$filter || [];
    my @data = @{$data};
    my $override_cmd = $override->{$filter} || $override->{any_filter};
    if ($override_cmd) {
      my @override = @{$override_cmd};
      my $keyword = shift @override;
      if ($keyword eq 'add') {
	foreach my $new_value (grep(defined $_, @override)) {
	  if (grep(ref $_ || $new_value ne $_, @data) == @data) {
	    push @data, $new_value;
	    $changed_filter = 1;
	  }
	}
      }
      elsif ($keyword =~ /^(replace|set)$/) {
	@data = grep(defined $_, @override);
	$changed_filter = 1;
      }
      else {
	die "Unknown keyword for canonical URI filter \"$filter\": \"$keyword\"";
      }
    }
    if (@data) {
      # @data contains Bibliotech::Parser::NamePart objects from the current filter we're looping on, represented by $filter_setup
      push @slashparts, $filter_setup->{label} => map(ref($_) eq 'ARRAY' ? join('+', @{$_}) : "$_", @data);
      $used_filter = 1;
    }
  }

  $page = 'recent' if $changed_filter and (ref $page or $page !~ /^(users|tags|bookmarks|export)$/);
  if ($page eq 'home') {
    unshift @slashparts, $page if $show_home;
  }
  elsif ($page eq 'wiki' and $wiki_path) {
    # noop
  }
  elsif ($page ne 'recent') {  #  or exists $override->{start}
    $page = $page->[1] if ref $page;
    unshift @slashparts, $page;
  }

  unshift @slashparts, $output unless $output eq 'html' or $override->{no_output};

  @slashparts = ('recent') unless @slashparts;  # you have to say it if there's nothing else to say

  my $uri = URI->new(join('/', $location, map { encode_utf8($_) } @slashparts));
  foreach my $arg (qw/start num sort freematch/) {
    next if $arg eq 'start' and $changed_filter;  # if you change a value you are starting again
    my $value = $self->$arg;
    $value = $override->{$arg}->[1] if $override->{$arg};
    next if $arg eq 'num' and $value eq Bibliotech::Parser->num_default($output);
    next unless defined $value;
    (my $key = $arg) =~ s/^freematch$/q/;
    $uri->query_param($key => $value);
  }
  return $uri;
}

# used by Web API to figure out the a proper object location
sub canonical_uri_via_html {
  my ($self, $location, $override, $show_home) = @_;
  $override ||= {};
  $override->{output} = [set => 'html'];
  return $self->canonical_uri($location, $override, $show_home);
}

sub canonical_uri_as_downloadable_filename {
  my $self      = shift;
  my $output    = $self->output;
  my $extension = shift || '.'.$output;
  my $filename  = $self->canonical_uri(undef, {no_output => 1}, 1);
  $filename =~ s|^/?$|/recent|;   # at least say 'recent'
  $filename =~ s|^/||;            # strip leading slash
  $filename =~ s|[/\s?=]|_|g;     # alter slashes, spaces, question marks and equals to underscores
  $filename .= $extension;        # append a standard extension
  return $filename;
}

sub rss_href {
  my ($self, $bibliotech) = @_;
  return $bibliotech->location.'rss/wiki/' if $self->page_or_inc eq 'wiki';
  return $self->canonical_uri($bibliotech->location, {output => [set => 'rss'],
						      start  => [set => undef],
						      num    => [set => undef]});
}

sub ris_href {
  my ($self, $bibliotech) = @_;
  return $self->canonical_uri($bibliotech->location, {output => [set => 'ris'],
						      start  => [set => undef],
						      num    => [set => undef]});
}

sub geo_href {
  my ($self, $bibliotech) = @_;
  return $self->canonical_uri($bibliotech->location, {output => [set => 'geo'],
						      start  => [set => undef],
						      num    => [set => undef]});
}

sub export_href {
  my ($self, $bibliotech) = @_;
  return $self->canonical_uri($bibliotech->location, {output => [set => 'html'],
						      page   => [set => 'export'],
						      start  => [set => undef],
						      num    => [set => undef]});
}

1;
__END__
