# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component class provides a base class intended to be
# overridden by individual component classes. A component is a piece of code
# that returns an HTML block that is one piece of a larger page layout.
# Other formats like RSS and RIS only use one component to provide all the
# output.

package Bibliotech::Component;
use strict;
use base 'Class::Accessor::Fast';
use Encode qw/decode_utf8 encode_utf8 is_utf8/;
use List::Util qw/first/;
use Bibliotech::Config;
use Bibliotech::Util;
use Bibliotech::Component::Inc;
use Bibliotech::Cookie;
use Bibliotech::Parser;
use Data::Dumper;  # actually used

our $PID_FILE = Bibliotech::Config->get('PID_FILE') || '/var/run/httpd.pid';

__PACKAGE__->mk_accessors(qw/bibliotech parts options last_updated_cache memcache_key main_title_discovered main_title_set/);

BEGIN {
  no strict 'refs';
  *{$_.'_content'} = eval "sub { die \"called for undefined $_ content (\".ref(\$_[0]).\")\n\"; }"
      foreach (@Bibliotech::Parser::OUTPUTS);
}

# plain_content() is created above - although a component can technically offer this it is never called for the web site
# inputs:
#   $verbose - 1/0 - for 0 keep the return value one line
# outputs:
#   scalar or list of text output

# html_content() is created above
# inputs:
#   $class - CSS class base name suggestion for any CSS classes you write out
#   $verbose - 1/0 generally verbose=0 means the component is called as a sidebar
#   $main - 1/0 is this component the main one on this page
# output:
#   Bibliotech::Page::HTML_Content object
# ...or in special cases die with one of these values:
#   "Location: x\n" - will cause immediate redirect to the URL x
#   "HTTP xxx\n" - will case immediate HTTP response with same response code of the integer xxx provided

# rss_content() is created above
# inputs:
#   $verbose - 1/0 - add more elements when verbose
# outputs:
# either...
#   a list of hashref's of item data e.g. {title => ..., link => ...}
# ...or...
#   a full RSS document as a string


# configuration key retrieval helper
sub cfg {
  Bibliotech::Config::Util::cfg(@_);
}

# same but required
sub cfg_required {
  Bibliotech::Config::Util::cfg_required(@_);
}

sub content {
  shift->html_content(@_);  # default to HTML
}

# override this to return a list of one or more of these values:
#       'DBI' - last update time of database, i.e. this component used data from the database
# '/filename' - update timestamp for a given filename, i.e. this component shows data from this file
#     'LOGIN' - last login or logout time, i.e. this component displays user data (remember variable replacement!)
#       'PID' - last Apache startup time
#         123 - Unix timestamp, i.e. figure the time another way
#       'NOW' - current time, component is always different
#       undef - fixed output
# Notes:
#  'PID' is currently included by default so no component module need mention it
#  'LOGIN' should be included by any component that uses Bibliotech::*::*_content() calls (because they often
#    give user-centic output) or any component that uses file includes (because the variable replacements can be
#    user-centric) but you can skip it if you know for sure these cases are false
sub last_updated_basis {
  undef;
}

sub last_updated_basis_includes_login {
  grep($_ eq 'LOGIN', shift->last_updated_basis);
}

sub last_updated_calc {
  my ($self, $basis, $cache) = @_;
  return undef unless defined $basis;
  $cache ||= {};
  return $cache->{$basis} if defined $cache->{$basis};
  return $cache->{$basis} = Bibliotech::DBI->db_get_last_updated if $basis eq 'DBI';
  $basis = $PID_FILE if $basis eq 'PID';
  return $cache->{$basis} = (stat $basis)[9] if $basis =~ m|^/|;
  return $cache->{$basis} = $self->bibliotech->request->notes->{logintime} if $basis eq 'LOGIN';
  if ($basis eq 'USER') {
    my $user = $self->bibliotech->user;
    return defined $user ? $cache->{$basis} = $user->updated : undef;
  }
  return $basis if $basis =~ /^\d+$/;
  return $cache->{$basis} = Bibliotech::Util::time() if $basis eq 'NOW';
  die "invalid last updated basis value: $basis";
}

