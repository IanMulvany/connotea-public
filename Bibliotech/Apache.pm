# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Apache class handles actual requests via Apache.

package Bibliotech::Apache;
use strict;
use Bibliotech::Config;
use Bibliotech::ApacheProper;
use base 'Bibliotech';  # down here because its best to load Apache modules first in mod_perl scripts
die $Bibliotech::Plugin::errstr if defined $Bibliotech::Plugin::errstr;  # 'use base' won't die under apache
use Bibliotech::Const;
use Bibliotech::Cache;
use Bibliotech::DBI;
use Bibliotech::Log;
use Bibliotech::Page::Standard;
use Bibliotech::Parser;
use Bibliotech::WebAPI;
use Bibliotech::CGI;
use Bibliotech::Throttle;
use Bibliotech::Clicks;
use Bibliotech::WebCite;
use Bibliotech::Profile;
# load Inc because of its utility to include files as well as directly as a component
use Bibliotech::Component::Inc;
# load ReportProblemForm because it appears in html exception pages
use Bibliotech::Component::ReportProblemForm;
use Encode qw/decode_utf8 encode_utf8 is_utf8/;
use Time::HR;
use HTTP::Date;
use Data::Dumper;

our $DOCROOT                      = Bibliotech::Config->get('DOCROOT');
$DOCROOT =~ s|([^/])$|$1/|;
our $LINK                         = Bibliotech::Config->get('LOCATION');
$LINK =~ s|/$||;
our $LOCATION                     = $LINK ? new URI($LINK.'/') : undef;
our $PREPATH                      = Bibliotech::Config->get('PREPATH');
our $CLIENT_SIDE_HTTP_CACHE       = Bibliotech::Config->get('CLIENT_SIDE_HTTP_CACHE') || 1;
our $CACHE_AGE_HEADER 		  = Bibliotech::Config->get('CACHE_AGE_HEADER') || 3;
our $NO_CACHE_HEADER  		  = Bibliotech::Config->get('NO_CACHE_HEADER');
our $FRESH_VISITOR_LAZY_UPDATE    = Bibliotech::Config->get('FRESH_VISITOR_LAZY_UPDATE');
our $EXPLAIN_HTTP_CODES           = Bibliotech::Config->get('EXPLAIN_HTTP_CODES');
our $OUTPUTS_ALTERNATION          = '('.join('|',@Bibliotech::Parser::OUTPUTS).')';
our $LOG                          = Bibliotech::Log->new;
our $MEMCACHE                     = Bibliotech::Cache->new({log => $LOG});
our $HANDLE_STATIC_FILES	  = Bibliotech::Config->get('HANDLE_STATIC_FILES') || [];
$HANDLE_STATIC_FILES = [$HANDLE_STATIC_FILES] unless ref $HANDLE_STATIC_FILES;

our $USER_ID;
our $USER;
our %QUICK;

# helper routine to decide if this is a simple file to serve off the filesystem (graphics, etc.)
# "by_apache" in this case means not by this handler by by the normal Apache file handler
sub is_filename_handled_by_apache {
  local $_ = shift;      # full local pathname, e.g. /var/www/html/bibliotech/file.ext
  return 1 if -e && -f;  # Apache should handle existing files
  return 0;
}

# helper routine to decide if this file, although normally handled by Apache, should be processed here
# useful for adding template directives in Javascript or CSS files
sub is_filename_forced_handled {
  my $filename = shift;  # full local pathname, e.g. /var/www/html/bibliotech/file.ext
  return 1 if grep { $filename =~ m|\Q$_\E$| } @{$HANDLE_STATIC_FILES};
  return 0;
}

# under normal operations just return a status code, but can be set to display a message instead
sub explainable_http_code {
  my ($self, $code, $reason, $r) = @_;
  return $code unless $EXPLAIN_HTTP_CODES;
  return exception_handler_text($self, "Would have returned $code but in explain mode:\n$reason", $r);
}

