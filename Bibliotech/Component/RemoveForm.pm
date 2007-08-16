# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::Remove class provides a remove form.

package Bibliotech::Component::RemoveForm;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::Const;

sub last_updated_basis {
  ('DBI', 'LOGIN');
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $user = $self->getlogin or return $self->saylogin;

  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $cgi        = $bibliotech->cgi;

  my $validationmsg;
  if ($cgi->param('button') eq 'Remove' and my $uri = $cgi->param('uri')) {
    eval {
      $bibliotech->remove(user => $user, uri => $uri);
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      my $dest = $cgi->param('dest');
      die "Location: $dest\n" if $dest && $dest =~ /^\Q$location\E/;
      my $continue = $cgi->param('continue') || 'library';
      return $self->on_continue_param_return_close_library_or_confirm($continue, $uri, sub {
	return ($cgi->p('Your bookmark has been removed.').
		$cgi->p({class => 'closebutton'},
			$cgi->button(-value => 'Close',
				     -class => 'buttonctl',
				     -onclick => 'window.close()')));
      });
    }
  }

  my $uri = $cgi->param('uri');
  if ($uri and Bibliotech::Bookmark::is_hash_format($uri)) {
    my ($bookmark) = Bibliotech::Bookmark->search(hash => $uri) or die "Hash not found as a known URI ($uri).\n";
    $cgi->param('uri', $uri = $bookmark->url);
  }

  my $bookmark;
  ($bookmark) = Bibliotech::Bookmark->search(url => $uri) if $uri;
  $bookmark->adding(1) if $bookmark;  # temp column, suppresses remove link in html_output

  my $o = $self->tt('compremove', {referer => $cgi->referer || undef}, $self->validation_exception('', $validationmsg));

  my $javascript_first_empty = $self->firstempty($cgi, 'remove', qw/uri/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					       javascript_onload => ($main ? $javascript_first_empty : undef)});
}

1;
__END__
