# Copyright 2007 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::WebCite class handles requests to a stand-alone
# citation system that should be runnable as an Apache handler
# separately from the rest of the system.

=pod

How to setup WebCite.

Setup the code for Bibliotech.

You DO need a full copy of the code.
You DO need Apache.
You do NOT need MySQL.
You do NOT need Memcache.
You do NOT need CGI::Wiki.

You should create a bibliotech config file; the WEBCITE section applies to the variables herein,
and the citation modules will refer to the file as well. You can use your normal file if you run
an instance of Connotea Code.

=cut

package Bibliotech::WebCite;
use strict;
use base 'Class::Accessor';
__PACKAGE__->mk_accessors(qw/request cgi log/);
use Bibliotech::Config required => \&cfg_required_fallback;
use Bibliotech::ApacheProper;
use Bibliotech::Log;
use Bibliotech;
use Bibliotech::DBI;
use Bibliotech::Page;
use Bibliotech::Const;
use Bibliotech::BibUtils qw/ris2xml/;
use Storable qw/lock_store lock_retrieve/;
use File::Path qw/mkpath/;
use JSON;

our $CACHE_ENABLED = Bibliotech::Config::get('WEBCITE', 'CACHE_ENABLED'); defined $CACHE_ENABLED or $CACHE_ENABLED = 1;
our $CACHE_PATH    = Bibliotech::Config::get('WEBCITE', 'CACHE_PATH') || '/var/cache/webcite/';
our $CACHE_TIMEOUT = Bibliotech::Config::get('WEBCITE', 'CACHE_TIMEOUT') || 90*24*60*60;  # 90 days
our $LOG_ENABLED   = Bibliotech::Config::get('WEBCITE', 'LOG_ENABLED'); defined $LOG_ENABLED or $LOG_ENABLED = 1;
our $LOG_FILE      = Bibliotech::Config::get('WEBCITE', 'LOG_FILE') || '/var/log/webcite.log';

sub handler {
  my $r    = shift;
  my $cgi  = CGI->new;
  my $log  = Bibliotech::Log->new($LOG_FILE);
  my $self = bless {request => $r, cgi => $cgi, log => $log}, __PACKAGE__;
  my $rc   = eval {
    my $uri =    $cgi->unescape($cgi->param('uri')) or return $self->form;
    my $fmt = lc($cgi->unescape($cgi->param('fmt')));
    $fmt =~ /^(?:ris|mods|json)$/ or return $self->form;  # sanity check
    return $self->dispatch($uri, $fmt);
  };
  return $self->fatal_error($@) if $@;
  return $rc;
}

sub form {
  my ($self) = @_;
  my $r = $self->request;
  my $cgi = $self->cgi;
  $r->send_http_header(HTML_MIME_TYPE);
  $r->print($cgi->start_html('Get Citation'),
	    $cgi->h1('Get Citation'),
	    $cgi->start_form(-method => 'POST',
			     -action => $r->uri,
			     -enctype => 'application/x-www-form-urlencoded'),
	    $cgi->table($cgi->Tr($cgi->td(['URI:',
					   $cgi->textfield(-name => 'uri',
							   -size => 80,
							   -maxlength => 255)])),
			$cgi->Tr($cgi->td(['Format:',
					   $cgi->popup_menu(-name => 'fmt',
							    -values => [qw/ris mods json/])])),
			$cgi->Tr($cgi->td(['&nbsp;',
					   $cgi->submit('Query')]))),
	    $cgi->end_form,
	    $cgi->p('Web Citation Service based on',
		    $cgi->a({href => 'http://www.connotea.org/code'}, 'Connotea Code'),
		    '(see Bibliotech::WebCite).'),
	    $cgi->end_html);
  OK;
}

sub finish_bookmark {
  my ($bookmark, $citation) = @_;
  $bookmark->citation($citation);
  $bookmark->set_correct_hash;
  return $bookmark;
}

sub citation {
  my $uri        = shift;
  my $bibliotech = Bibliotech->new;
  my $bookmark   = Bibliotech::Unwritten::Bookmark->construct({url => $uri});
  my ($revised_bookmark, $citations, $module_str) = $bibliotech->pull_citation_calc($bookmark, undef, 0);
  return if not defined $citations;
  my $result     = $citations->fetch;
  return if not defined $result;
  my $citation   = Bibliotech::Unwritten::Citation->from_citationsource_result($result, 0, $module_str);
  return finish_bookmark(defined $revised_bookmark ? $revised_bookmark : $bookmark, $citation);
}

# e.g. 'http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?db=pubmed&cmd=Retrieve&dopt=AbstractPlus&list_uids=17328115&query_hl=1&itool=pubmed_docsum' -> 'http/www.ncbi.nlm.nih.gov/entrez/query.fcgi__db_pubmed_cmd_Retrieve_dopt_AbstractPlus_list_uids_17328115_query_hl_1_itool_pubmed_docsum'
sub uri_to_cache_path {
  my $uri = shift;
  local $_ = UNIVERSAL::isa($uri, 'URI') ? $uri->as_string : $uri;
  s|^(\w+):|$1|;
  s|//+|/|g;
  s|\?|__|g;
  s|[&=]|_|g;
  return join('', $CACHE_PATH, $_, '.result');
}