sub handler {
  my $starthrtime = gethrtime;
  my $r = shift;
  my $pool = $r->pool;

  cleanup_quick([\$USER_ID, \$USER, \%QUICK]);
  $USER_ID = $r->user || undef;
  $pool->cleanup_register(\&cleanup_quick, [\$USER_ID, \$USER, \%QUICK]);

  my $staticfile = do { my $filename = $r->filename;
			$filename =~ s/\Q$PREPATH\E$// if $PREPATH;
			$filename.$r->path_info; };
  return explainable_http_code(undef, DECLINED, 'Apache can handle static files', $r)
      if is_filename_handled_by_apache($staticfile) and !is_filename_forced_handled($staticfile);

  $staticfile = decode_utf8($staticfile) || decode_utf8(encode_utf8($staticfile)) || $staticfile;
  my $self = bless Bibliotech->new({request => $r, log => $LOG}), __PACKAGE__;
  my $docroot = $DOCROOT || $r->document_root;
  $docroot =~ s|([^/])$|$1/|;
  my $sitename = $self->sitename;
  $docroot .= lc($sitename) if -e $docroot.lc($sitename);
  $docroot =~ s|([^/])$|$1/|;
  $self->docroot($docroot);

  # set path
  (my $path = $staticfile) =~ s|^$docroot|/|;
  $path =~ s|/uri/(\w{1,10}):/|/uri/$1://|;
  my $args = $r->args;
  $path .= '?'.$args if $args;
  $self->path($path);

  # set link and location
  my $link = $LINK;
  my $location = $LOCATION;
  unless ($link && $location) {
    ($link = 'http://'.$r->get_server_name.$r->location) =~ s|/$||;
    $location = $link.'/';
    $link .= $path;
    $location = new URI ($location);
  }
  $self->link($link);
  $self->location($location);

  $self->memcache($MEMCACHE);

  # without the next line, objects left in an Apache child's memory could be reused even if another child had
  # in the intervening time acted to change the contents of the database... a possible optimization here would
  # be to only call this if the database update timestamp had moved since the last time this child ran
  Bibliotech::DBI->clear_object_index;

  eval {
    return $self->user($USER = Bibliotech::User->retrieve($USER_ID)) if $USER_ID;
    Bibliotech::DBI->db_Main->ping;
  };
  return $self->explainable_http_code(HTTP_SERVICE_UNAVAILABLE, "Database user lookup or ping failed:\n$@") if $@;

  $self->process(verb => $r->method);
  return $self->explainable_http_code(NOT_FOUND, "Failed to process requested URI\n".$self->error)
      if $self->error =~ /(not a recognized|bad command|missing a parameter after the keyword)/;

  my $command = $self->command or return $self->explainable_http_code(NOT_FOUND, 'No command object available');
  my $page    = $command->page_or_inc;
  my $output  = $command->output;
  return $self->explainable_http_code(NOT_FOUND, "We do not serve inc pages that are not html format.\noutput = $output")
      if $page eq 'inc' and $output ne 'html';

  return $self->explainable_http_code(FORBIDDEN, 'Data requests must have a user.')
      if $output eq 'data' and !$USER_ID;

  my $canonical_path = $command->canonical_uri(undef, undef, 1);
  $self->canonical_path($canonical_path);

  my $load;
  $MEMCACHE->add(LOAD => 0);                           # add does nothing if it already exists
  $load = $MEMCACHE->incr('LOAD');                     # incr only works on existing values, hence the add
  $pool->cleanup_register(\&cleanup_decr, $MEMCACHE);  # immediately register the mechanism to perform a decr
  $self->load($load);

  my $dbtime   = Bibliotech::DBI::db_get_last_updated();
  my $who      = (defined $USER ? 'user '.$USER->username." ($USER_ID)" : 'visitor');
  my $log_line = "$who requests $canonical_path bringing load to $load with db at $dbtime";
  $LOG->info($log_line);  # will also go in error report if there's an exception

  my $canonical_path_for_cache_key = $canonical_path->clone;
  my $args_obj = URI->new($location.'?'.$args);
  foreach my $cache_relevant_arg ('uri',    	# used for queries
				  'q',      	# used for queries
				  'user',   	# used for forgotpw
				  'userid', 	# used for verify
				  'code',   	# used for forgotpw and verify
				  'time',   	# used for forgotpw
				  'debug',      # add some debug output
				  'designtest', # test some new code area
				  ) {
    if (my $value = $args_obj->query_param($cache_relevant_arg)) {
      $canonical_path_for_cache_key->query_param($cache_relevant_arg => $value);  # copy across
    }
  }
  $self->canonical_path_for_cache_key($canonical_path_for_cache_key);

  my $code = OK;
  eval {
    my $handler_func =
	eval { return $page.'_handler'         if $page =~ m!^(?:library|profile|click|citation|sabotage)$!;
	       return 'library_export_handler' if $page =~ m!^(?:library/export|export/library)$!;
	       return 'query_handler';
             };
    $code = $self->$handler_func;
  };

  if ($@) {  # handle an exception bubbled up from main codebase
    my $e = $@;
    my ($note, $report);
    my $calc_report = sub { join("\n",
				 'Error exception report:',
				 '',
				 $log_line,
				 '',
				 do { local $_ = $location; s|\Q$PREPATH\E/$||; $_; } . $r->uri,
				 $note ? ('', $note) : (),
				 '',
				 $e,
				 ''); };
    my $get_report = sub { return $report if defined $report;
			   return $report = $calc_report->(); };
    if ($e =~ /DBI connect\(.*\) failed/ or
	$e =~ /execute failed: Server shutdown in progress/) {
      # mysql server is shutting down or off
      # this code will say "high load" which is not accurate, but acceptable
      $code = HTTP_SERVICE_UNAVAILABLE;
      $note = 'masked error with service unavailable screen';
    }
    else {
      $self->exception_handler($get_report->());
    }
    $LOG->error('exception: '.$e);
    $self->notify_for_exception(subject => '['.$self->sitename.' exception]', body => $get_report->());
  }

  my $elapsed = sprintf('%0.4f', (gethrtime() - $starthrtime) / 1000000000);
  $load--;  # saved in memcache by cleanup handler registered after getting LOAD
  $LOG->info("completed $canonical_path with code $code in $elapsed secs bringing load to $load");
  $LOG->flush;

  return code_for_handler_return($code);
}