# return a hashref of timestamps based on the result from last_updated_basis() and an optional hashref to serve as a cache
sub last_updated_hash {
  my ($self, $cache_ref) = @_;
  my %times;
  foreach my $basis ($self->last_updated_basis) {
    my $time = $self->last_updated_calc($basis, $cache_ref);
    $times{$basis} = ref $time ? $time->epoch : $time;
  }
  return wantarray ? %times : \%times;
}

# return a timestamp based on the result from last_updated_basis() and an optional hashref to serve as a cache
# in list context, returns all timestamps with undef's, suitable for matchup to last_updated_basis()
# in scalar context, selects the most recent timestamp and returns it
sub last_updated {
  my ($self, $cache_ref, $disregard_login) = @_;
  my $cached = $self->last_updated_cache || [undef, undef];
  my $time = $cached->[$disregard_login ? 1 : 0];
  return $time if defined $time;
  my %times = $self->last_updated_hash($cache_ref);
  undef $times{LOGIN} if $disregard_login;
  my @times = grep(defined $_, values %times);
  $time = @times ? (sort {$b <=> $a} @times)[0] : undef;
  $cached->[$disregard_login ? 1 : 0] = $time;
  $self->last_updated_cache($cached);
  return $time;
}

# return a number of seconds past last_updated() that it's acceptable to go on using old results
# undef = disable
# 0 = effectively disable, but use undef instead
# 1 = use a reasonable system default (currently 2 hours)
sub lazy_update {
  0;
}

sub memcache_check {
  my ($self, @key) = @_;
  my $options = $self->options || {};
  return undef if defined $options->{cache} and !$options->{cache};
  my $bibliotech = $self->bibliotech;
  return undef if $bibliotech->cgi->param('debug');
  my $key;
  if (@key) {
    $self->memcache_key($key = Bibliotech::Cache::Key->new(@key));
  }
  else {
    $key = $self->memcache_key;
  }
  return $bibliotech->memcache->get_with_last_updated($key,
						      $self->last_updated(undef, 1),
						      $self->lazy_update,
						      1);
}

sub memcache_save {
  my ($self, $value) = @_;
  my $options = $self->options || {};
  return $value if defined($options->{cache}) and !$options->{cache};
  my $bibliotech = $self->bibliotech;
  return $value if $bibliotech->cgi->param('debug');
  my $key = $self->memcache_key or die 'set key first';
  $bibliotech->memcache->set_with_last_updated($key,
					       $value,
					       $self->last_updated(undef, 1));
  return $value;
}

sub heading_dynamic {
  shift->bibliotech->command->page_or_inc_filename;
}

# if this component is the main component on the page, what should be the page heading?
sub main_heading {
  my $self = shift;
  my $title = $self->main_title_set;
  return $title if $title;
  $title = $self->main_title_discovered;
  return $title if $title;
  return $self->heading_dynamic(1);  # 1 means main
}

# if this component is the main component on the page, what should be the document title?
# defaults to using two accessors: main_title_set, main_title_discovered, or calling basic_main_title()
sub main_title {
  my $self = shift;
  my $title = $self->main_title_set;
  return $title if $title;
  $title = $self->main_title_discovered;
  if ($title) {
    my $sitename = $self->bibliotech->sitename;
    $title = "$sitename: $title" unless $title =~ /^\Q$sitename\E/;
    return $title;
  }
  return $self->basic_main_title;
}

# helper routine you can also call directly if you like
sub basic_main_title {
  my $self = shift;
  return $self->bibliotech->sitename.': '.$self->main_heading;
}

# if this component is used alone for a fomat like RSS what should the description be?
sub main_description {
  shift->main_title;
}