sub load_citation {
  my $uri = shift;
  my $file = uri_to_cache_path($uri);
  return (undef, 0) unless -e $file;
  return (undef, 0) if defined $CACHE_TIMEOUT and (stat($file))[9] < time - $CACHE_TIMEOUT;
  return (lock_retrieve($file)->{result}, 1);
}

sub lock_store_with_mkpath {
  my ($result, $path) = @_;
  (my $dir = $path) =~ s|/[^/]*$||;
  eval { mkpath($dir); };
  die "problem with mkpath(\'$dir\') from original path \'$path\': $@" if $@;
  lock_store({result => $result}, $path);
}

sub save_citation {
  my ($uri, $result) = @_;
  lock_store_with_mkpath($result, uri_to_cache_path($uri));
}

sub possibly_cached_citation {
  my $uri = shift;
  my $result;
  if ($CACHE_ENABLED) {
    my $matched;
    ($result, $matched) = load_citation($uri);
    return ($result, 1) if $matched;  # even if undef
  }
  $result = citation($uri);
  if ($CACHE_ENABLED) {
    save_citation($uri, $result);
  }
  return ($result, 0);
}

sub dispatch {
  my ($self, $uri, $fmt) = @_;
  my ($bookmark, $from_cache) = eval { possibly_cached_citation($uri) };
  my $error = $@;
  $self->log_entry($uri, $fmt, defined $bookmark, $from_cache, $error);
  return $self->error($uri, $error) if $error;
  return $self->none($uri) unless defined $bookmark;
  return $self->fmt($bookmark, $fmt);
}

sub fmt {
  my ($self, $bookmark, $fmt) = @_;
  my $r            = $self->request;
  my $type_func    = $fmt.'_type';
  my $content_func = $fmt.'_content';
  my $type         = $self->$type_func;
  my $content      = $self->$content_func($bookmark);
  $r->send_http_header($type);
  $r->print($content);
  OK;
}

sub ris_type {
  RIS_MIME_TYPE;
}

sub ris_content {
  Bibliotech::Page::hash2ris(pop->ris_content(1));
}

sub mods_type {
  MODS_MIME_TYPE;
}

sub mods_content {
  ris2xml(ris_content(@_));
}

sub json_type {
  'text/javascript';
}

sub json_content {
  objToJson(pop, {convblessed => 1, selfconvert => 1, pretty => 1, indent => 2})."\n";
}

sub none {
  my ($self, $uri) = @_;
  my $r = $self->request;
  $r->status(NOT_FOUND);
  $r->send_http_header(TEXT_MIME_TYPE);
  $r->print('No citation.');
  OK;
}

sub error {
  my ($self, $uri, $error) = @_;
  return $self->fatal_error(join("\n", $uri, $error));
}

sub fatal_error {
  my ($self, $error) = @_;
  my $r = $self->request;
  $r->status(SERVER_ERROR);
  $r->send_http_header(TEXT_MIME_TYPE);
  $r->print(join("\n", 'ERROR', '', $error, ''));
  OK;
}

sub cfg_required_fallback {
  return 'WebCite'        if $_[0] eq 'SITE_NAME';
  return 'root@localhost' if $_[0] eq 'SITE_EMAIL';
  return;
}

sub log_entry {
  return unless $LOG_ENABLED;
  my ($self, $uri, $fmt, $any, $cache, $err) = @_;
  $self->log->info(join(' ', ($fmt,
			      $any ? 1 : 0,
			      $err ? "[$err]" : 'ok',
			      $cache ? 'load' : 'calc',
			      $uri)));
}


package JSON::Converter;
# JSON 1.09 died when encountering URI objects inside nested structures
# This code fixes the problem.
# Also submitted a fix to CPAN: http://rt.cpan.org/Public/Bug/Display.html?id=25291

# redefined directly here -- too hard to subclass JSON::Converter
# because of its usage of non-class sub calls throughout
no warnings;

# add SCALAR
sub _blessedToNormal {
    UNIVERSAL::can($_[0], 'json_content') and return _blessedToNormal($_[0]->json_content);
    my $type  = _getObjType($_[0]);
    return $type eq 'HASH'   ? _blessedToNormalHash($_[0])   : 
           $type eq 'ARRAY'  ? _blessedToNormalArray($_[0])  :
           $type eq 'SCALAR' ? _blessedToNormalScalar($_[0]) :
	   $_[0];
}

# define SCALAR treatment
sub _blessedToNormalScalar {
    my ($obj) = @_;
    my $res;

    die "circle ref!" if(grep { overload::AddrRef($_) eq overload::AddrRef($obj) }
                          @JSON::Converter::_blessedToNormal::obj_addr);

    push @JSON::Converter::_blessedToNormal::obj_addr, $obj;

    $res = _blessedToNormal($$obj);

    pop @JSON::Converter::_blessedToNormal::obj_addr;

    return $res;  # JSON can't really do scalar refs so it can't be \$res
}

1;
__END__