# registered as a cleanup handler to decrement the load variable
sub cleanup_decr {
  shift->decr('LOAD');  # parameter is $MEMCACHE object
  return OK;
}

# registered as a cleanup handler to remove temporary cached values
sub cleanup_quick {
  my $items = shift;
  ${$items->[0]} = undef;  # parameter is $USER_ID
  ${$items->[1]} = undef;  # parameter is $USER
  %{$items->[2]} = ();     # parameter is $QUICK
  return OK;
}

# accept a user object and return a canonical library URL
sub library_location {
  my ($self, $user, $override_ref) = @_;
  die 'no user' unless defined $user;
  return $self->command->canonical_uri($self->location,
				       {page => [set => 'recent'],
					user => [replace => $user->username],
					%{$override_ref||{}}});
}

# accept a user object and return a canonical wiki profile URL
sub profile_location {
  my ($self, $user) = @_;
  die 'no user' unless defined $user;
  return $self->location.'wiki/User:'.$user->username;
}

# handle the /library URI which redirects to their library or the login page
sub library_handler {
  my ($self, $override_ref) = @_;
  my $user = $self->user;
  my $r    = $self->request;

  my $uri;
  if (defined $user) {
    $uri = $self->library_location($user, $override_ref);
  }
  else {
    Bibliotech::Component->new({bibliotech => $self})->remember_current_uri;
    $uri = $self->location.'login';
  }

  $r->headers_out->set(Location => $uri);
  $r->status(REDIRECT);
  return REDIRECT;
}

# handle the /library/export URI which redirects to their library export page or the login page
sub library_export_handler {
  shift->library_handler({page => [set => 'export']});
}

# handle the /profile URI which redirects to their wiki profile page
sub profile_handler {
  my $self = shift;
  my $user = $self->user;
  my $r    = $self->request;

  my $uri;
  if (defined $user) {
    $uri = $self->profile_location($user);
  }
  else {
    Bibliotech::Component->new({bibliotech => $self})->remember_current_uri;
    $uri = $self->location.'login';
  }

  $r->headers_out->set(Location => $uri);
  $r->status(REDIRECT);
  return REDIRECT;
}

# display an error in an HTML page
sub exception_handler_html {
  my ($self, $text) = @_;
  my $page = Bibliotech::Page->new({bibliotech => $self});
  my $root = $page->find_template_root;
  $root =~ s|([^/])$|$1/|;  # ensure trailing slash
  my $file = $root.'exception.html';
  my $fh   = IO::File->new($file) or die "cannot open $file";
  $text =~ s/\n+\z//;  # strip trailing newline so it looks cleaner in <pre> tag
  my $form;
  eval {
    $self->cgi(Bibliotech::CGI->new) unless defined $self->cgi;  # can happen on early exception
    my $rpf  = Bibliotech::Component::ReportProblemForm->new({bibliotech => $self, exception => $text});
    $form = $rpf->html_content->content('reportproblem', 0, 1);
  };
  $form = "<pre>$@</pre>\n" if $@;
  my @body = $self->replace_text_variables([<$fh>], undef, {report => $text, form => $form}) or die 'no body';
  $fh->close;
  my $r = $self->request;
  $r->send_http_header(HTML_MIME_TYPE);
  $r->print(@body);
  return OK;
}

