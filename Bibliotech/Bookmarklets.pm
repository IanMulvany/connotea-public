# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides functions to return snippets of HTML representing
# one or all bookmarklets.

package Bibliotech::Bookmarklets;
use strict;
use Bibliotech::Config;

our $POPUP_WIDTH  = Bibliotech::Config->get('POPUP_WIDTH')  || 720;
our $POPUP_HEIGHT = Bibliotech::Config->get('POPUP_HEIGHT') || 755;

sub bookmarklet_calc {
  my ($sitename, $base_location, $page, $popup) = @_;

  $popup = 0 if $popup eq 'direct';
  my $location = $base_location.$page.($popup ? 'popup' : '');
  my $sitename = ucfirst($sitename);
  (my $sitenamejs = $sitename) =~ s/\W/_/g;

  my $javascript = '';
  my $label = 'bookmarklet';

  my $doiregex = '/(doi:)?\s?(10\.\d{4}\/\S+)/';

  my $popup_width  = $POPUP_WIDTH;
  my $popup_height = $POPUP_HEIGHT;

  if ($page eq 'add') {
    if ($popup) {
      $javascript = qq|
	  u=location.href;
          a=false;
          x=window;
          e=x.encodeURIComponent;
          d=document;
          if((s=d.selection)?t=s.createRange().text:t=x.getSelection()+\'\')
	      (r=${doiregex}.exec(t))?u=\'http://dx.doi.org/\'+r[2]:a=true;
          a?alert(\'Please highlight a full DOI, or deselect text to add this page.\')
	   :w=open(\'${location}?continue=confirm&uri=\'+e(u)+\'&title=\'+e(d.title),\'add\',\'width=${popup_width},height=${popup_height},scrollbars,resizable\');
          void(x.setTimeout(\'w.focus()\',200));
      |;
      $label = "Add To $sitename";
    }
    else {
      $javascript = qq|
	  u=location.href;
          a=false;
          x=window;
          e=x.encodeURIComponent;
          d=document;
          if((s=d.selection)?t=s.createRange().text:t=x.getSelection()+\'\')
	      (r=${doiregex}.exec(t))?u=\'http://dx.doi.org/\'+r[2]:a=true;
          a?alert(\'Please highlight a full DOI, or deselect text to add this page.\')
	   :location.href=\'${location}?continue=return&uri=\'+e(u)+\'&title=\'+e(d.title)
       |;
      $label = "Add To $sitename (main window)";
    }
  }
  elsif ($page eq 'comments') {
    if ($popup) {
      $javascript = qq|
	  u=location.href;
          a=false;
          d=document;
          if((s=d.selection)?t=s.createRange().text:t=window.getSelection()+\'\')
	      (r=${doiregex}.exec(t))?u=\'http://dx.doi.org/\'+r[2]:a=true;
          a?alert(\'Please highlight a full DOI, or deselect the text to use the page URL.\')
	   :w=open(\'${location}?continue=confirm&uri=\'+encodeURIComponent(u),\'${sitenamejs}comments\',\'width=${popup_width},height=${popup_height},scrollbars,resizable\');
          void(window.setTimeout(\'w.focus()\',200));
      |;
      $label = "$sitename Comments";
    }
    else {
      $javascript = qq|
	  u=location.href;
          a=false;
          d=document;
          if((s=d.selection)?t=s.createRange().text:t=window.getSelection()+\'\')
	      (r=${doiregex}.exec(t))?u=\'http://dx.doi.org/\'+r[2]:a=true;
          a?alert(\'Please highlight a full DOI, or deselect the text to use the page URL.\')
	   :location.href=\'${location}?continue=return&uri=\'+encodeURIComponent(u);
      |;
      $label = "$sitename Comments (main window)";
    }
  }
  elsif ($page eq 'addcomment') {
    if ($popup) {
      $javascript = qq|
	  u=location.href;
          a=false;
          d=document;
          if((s=d.selection)?t=s.createRange().text:t=window.getSelection()+\'\')
	      (r=${doiregex}.exec(t))?u=\'http://dx.doi.org/\'+r[2]:a=true;
          a?alert(\'Please highlight a full DOI, or deselect the text to use the page URL.\')
	   :w=open(\'${location}?continue=commentspopup&uri=\'+encodeURIComponent(u),\'${sitenamejs}comments\',\'width=${popup_width},height=${popup_height},scrollbars,resizable\');
          void(window.setTimeout(\'w.focus()\',200));
      |;
      $label = "Add $sitename Comment";
    }
    else {
      $javascript = qq|
	  u=location.href;
          a=false;
          d=document;
          if((s=d.selection)?t=s.createRange().text:t=window.getSelection()+\'\')
	      (r=${doiregex}.exec(t))?u=\'http://dx.doi.org/\'+r[2]:a=true;
          a?alert(\'Please highlight a full DOI, or deselect the text to use the page URL.\')
	   :location.href=\'${location}?continue=comments&uri=\'+encodeURIComponent(u);
      |;
      $label = "Add $sitename Comment (main window)";
    }
  }

  $javascript =~ s/\s*\n\s*//g;

  my $onclick = 'alert(\'Bookmark this link in your web browser to use it.\'); return false;';
  return ($javascript, $onclick, $label);
}

sub bookmarklet {
  my ($sitename, $base_location, $cgi, $page, $popup) = @_;
  my ($javascript, $onclick, $label) = bookmarklet_calc($sitename, $base_location, $page, $popup);
  return $cgi->a({href => 'javascript:'.$javascript, onclick => $onclick}, $label);
}

sub bookmarklet_javascript {
  my ($sitename, $base_location, $cgi, $page, $popup) = @_;
  my ($javascript, $onclick, $label) = bookmarklet_calc($sitename, $base_location, $page, $popup);
  return 'javascript:'.$javascript;
}

sub bookmarklets {
  my ($sitename, $base_location, $cgi) = @_;
  my @bookmarklets;
  foreach my $page ('add', 'comments', 'addcomment') {
    foreach my $popup (0, 1) {
      push @bookmarklets, bookmarklet($sitename, $base_location, $page, $popup);
    }
  }
  return $cgi->ul($cgi->li(\@bookmarklets));
}

1;
__END__