sub cleanparam {
  my ($self, $value, %options) = @_;
  return undef if !defined $value;
  return '' if $value eq '';
  unless ($options{skip_decode}) {
    $value = decode_utf8($value) || decode_utf8(encode_utf8($value)) || $value unless is_utf8($value);
  }
  unless ($options{keep_whitespace}) {
    $value =~ s|^\s+||;
    $value =~ s|\s+$||;
  }
  return $value;
}

# accept a CGI object, a form name, and a list of field names, and return a Javascript focus() command
# to go to the first empty field, or undef if they are all filled in
sub firstempty {
  my ($self, $cgi, $formname, @params) = @_;
  my $fieldname = eval {
    if (ref $params[0]) {
      my ($params_ref, $validation_exception) = @params;
      return $validation_exception->field if defined $validation_exception;
      @params = @{$params_ref};
    }
    return first { !$cgi->param($_) } @params;
  };
  die $@ if $@;
  return unless $fieldname;
  return "document.forms.$formname.$fieldname.focus()";
}

sub pleaseregister {
  my ($self, $capitalize) = @_;
  my $cgi = $self->bibliotech->cgi;
  return ($capitalize ? 'P' : 'p').'lease '.$cgi->a({href => $self->bibliotech->location.'register', class => 'nav'}, 'register').'.';
}

sub registernote {
  my ($self) = @_;
  my $cgi = $self->bibliotech->cgi;
  return $cgi->p('Not a member yet?', $self->pleaseregister(1));
}

sub remember_current_uri {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $r          = $bibliotech->request;
  my $args       = $r->args;
  my $uri        = $r->uri . ($args ? '?'.$args : '');
  my $cookie     = Bibliotech::Cookie->login_redirect_cookie($uri, $bibliotech);
  $r->err_headers_out->add('Set-Cookie' => $cookie);
  return $cookie;
}

sub getlogin {
  shift->bibliotech->user;
}

sub saylogin {
  my ($self, $task) = @_;
  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $command    = $bibliotech->command;
  my $cgi        = $bibliotech->cgi;
  my $login      = $command->is_popup ? 'loginpopup' : 'login';
  my $msg        = $cgi->div($cgi->h1('Login Required'),
			     $cgi->p('You must', $cgi->a({href => $location.$login, class => 'nav'}, 'login').
				     ($task ? ' '.$task : '').'.'));
  $self->remember_current_uri unless $command->is_login_or_logout;
  $self->discover_main_title($msg);
  return Bibliotech::Page::HTML_Content->simple($msg);
}

sub include {
  my ($self, $filename, $class, $verbose, $main, $variables, $variables_code_obj) = @_;
  # set cache to false because this is a helper for components and components are expected to cache themselves
  # without setting cache to zero there would be double caching and that introduces more bugs than it's worth
  my $inc = new Bibliotech::Component::Inc ({bibliotech => $self->bibliotech,
					     options => {filename => $filename,
							 variables => $variables,
							 variables_code_obj => $variables_code_obj,
							 cache => 0}
					   });
  return $inc->content($class, $verbose, $main)->content;
}

sub include_basis {
  my ($self, $filename) = @_;
  my $inc = new Bibliotech::Component::Inc ({bibliotech => $self->bibliotech});
  return $inc->option_filename($filename);
}