# display an error as a text dump
sub exception_handler_text {
  my ($self, $text, $r) = @_;
  $r = $self->request unless defined $r;
  $r->send_http_header(TEXT_MIME_TYPE);
  $r->print("Internal Error\n\n");
  $r->print("This web application is experiencing an error. We apologize for the inconvenience.\n\n");
  $r->print($text);
  return OK;
}

# handle an error bubbled up
sub exception_handler {
  my ($self, $text) = @_;
  eval {
    $self->exception_handler_html($text);
  };
  return OK unless $@;
  eval {
    $self->exception_handler_text($text);
  };
  return OK unless $@;
  return SERVER_ERROR;
}

# accept verb, output format, and page keyword and return the perl classname to handle it
sub page_class {
  my $self   = shift;
  my $verb   = shift or die 'no verb';
  my $output = shift or die 'no output';
  my $page   = shift or die 'no page';

  $page =~ s/^(.)(.*)$/uc($1).lc($2)/e;

  if ($output eq 'data') {
    $verb =~ s/^(.)(.*)$/uc($1).lc($2)/e;
    return "Bibliotech::WebAPI::Action::${page}::${verb}";
  }

  return "Bibliotech::Page::${page}";
}

# same as page_class() but handle unimplemented Web API actions
sub page_class_or_not_implemented {
  my $class = shift->page_class(@_);
  return $class unless $class =~ /Bibliotech::WebAPI::/;
  return $class if UNIVERSAL::can($class, 'answer');
  return 'Bibliotech::WebAPI::Action::NotImplemented';
}

