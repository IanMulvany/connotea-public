# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::UploadForm class provides an upload form.

package Bibliotech::Component::UploadForm;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::Const;
use HTML::Sanitizer;
use List::MoreUtils qw/any/;
use Bibliotech::Util;
use Bibliotech::Captcha;
use Bibliotech::Plugin;

sub last_updated_basis {
  ('DBI', 'LOGIN');
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi = $bibliotech->cgi;

  my $user = $self->getlogin or return $self->saylogin('to upload a file');
  return Bibliotech::Page::HTML_Content->simple('Your account is inactive.') unless $user->active;

  my $validationmsg;
  my $button = $cgi->param('button');

  if ($button eq 'Upload' or $button eq 'Confirm' or $button eq 'Submit') {
    my $o = '';
    eval {
      my @tags;
      my $kw = $cgi->param('kw');
      @tags = $bibliotech->parser->tag_list($cgi->param('tag'));
      my $use_keywords;
      if ($kw eq 'kw') {
	$use_keywords = 1;
	@tags = ();  # force blank
      }
      else {
	die "Missing tags, malformed tags, or use of a reserved keyword as a tag.\n" unless @tags;
	if ($kw eq 'kw_and_tag') {
	  $use_keywords = 1;
	}
	elsif ($kw eq 'kw_or_tag') {
	  $use_keywords = 2;
	}
	elsif ($kw eq 'tag') {
	  $use_keywords = 0;
	}
	else {
	  die 'unknown option for kw';
	}
      }
      my $memcache = $bibliotech->memcache;
      my $doc_cache_key;
      if (my $upload_key_param = $cgi->param('upload_key')) {
	my ($time, $serial) = $upload_key_param =~ m|^(\d+)/(\d+)$|;
	$doc_cache_key = new Bibliotech::Cache::Key (class => __PACKAGE__,
						     id => 'doc',
						     user => $user,
						     id => $time,
						     id => $serial);
      }
      else {
	my $time = Bibliotech::Util::time();
	my $serial = int(rand(1000000));
	$doc_cache_key = new Bibliotech::Cache::Key (class => __PACKAGE__,
						     id => 'doc',
						     user => $user,
						     id => $time,
						     id => $serial);
	$cgi->param(upload_key => "$time/$serial");
      }
      my $captcha_cache_key = $doc_cache_key.':captcha';
      my $doc;
      my $captcha_status = 0;

      if ($button eq 'Confirm' or $button eq 'Submit') {
	$doc = $memcache->get($doc_cache_key);
	die "Upload session has expired.\n" unless defined $doc;
	$captcha_status = $memcache->get($captcha_cache_key);
	if ($captcha_status == 1) {
	  if (my $md5sum = $cgi->param('captchamd5sum')) {
	    if (my $code = $cgi->param('captchacode')) {
	      my $captcha = Bibliotech::Captcha->new;
	      my $result  = $captcha->check_code($code, $md5sum);
	      if ($result == 1) {
		$captcha_status = 2;
		$memcache->set($captcha_cache_key => 2, 86400);
	      }
	    }
	  }
	}
	if ($captcha_status == 1 or $button eq 'Submit') {
	  $button = '_display';
	}
	else {
	  my $count = $cgi->param('count');
	  my @selections;
	  for (my $i = 1; $i <= $count; $i++) {
	    push @selections, $i if $cgi->param('add'.$i);
	  }
	  my $type = $cgi->param('type');
	  push_out_header_to_impatient_browser($bibliotech->request);
	  ################ IMPORT THE FILE
	  my $results = $bibliotech->import_file($user,
						 $type,
						 $doc,
						 \@selections,
						 \@tags,
						 $use_keywords,
						 0,
						 $captcha_status == 2 ? 1 : 0);
	  my @errors = grep($_, map($_->error, @{$results}));
	  die join("\n", @errors) if @errors;
	  $memcache->delete($doc_cache_key);
	  $memcache->delete($captcha_cache_key);
	}
      }

      if ($button eq 'Upload') {
	my $fh = $cgi->upload('file') or die "Expected an uploaded file but none could be opened.\n";
	{ local $/ = undef; $doc = <$fh>; }
	close $fh;
	defined($doc) && length($doc) or die "Expected an uploaded file but an empty one was received.\n";
	$memcache->set($doc_cache_key => $doc, 86400);
	$memcache->set($captcha_cache_key => 0, 86400);
	$button = '_display';
      }

      if ($button eq '_display') {
	my $type = $cgi->param('type');
	my $results = $bibliotech->import_file($user, $type, $doc, undef, \@tags, $use_keywords, 1, $captcha_status == 2 ? 1 : 0);
	my $count_total = $results->length;
	my $count_errors = grep($_->error, @{$results});
	my $count_ok = $count_total - $count_errors;
        my $report_msg = $count_total.' '.($count_total == 1 ? 'record' : 'records').' found';
        if ($count_total == $count_ok) {
          if ($count_total > 1) {
            $report_msg .= ', '.($count_total == 2 ? 'both' : 'all').' of which will be imported';
	  }
          $report_msg .= '.';
        } 
        else {
	  if ($count_total == 1) {
            $report_msg .= ', which will not be imported.';
          }
          else {
            $report_msg .= ', of which '.$count_ok.' will be imported and '.$count_errors.' will be skipped.'; 
          }
        }
	my $need_captcha = any { $_->is_spam } @{$results};
	if ($need_captcha) {
	  if ($captcha_status == 2) {
	    $need_captcha = 0;
	  }
	  elsif ($captcha_status == 0) {
	    $captcha_status = 1;
	    $memcache->set($captcha_cache_key => 1, 86400);
	  }
	}

	$o .= $cgi->h1('File Upload');
	$o .= $cgi->start_form(-method => 'POST', -action => $bibliotech->location.'upload', -name => 'upload');

	if ($need_captcha) {
	  $cgi->Delete('captchamd5sum');
	  $cgi->Delete('captchacode');
	  my $captcha = Bibliotech::Captcha->new;
	  my $md5sum  = $captcha->generate_code(5);
	  my $src     = $captcha->img_href($md5sum);
	  $o .= $self->tt('compcaptcha', {captchasrc => $src, captchamd5sum => $md5sum});
	}

	$o .= $cgi->div({class => 'actionmsg'}, $report_msg) . $cgi->br;

	$o .= $cgi->div({class => 'buttonrow'},
			$cgi->submit(-id => 'confirmbuttontop', -class => 'buttonctl', -name => 'button', -value => 'Confirm'),
			$cgi->submit(-id => 'cancelbuttontop', -class => 'buttonctl', -name => 'button', -value => 'Cancel'));
	my $count = 0;
	while (my $result = $results->fetch) {
	  my $user_article = $result->user_article;
	  my $warning = $result->warning;
	  my $error = $result->error;
	  $count++;
	  my $ok_to_include = $error ? 0 : 1;
	  my $uri;
	  $uri = $user_article->bookmark->url if $user_article;
	  my @div;
	  my @header;
	  push @header, $cgi->span({class => 'iconscheckbox'},
				   $cgi->checkbox(-class => 'checkboxctl',
						  -name => 'add'.$count,
						  -checked => 1,
						  -value => 1,
						  -label => 'Include')) if $ok_to_include;
	  my $action_msg = $ok_to_include ? 'Adding' : '! Skipping';
	  push @header, $cgi->span({class => 'uploadentry'}, $action_msg, 'record #'.$count);
	  push @div, $cgi->div({class => 'icons'}, @header) if @header;
	  push @div, $cgi->div({class => 'actionmsg'}, $warning) if $warning;
	  push @div, $cgi->div({class => 'errormsg'}, $error) if $error;
	  if ($user_article) {
	    my $bookmark = $user_article->bookmark;
	    $bookmark->adding($ok_to_include ? 3 : 4);  # indicate that we're "adding"
	    my $html;
	    if ($bookmark->url ne 'NO_URI' or $user_article->citation or $bookmark->citation) {
	      $html = $user_article->html_content($bibliotech, 'upload_result', $verbose, $main);
	    }
	    push @div, $cgi->div({class => 'upload_bookmark'}, $html) if $html;
	    push @div, $cgi->br, $cgi->br;
	  }
	  $o .= $cgi->div({class => 'uploaded'}, @div);
	}
	$o .= $cgi->hidden(count => $count_total);
	$o .= $cgi->hidden('kw');
	$o .= $cgi->hidden('tag');
	$o .= $cgi->hidden('type');
	$o .= $cgi->hidden('upload_key');
	if ($count > 0) {
	  $o .= $cgi->div({class => 'buttonrow'},
			  $cgi->submit(-id => 'confirmbutton', -class => 'buttonctl', -name => 'button', -value => 'Confirm'),
			  $cgi->submit(-id => 'cancelbutton', -class => 'buttonctl', -name => 'button', -value => 'Cancel'));
	}
	$o .= $cgi->end_form;
      }
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      die 'Location: '.$bibliotech->location."library\n" if $button eq 'Confirm';
      $self->discover_main_title($o);
      return Bibliotech::Page::HTML_Content->simple($o);
    }
  }
  elsif ($button eq 'Cancel') {
    # nothing to do because no user_bookmark's are created on first pass
    # go back to upload form
    die 'Location: '.$bibliotech->location."upload\n";
  }

  my $o = $self->tt('compupload',
		    {modules => Bibliotech::Plugin::Import->selection_tt},
		    $self->validation_exception(undef, $validationmsg));

  my $javascript_first_empty = $self->firstempty($cgi, 'upload', qw/file tag/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					       javascript_onload => ($main ? $javascript_first_empty : undef)});
}

sub push_out_header_to_impatient_browser {
  # http://theory.uwinnipeg.ca/modperl/docs/2.0/user/coding/coding.html#Forcing_HTTP_Response_Headers_Out
  #my $r = shift;
  #$r->content_type('text/html');
  #$r->rflush; # send the headers out
  shift->send_http_header('text/html');
}

1;
__END__
