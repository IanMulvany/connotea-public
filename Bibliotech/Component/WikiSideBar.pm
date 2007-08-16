# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::WikiSideBar provides a side bar that
# is probably only useful with a Bibliotech::Component::Wiki.

package Bibliotech::Component::WikiSideBar;
use strict;
use base 'Bibliotech::Component';

sub last_updated_basis {
  ('NOW');
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $action     = $cgi->param('action') || 'display';
  my $button     = $cgi->param('button');
  my $activity   = $action eq 'afteredit' && ($button eq 'Save' || $button eq 'Cancel') ? 'display' : $action;
  my $node       = $bibliotech->command->wiki_path || $cgi->param('node') || 'Home';
  my $o          = '';

  my ($nodeprefix, $basenode);
  if ($node =~ /^((Generate|System|User|Bookmark|Tag):)?([\w:]*)$/) {
    $nodeprefix = $2;
    $basenode = $3;
  }

  my %vars = (action => $action, node => $node, nodeprefix => $nodeprefix, basenode => $basenode);

  my $add_include = sub {
    $o .= $self->include(shift, $class, $verbose, $main, \%vars);
  };

  if ($activity =~ /^(?:after)?edit$/) {
    $add_include->('/wikiedithelp');
  }
  else {
    if ($node =~ /^(User|Bookmark|Tag|Group):.*?$/) {
      $add_include->('/wiki'.lc($1));
    }
    else {
      $add_include->('/wikigeneral');
    }
    $add_include->('/wikisidebar');
  }

  return Bibliotech::Page::HTML_Content->simple($cgi->div({class => 'wikisidebar'}, $o));
}

1;
__END__