# handler for most hits, the queries
sub query_handler {
  my $self    = shift;
  my $r       = $self->request;
  my $verb    = $r->method;
  my $command = $self->command;
  my $page    = $command->page_or_inc;
  my $fmt     = $command->output;

  die "unknown format requested: $fmt\n" unless $fmt =~ /^$OUTPUTS_ALTERNATION$/;

  return $self->explainable_http_code(HTTP_SERVICE_UNAVAILABLE, 'service paused (early)')
      if Bibliotech::Throttle::do_service_paused_early($self);

  if ($page eq 'inc' or $page eq 'none') {   # static page - do some pre-checks so we can bail if it will not be possible
    my $rc = Bibliotech::Component::Inc->check_filename($r, NOT_FOUND, FORBIDDEN, OK);
    return $self->explainable_http_code($rc, 'inc static file check on filename') if $rc != OK;
  }

  if ($page eq 'noop' and $fmt ne 'data') {
    return $self->explainable_http_code(NOT_FOUND, 'noop is a data command only');
  }

  my $pageobj = $self->page_class_or_not_implemented($verb, $fmt, $page)->new({bibliotech => $self});

  my ($last_updated, $last_updated_without_login)
      = $pageobj->last_updated($fmt, Bibliotech::Throttle::is_service_paused_at_all());

  if ($CLIENT_SIDE_HTTP_CACHE) {
    $r->set_last_modified($last_updated) if $last_updated;
    my $rc = $r->meets_conditions;
    #return $self->explainable_http_code($rc, 'meets conditions (browser caching negotiation)') if $rc != OK;
    return $rc if $rc != OK;
  }

  return $self->explainable_http_code(HTTP_SERVICE_UNAVAILABLE, 'service paused')
      if Bibliotech::Throttle::do_service_paused($self);
  if ($page ne 'inc') {
    return $self->explainable_http_code(HTTP_SERVICE_UNAVAILABLE, 'bot throttle')
	if Bibliotech::Throttle::do_bot_throttle($self);
    return $self->explainable_http_code(HTTP_SERVICE_UNAVAILABLE, 'dynamic throttle')
	if Bibliotech::Throttle::do_dynamic_throttle($self);
  }

  my $cgi = Bibliotech::CGI->new or die 'cannot create Bibliotech::CGI object';
  if (my $cgi_error = $cgi->cgi_error) {
    die $cgi_error;
  }
  $self->cgi($cgi);
  my $debug = defined $cgi->param('debug');

  my $result;
  eval {
    my $num = $command->num;
    ($num <= 1000 or $fmt eq 'data') or die "Sorry the maximum num setting is 1000.\n";
    my $func = $fmt.'_content';
    my $getresult = sub { $result = $pageobj->$func; };
    if ($r->user or          # don't use cache - their browser and our 304's should be sufficient
	$verb ne 'GET' or    # cannot cache POST's
	$page eq 'error' or  # cannot cache errors
	$debug               # let debug flag override cache as well
	) {
      $getresult->();
    }
    else {
      # visitor - use cache
      my $cache_key = Bibliotech::Cache::Key->new($self,
						  class => __PACKAGE__,
						  method => 'query_handler',
						  path => undef);
      my $memcache = $self->memcache;
      if (my $cache_entry = $memcache->get_with_last_updated
	  ($cache_key,
	   $last_updated_without_login,
	   $self->is_navigating_inside_site ? undef : $FRESH_VISITOR_LAZY_UPDATE,
	   1)) {
	$result = $cache_entry;
      }
      else {
	$getresult->();
	$memcache->set_with_last_updated($cache_key,
					 $result,
					 $last_updated_without_login) unless $debug;
      }
    }
  };

  if (my $e = $@) {
    if ($e =~ / at .* line /) {  # priority to recognizable coding errors
      die $e;
    }
    elsif ($e =~ /\bLocation: (.*)$/) {  # exception mechanism to redirect
      chomp (my $uri = $1);
      $r->headers_out->set(Location => $uri);
      $r->status(REDIRECT);
      #return $self->explainable_http_code(REDIRECT, 'redirect (Location exception)');
      return REDIRECT;
    }
    elsif ($e =~ /\bHTTP (\d+)$/) {  # exception mechanism to send alternate HTTP code
      my $http_code = $1;
      return $http_code if $http_code =~ /^[23]/;
      return $self->explainable_http_code($http_code, 'forced code (HTTP integer exception)');
    }
    die $e;
  }

  my ($o, $final_rc, $extension, $mime_type) = _get_extension_and_type
      ($fmt,
       $fmt ne 'data' ? ($result, OK)
                      : (Bibliotech::Page->new({bibliotech => $self})->tt_content_for_web_api($result),
			 $result->code),
       $command->inc_filename);
  return $self->explainable_http_code($final_rc, 'get_extension_and_type says not found')
      if $final_rc == NOT_FOUND;

  my $download = $cgi->param('download') || '';
  if ($download eq 'file') {
    my $filename = $command->canonical_uri_as_downloadable_filename($extension);
    $r->headers_out->set('Content-Disposition' => 'attachment; filename='.$filename);
  }
  $r->content_type(join('; ',
			$download eq 'view' ? viewable_mime_type($mime_type) : $mime_type,
			'charset=UTF-8'));

  # send cache control or expires headers depending on component choices and current HTTP client protocol
  if ($NO_CACHE_HEADER || $self->no_cache) {
    $r->no_cache(1);  # instruct client not to cache, so expiration is not an issue
  }
  else {
    if ($r->protocol =~ /(\d\.\d)/ && $1 >= 1.1) {
      $r->header_out('Cache-Control' => 'max-age='.$CACHE_AGE_HEADER);  # more modern way
    }
    else {
      my $timestamp = Bibliotech::Util::time() + $CACHE_AGE_HEADER;
      my $timestr = HTTP::Date::time2str($timestamp); # Apache::Util::ht_time() gives an error sometimes
      $r->header_out('Expires' => $timestr);  # older way
    }
  }

  my $raw = is_utf8($o) ? encode_utf8($o) : $o;
  $r->status(code_for_r_status($final_rc));
  $r->headers_out->add('Content-Length' => length($raw));
  $r->send_http_header;
  $r->print($raw);
  return OK;  # at this point we don't need help from Apache, we've displayed our page
              # and in fact Apache sometimes appends a generated error page if this is not OK
              # e.g. with GET /data/remove being NI
  #return code_for_handler_return($final_rc);
}

