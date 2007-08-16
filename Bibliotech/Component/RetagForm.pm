# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::RetagForm class provides a rename tag form.

package Bibliotech::Component::RetagForm;
use strict;
use base 'Bibliotech::Component';

sub last_updated_basis {
  ('DBI', 'LOGIN');
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $user = $self->getlogin or return $self->saylogin('to rename your tags');

  my $bibliotech = $self->bibliotech;
  my $parser     = $bibliotech->parser;
  my $cgi        = $bibliotech->cgi;
  my $param2list = sub { Bibliotech::Component::RetagForm::TagList->new_from_param($parser, $cgi, @_) };
  my $retag      = sub { $bibliotech->retag($user->user_id, @_) };

  my $validationmsg;
  if ($cgi->param('button') eq 'Retag') {
    my $count = 0;
    eval {
      my $old = $param2list->('oldtag');
      my $new = $param2list->('newtag');
      $old->force_one;
      $old->count or die "Old tag: Missing tags, malformed tags, or use of a reserved keyword as a tag.\n";
      die "The tags you have entered are the same (case is ignored) so no action is performable.\n" if $old eq $new;
      $count = $retag->($old => $new);
      die 'No instances of old '.$old->noun." found for your user: $old.\n" unless $count;
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      return Bibliotech::Page::HTML_Content->simple
	  ($cgi->p($count ? "Successfully renamed tags in $count original ".($count == 1 ? 'instance' : 'instances').'.'
		          : 'No instances found.'));
    }
  }

  # parameter cleaning - need this to keep utf-8 output from messing up on an update reload
  foreach (qw/oldtag newtag/) {
    my $value = $self->cleanparam($cgi->param($_));
    $cgi->param($_ => $value) if $value;
  }

  my $o = $self->tt('compretag', undef, $self->validation_exception('', $validationmsg));

  my $javascript_first_empty = $self->firstempty($cgi, 'retag', qw/oldtag newtag/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					       javascript_onload => ($main ? $javascript_first_empty : undef)});
}

package Bibliotech::Component::RetagForm::TagList;

use overload '"' => 'as_cmp_string', fallback => 1;

sub new {
  my ($class, @tags) = @_;
  return bless \@tags, ref $class || $class;
}

sub new_from_param {
  my ($class, $parser, $cgi, $param) = @_;
  my @tags;
  if (my $str = $cgi->param($param)) {
    @tags = $parser->tag_list($str);
  }
  return bless \@tags, ref $class || $class;
}

sub count {
  my $tags = shift;
  return scalar @{$tags};
}

sub as_cmp_string {
  my $tags = shift;
  return join(', ', sort(map(lc($_), @{$tags}))) || '';
}

sub force_one {
  my $tags = shift;
  @{$tags} = join(' ', @{$tags}) if @{$tags} > 1;  # force just one tag
  return $tags;
}

sub noun {
  shift->count == 1 ? 'tag' : 'tags';
}

1;
__END__