sub tt {
  my ($self, $filename_without_root_or_extension, $special_vars_hashref, $validation_exception) = @_;
  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;
  my $docroot    = $bibliotech->docroot;
  my $command    = $bibliotech->command;
  (my $filename_without_root = $filename_without_root_or_extension) =~ s!((^|/)\w+)$!$1.tt!;

  my $escaped = sub { local $_ = shift; s/\"/&quot;/g; $_; };

  my $doc = Bibliotech::Page::tt_process_calc
      (Bibliotech::Page::tt_content_template_toolkit_object
       (Bibliotech::Page::find_template_root_calc($docroot)),
       $filename_without_root,
       _combine_hashrefs_with_clash_error
       (tt_general_vars =>
	{Bibliotech::Page::tt_general_vars_calc(undef, $bibliotech, $command)},
	component_general_vars =>
	{component                => $self,
	 sticky                   => sub { my ($name, $default) = @_;
					   $default = '' unless defined $default;
					   return $default unless $name;
					   my $value = $self->cleanparam($cgi->param($name));
					   return $default unless defined $value;
					   my $ref = ref $value or return $escaped->($value);
					   my $str = "$value";
					   die "sticky() tried to stringify param $name but got $str: ".Dumper($value)
					       if $str =~ /^\Q$ref\E/;
					   return $escaped->($str);
					 },
	 has_validation_error_for => sub { return unless defined $validation_exception;
					   return $validation_exception->is_for(@_);
					 },
	 validation_error_field   => sub { return unless defined $validation_exception;
					   return $validation_exception->field;
					 },
	 validation_error         => sub { return unless defined $validation_exception;
					   return $validation_exception->message;
					 },
	 main_title_set           => sub { $self->main_title_set(shift); ''; }},
	special_vars =>
	$special_vars_hashref));

  $self->discover_main_title($doc);

  return $doc;
}

sub _combine_hashrefs_with_clash_error {
  my %def = @_;  # keys are names, values are hashrefs
  my (%trace, %final);
  while (my ($src, $hash) = each %def) {
    next unless defined $hash;
    my %hash = %{$hash};
    foreach my $key (keys %hash) {
      die "Variable conflict: $key key given from both $trace{$key} and $src" if $trace{$key} and $final{$key};
      $trace{$key} = $src;
      $final{$key} = $hash{$key};
    }
  }
  return \%final;
}

sub discover_main_title {
  my ($self, $doc) = @_;
  my $discovered_title = _scan_for_title($doc) or return;
  return $self->main_title_discovered($discovered_title);
}


sub _scan_for_title {
  local $_ = shift;
  return $1 if /<h1.*?>(.*?)<\/h1>/mi;
  return $1 if /<h2.*?>(.*?)<\/h2>/mi;
  return;
}

# call with a sub ref to do some tests that die in the case of an
# error and this sub will just wrap them in an object with a
# guaranteed field name for you
sub validate_tests {
  my ($self, $default_field, $tests_sub) = @_;
  eval { $tests_sub->(); };
  if ($@) {
    die $@ if UNIVERSAL::isa($@, 'Bibliotech::Component::ValidationException');
    die $self->validation_exception(ref $@ eq 'ARRAY' ? @{$@} : ($default_field => $@));
  }
  return 1;
}

sub on_continue_param_return_close_library_or_confirm {
  my ($self, $continue, $uri, $confirm_sub) = @_;
  die "Location: $uri\n" if $continue eq 'return';
  if ($continue eq 'close') {
    return Bibliotech::Page::HTML_Content->new({html_parts => {main => ''},
						javascript_onload => 'window.close()'});
  }
  if ($continue eq 'library') {
    my $location = $self->bibliotech->location;
    my $username = $self->bibliotech->user->username;
    die "Location: ${location}user/$username\n";
  }
  return Bibliotech::Page::HTML_Content->simple($confirm_sub->());
}

# convenience routine to take two parameters and build an object
sub validation_exception {
  my ($self, $field, $msg) = @_;
  return unless defined $msg;
  return $msg if UNIVERSAL::isa($msg, 'Bibliotech::Component::ValidationException');
  return Bibliotech::Component::ValidationException->new({field => $field, message => $msg});
}

package Bibliotech::Component::ValidationException;
use base 'Class::Accessor::Fast';
use List::MoreUtils qw/any/;
use overload '""' => \&as_string, fallback => 1;

__PACKAGE__->mk_accessors(qw/field message/);

# needed here becuase something about the way $@ gets tested by regexes messes up overload '""' => 'message'
sub as_string {
  scalar shift->message;
}

sub is_for {
  my $self = shift;
  my $field = $self->field or return;
  return any { $field eq $_ } @_;
}

1;
__END__