# helper routine: provide format, result, and HTTP status code and get back same plus extension and type
# in the case that the format is not known you'll get back appropriate 404
sub _get_extension_and_type {
  my ($fmt, $result, $rc, $inc_filename) = @_;
  return ($result, $rc, HTML_EXTENSION,    HTML_MIME_TYPE)    if $fmt eq 'html' and !$inc_filename;
  return ($result, $rc, RSS_EXTENSION,     RSS_MIME_TYPE)     if $fmt eq 'rss';
  return ($result, $rc, RIS_EXTENSION,     RIS_MIME_TYPE)     if $fmt eq 'ris';
  return ($result, $rc, GEO_EXTENSION,     GEO_MIME_TYPE)     if $fmt eq 'geo';
  return ($result, $rc, HTML_EXTENSION,    HTML_MIME_TYPE)    if $fmt eq 'tt';
  return ($result, $rc, BIBTEX_EXTENSION,  BIBTEX_MIME_TYPE)  if $fmt eq 'bib';
  return ($result, $rc, ENDNOTE_EXTENSION, ENDNOTE_MIME_TYPE) if $fmt eq 'end';
  return ($result, $rc, MODS_EXTENSION,    MODS_MIME_TYPE)    if $fmt eq 'mods';
  return ($result, $rc, TEXT_EXTENSION,    TEXT_MIME_TYPE)    if $fmt eq 'txt';
  return ($result, $rc, TEXT_EXTENSION,    TEXT_MIME_TYPE)    if $fmt eq 'plain';
  return ($result, $rc, WORD_EXTENSION,    WORD_MIME_TYPE)    if $fmt eq 'word';
  return ($result, $rc, RDF_EXTENSION,     RDF_MIME_TYPE)     if $fmt eq 'data';
  if ($fmt eq 'html' and $inc_filename) {
    my ($ext) = $inc_filename =~ /(\.\w{1,5})$/;
    if ($ext) {
      return ($result, $rc, $ext, CSS_MIME_TYPE)        if $ext eq '.css';
      return ($result, $rc, $ext, JAVASCRIPT_MIME_TYPE) if $ext eq '.js';
      return ($result, $rc, $ext, TEXT_MIME_TYPE)       if $ext eq '.txt';
    }
    return ($result, $rc, $ext, HTML_MIME_TYPE);
  }
  return (undef, NOT_FOUND, undef, undef);
}

sub is_navigating_inside_site {
  my $self     = shift;
  my $referer  = $self->request->header_in('Referer') or return;
  my $location = $self->location;
  return 1 if $referer =~ /^\Q$location\E/;
  return;
}

# helper routine to determine a MIME type for viewing
sub viewable_mime_type {
  my $type = shift;
  return $type if $type =~ m|^text/|;
  return 'application/xml' if $type =~ m|^application/(?:.+\+)?xml$|;
  return 'text/plain';
}

# called for /sabotage URI for debugging
sub sabotage_handler {
  die "Hello, this is an exception generated intentionally to test exceptions.\n";
}

# handler for /click to register a hit on a trackable link
sub click_handler {
  my $self = shift;
  my $cgi  = $self->cgi || Bibliotech::CGI->new;
  my $user = $self->user;
  my $r    = $self->request;
  my $src  = $cgi->unescape($cgi->param('src'))  or die "Must give a source to click handler!\n".
      Dumper($r->uri || undef,
	     $r->args || undef,
	     {map {$_ => $cgi->param($_)} $cgi->param},
	     $cgi->param('src') || undef,
	     $cgi->unescape($cgi->param('src')) || undef);
  my $dest = $cgi->unescape($cgi->param('dest')) or die "Must give a destination to click handler! (src: $src)\n";
  my $name = defined $user ? $user->username : undef;
  my $ip   = $r->connection->remote_ip;
  Bibliotech::Clicks::Log::add($src, $dest, $name, $ip);
  $r->headers_out->set(Location => $dest);
  $r->status(REDIRECT);
  return REDIRECT;
}

# helper routine that accepts an HTTP status code and returns it, or 200 for 0
sub code_for_r_status {
  my $num = pop;
  return HTTP_OK if $num == OK;
  return $num;
}

# helper routine that accepts an HTTP status code and returns it, or 0 for 200
sub code_for_handler_return {
  my $num = pop;
  return OK if $num == HTTP_OK;
  return $num;
}

# handler for WebCite, just for citation
sub citation_handler {
  Bibliotech::WebCite::handler(shift->request);
}

1;
__END__
