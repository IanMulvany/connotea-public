# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file provides various utility functions.

package Bibliotech::Util;
use strict;
use base 'Exporter';
use LWP::UserAgent;
use Encode qw/encode encode_utf8 decode decode_utf8 is_utf8/;
use HTML::Sanitizer;
use HTML::Entities;
use DateTime;
use IO::File;
use Time::HR;
use Bibliotech::UserAgent;
# NOTE although we don't load Bibliotech::DBI or Bibliotech::Config:
# if Bibliotech::DBI *is* loaded:
#   time() and now() return database times not OS times
# if Bibliotech::Config *is* loaded:
#   notify() uses the configured SENDMAIL instead of a default
# we don't load them in order to keep Bibliotech::Util lightweight
# when used in testing

our @EXPORT_OK = qw(&clean_whitespace
		    &text_encode_wide_characters
		    &text_decode_wide_characters
		    &text_decode_wide_characters_to_xml_entities
		    &text_encode_newlines
		    &text_decode_newlines
		    &ua
		    &ua_get_response
		    &ua_decode_content
		    &ua_get_content_decoded
		    &ua_extract_title
		    &ua_clean_title
		    &force_to_utf8
		    &undo_force_to_utf8
		    &clean_block
		    &is_html_mime_type
		    &is_html_content_type
		    &ua_get_response_and_content_and_title_decoded
		    &ua_act
		    &get
		    &sanitize
                    &without_hyperlinks
                    &without_hyperlinks_or_trailing_spaces
                    &without_spaces
		    &speech_join
		    &encode_xml_utf8
		    &encode_xhtml_utf8
		    &encode_markup_xhtml_utf8
		    &now
		    &time
		    &notify
		    &cfg
		    &cfg_required
		    &plural
                    &commas
		    &decode_entities
		    &hrtime
		    &split_page_range
		    &parse_author
		    &split_names
		    &remove_et_al
		    &split_author_names
                    &divide
                    &percent
		    );

# remove leading and trailing whitespace and convert all multi-whitespace to single spacebar character
# used in particular for most fields of citation data from outside sources
sub clean_whitespace {
  my $value = shift;
  $value = shift if defined $value and ref $value;
  return undef unless defined $value;
  $value =~ s/^\s+//;
  $value =~ s/\s+$//;
  $value =~ s/\s+/ /sg;
  return $value;
}

# custom encode wide characters to avoid problems with older modules that are not unicode-aware
sub text_encode_wide_characters {
  my $str = shift;
  $str =~ s/([^[:ascii:]])/'-[c'.ord($1).'c]-'/ge;
  return $str;
}

sub text_decode_wide_characters {
  my $str = shift;
  $str =~ s/-\[c(\d+)c\]-/chr($1)/ge;
  return $str;
}

sub text_decode_wide_characters_to_xml_entities {
  my $str = shift;
  $str =~ s/-\[c(\d+)c\]-/sprintf('&#x%X;',$1)/ge;
  return $str;
}

sub text_encode_newlines {
  my $str = shift;
  $str =~ s/\n/-{\\n}-/g;
  return $str;
}

sub text_decode_newlines {
  my $str = shift;
  $str =~ s/-{\\n}-/\n/g;
  return $str;
}

sub ua {
  Bibliotech::UserAgent->new(bibliotech => shift);
}

# request a network document using our special ua object and return the whole response object
sub ua_get_response {
  my ($uri_or_request, $ua_or_bibliotech, $cached_copy) = @_;
  die 'must provide URI or HTTP::Request object' unless defined $uri_or_request;
  # $ua_or_bibliotech can be undef

  return ${$cached_copy} if defined $cached_copy and defined ${$cached_copy};

  my $req;
  if (UNIVERSAL::isa($uri_or_request, 'HTTP::Request')) {
    # assume they have packed a request for us already (maybe a POST)
    $req = $uri_or_request;
  }
  else {
    # assume it's a URI - either just a scalar or a URI object
    # in either case deal with a blank one the same way, since that will be a common error
    my $uri_str = "$uri_or_request" or die 'cannot GET a blank URI';
    if (UNIVERSAL::isa($uri_or_request, 'URI')) {
      $req = HTTP::Request->new(GET => $uri_or_request);
    }
    else {
      $req = HTTP::Request->new(GET => $uri_str);
    }
  }

  my $ua;
  if (UNIVERSAL::isa($ua_or_bibliotech, 'LWP::UserAgent')) {
    # they have given us an LWP object, perhaps obtained previously from ua()
    $ua = $ua_or_bibliotech;
  }
  else {
    # create a new one
    $ua = ua($ua_or_bibliotech);  # undef ok
  }

  my $response = $ua->request($req);
  ${$cached_copy} = $response if defined $cached_copy;
  return $response;
}

# accept a response object and decode the content portion to a Perl string respecting the encoding
sub ua_decode_content {
  my $response = shift;
  my $content  = $response->content;

  return $content if is_utf8($content);

  my @types = ($response->header('Content-Type'));

  # pick up a couple extra non-header variants:
  my ($first_5_lines) = $content =~ /^((?:.*\n){0,5})/;
  # you wouldn't think it was necessary to limit to the top lines but cnn.com as one prominent
  # example has embedded XML in their home page
  if ($first_5_lines and $first_5_lines =~ /<?xml[^>]+encoding=\"([^\"]+)\"/) {
    push @types, 'application/xml;charset='.$1;
  }
  else {
    my ($head) = $content =~ m|^.*?(<head.*</head>)|si;
    # same issue here - limit to <head> where it is supposed to be!
    if ($head and $head =~ /<meta\s+http-equiv=\"Content-Type\"\s+content=\"([^\"]+)\"/is) {
      push @types, $1;
    }
  }

  # break apart type and charset:
  my ($type, $charset);
  foreach (@types) {
    if (m|^(\w+/[\w+]+)(?:\s*;\s*(?:charset=)?([\w\-]+))|i) {
      $type = $1;
      if ($2) {
	$charset = $2;
	$charset =~ s/^UTF-8$/utf8/;
      }
    }
  }

  # offer default for charset based on type if necessary:
  unless ($charset) {
    if ($type && $type =~ /(?:xml|xhtml|rss|rdf)/) {
      $charset = 'utf8';
    }
    else {
      $charset = 'iso-8859-1';
    }
  }

  my $decoded = eval { decode($charset, $content) || $content };
  if ($@) {
    return $content if $@ =~ /unknown encoding/i;  # that's usually not our fault
    die $@;
  }
  return $decoded;
}

# request a network document using our special ua object and return just the content or response plus content
sub ua_get_content_decoded {
  my $response = ua_get_response(@_);
  my $content  = $response->is_success ? $response->content : undef;  # decoded in Bibliotech::UserAgent
  return wantarray ? ($response, $content) : $content;
}

# extract an HTML <title> from content and return it
sub ua_extract_title {
  my $content = shift;

  return undef unless defined $content;

  # extract an HTML title tag, remove tags and clean whitespace
  # the 4k limit is hacky and arbitrary but it avoids repeated title tags in strange documents
  # far more than it misses legitimate titles which are almost always near the top above all else

  my ($title) = substr($content, 0, 4096) =~ m|<title>(.*?)</title>|si;
  return ua_clean_title($title);
}

# clean an extracted HTML <title> by:
# - removing inner tags (just the tags not their contents)
# - removing superfluous whitespace
# - decoding HTML entities (e.g. '&amp;' to '&')
sub ua_clean_title {
  my $title = shift;

  return undef unless defined $title;
  return ''    unless length  $title;

  my $safe = new HTML::Sanitizer('*' => 0);  # strip tags but keep inside text
  return undo_force_to_utf8
          (decode_entities
	   (force_to_utf8
	    (clean_whitespace
	     (text_decode_wide_characters
	      ($safe->filter_html_fragment
	       (text_encode_wide_characters($title)))))));
}

sub force_to_utf8 {
  "\x{2764}".shift;
}

sub undo_force_to_utf8 {
  local $_ = shift;
  s/^\x{2764}//;
  return $_;
}

# clean a block of formatted text
# - decoding HTML entities (e.g. '&amp;' to '&')
# - we do not do HTML tags because it messes with spacing which is important in RIS etc
sub clean_block {
  my $block = shift;

  return undef unless defined $block;
  return ''    unless length  $block;

  return decode_entities($block);
}

sub is_html_mime_type {
  my $mime_type = shift or return 0;
  return 1 if grep { $mime_type eq $_ } ('text/html',
					 'text/xhtml',
					 'text/shtml',
					 'application/xhtml+xml');
  return 0;
}

sub is_html_content_type {
  my $content_type = shift;
  my ($mime_type) = $content_type =~ m|^(\w+/[\w+]+)|;
  return is_html_mime_type($mime_type);
}

# request an HTML network document using our special ua object and return the response, content, and title
sub ua_get_response_and_content_and_title_decoded {
  my ($response, $content) = ua_get_content_decoded(@_);
  return ($response,
	  $content,
	  (is_html_content_type(scalar $response->header('Content-Type'))
	      ? ua_extract_title($content)
	      : ())
	  );
}

# general purpose network URL retrieval utility
# pass in an URL scalar or a URI object or HTTP::Reqest object,
# optionally followed by a LWP::UserAgent or Bibliotech object
# returns content in scalar context
# returns request object, content, html title in list context
# e.g.: my $doc = get('http://connotea.org/');
sub ua_act {
  return wantarray ? ua_get_response_and_content_and_title_decoded(@_)
                   : ua_get_content_decoded(@_);
}

sub get {
  ua_act(@_);
}

# clean up comment text that will be posted on the site
# allows a strict shortlist of tags
sub sanitize {
  my $text = shift;
  return undef if !defined($text);
  return '' if !$text;

  my $html = $text;
  my @html = qw/b i p li ol ul em br tt strong blockquote div dl dt dd cite abbr/;  # took out 'a' for hyperlinks
  my $safe = HTML::Sanitizer->new((map { $_ => 1; } @html),
				  _              => {
				      href       => sub { $_ = 'denymenowhref' unless m/^(http|ftp|mailto):/i; 1; },
				      title      => 1,
				      'xml:lang' => 1,
				      lang       => 1,
				      '*'        => sub { $_ = 'denymenowattr'; 1; }
				  },
				  '*'            => HTML::Element->new('denymenowtag'));
  $html =~ s|\r?\n|<br />|g;  # convert newlines to break tags to keep their positions
  $html = text_encode_wide_characters($html);
  my $clean_html = $safe->filter_xml_fragment($html);
  if ($clean_html =~ /denymenow/) {
    die "Sorry, you may only use these HTML tags: ".join(', ', map($_, @html))."\n"
	if $clean_html =~ /denymenowtag/;
    die "Sorry, hyperlinks in comments may only be absolute links for http:, ftp:, or mailto: schemes.\n"
	if $clean_html =~ /denymenowhref/;
    die "Sorry, one of your HTML tag attributes is not allowed.\n"
	if $clean_html =~ /denymenowattr/;
    die "Some part of your text was denied for bad HTML content.\n";  # should actually never get hit
  }
  $clean_html =~ s!(<\w+ />|</\w+>)\n!$1!g;  # remove extra linefeed inserted by HTML::Sanitizer
  $clean_html = text_decode_wide_characters_to_xml_entities($clean_html);
  return $clean_html;
}

sub without_hyperlinks {
  my $text = shift;
  return undef if !defined($text);
  return '' if !$text;
  my $safe = HTML::Sanitizer->new;
  $safe->deny('a');
  return $safe->filter_html_fragment($text);
}

sub without_hyperlinks_or_trailing_spaces {
  local $_ = without_hyperlinks(shift);
  s/\s+\z//;
  return $_;
}

sub without_spaces {
  local $_ = shift;
  s/\s//g;
  return $_;
}

# pass in 'and' or 'or' followed by a list of strings
# you output will be a natural English list with commas
# e.g.:  "1"  "1 and 2"  "1, 2, and 3"
sub speech_join {
  my ($jointype, @str) = @_;
  @str = @{$str[0]} if @str == 1 && ref $str[0] eq 'ARRAY';
  return $str[0] if @str == 1;
  return join(" $jointype ", @str) if @str == 2;
  return join(', ', @str[0..$#str-1], join(' ', $jointype, $str[-1]));
  #return join(', ', @str[0..$#str-2], join(' ', $jointype, $str[-2], $str[-1]));
}

sub _encode_check_param {
  local $_ = shift;
  return undef unless defined $_;
  return $_ unless ref $_;
  return "$_" if $_->isa('URI');
  return undef;
}

# encode text to be output as XML with a UTF-8 charset
sub encode_xml_utf8 {
  my $str = shift;
  local $_ = _encode_check_param($str) or return $str;
  s/[[:cntrl:]](?<![\r\n\t ])//g;  # destroy control chars
  s/&(?!(#[0-9]+|#x[0-9a-fA-F]+|\w+);)/&amp;/g;
  s/</&lt;/g;
  s/>/&gt;/g;
  s/(&(\w+);?)/my $c = $HTML::Entities::entity2char{$2}; $c ? sprintf('&#x%X;', ord($c)) : "&amp;$2;"/eg;
  return $_;
}

# encode text to be output as XHTML with a UTF-8 charset
sub encode_xhtml_utf8 {
  my $str = shift;
  local $_ = _encode_check_param($str) or return $str;
  s/[[:cntrl:]](?<![\r\n\t ])//g;  # destroy control chars
  $_ = HTML::Entities::encode_entities($_);
  return $_;
}

sub encode_markup_xhtml_utf8 {
  my $str = shift;
  local $_ = _encode_check_param($str) or return $str;
  s/[[:cntrl:]](?<![\r\n\t ])//g;  # destroy control chars
  s/([^[:ascii:]])/sprintf('&#x%X;', ord($1))/ge;  # alternative to encode_entities() because it contains HTML
  return $_;
}

# return the database timestamp if connected, otherwise if in unconnected API mode return clock time
# returns an object
sub now {
  return Bibliotech::Date->mysql_now if $INC{'Bibliotech/DBI.pm'};
  return DateTime->now;
}

# return the database timestamp if connected, otherwise if in unconnected API mode return clock time
# returns a 32-bit Unix timestamp integer
sub time {
  return Bibliotech::Date->mysql_now->epoch if $INC{'Bibliotech/DBI.pm'};
  return time;
}

sub _sendmail_open {
  our $SENDMAIL_OPEN;
  return $SENDMAIL_OPEN if defined $SENDMAIL_OPEN;
  my $sendmail = ($INC{'Bibliotech/Config.pm'} ? Bibliotech::Config->get('SENDMAIL') : undef) || '/usr/lib/sendmail';
  return $SENDMAIL_OPEN = "|$sendmail -t";
}

# send an email
# options:
#   body: text of email
#   filter: a subroutine to filter the body
#   file: read text from file instead
#   outfh: output to file handle
#   outfile: output to file
#   prog: output to program, defaults to sendmail
#   to: who the email is to, defaults to user's email address
#   from: who the email is from, defaults to standard site email address
#   reply-to: who to reply to
#   envelope_sender: who to list as the return path, defaults to from
#   subject: the email subject line
sub notify {
  my ($options_ref) = @_;
  my %options = %{$options_ref||{}};

  # define body of email
  my @body;
  if ($options{body}) {
    # if body given use it
    @body = ref $options{body} ? [split(/\n/, $options{body})] : $options{body};
  }
  elsif (my $filename = $options{file}) {
    # if filename given load it
    my $fh = new IO::File ($filename) or die "cannot open $filename: $!";
    @body = <$fh>;
    $fh->close;
  }

  # if filter given, pass body through it
  if (my $filter = $options{filter}) {
    @body = @{$filter->(\@body, $options{var} || {})};
  }

  # calculate email headers, either by option or from body
  my %headers;
  $headers{$_} = $options{lc $_} foreach (qw/To From Reply-To Subject/);
  if ($body[0] =~ /^[\w\-]+:\s/) {  # don't bother unless first line looks promising
    local $_;
    while ($_ = shift @body) {      # go through initial lines...
      last if /^$/;                 # (end at blank line)
      /([\w\-]+):\s(.*)$/;          # findng headers...
      $headers{$1} = $2;            # and populating hash
    }
  }
  # fallbacks
  $headers{To} ||= $options{default_to};
  $headers{From} ||= $options{default_from};

  # last minute check
  die 'no destination address' unless $headers{To};
  die 'no source address' unless $headers{From};

  # setup an output filehandle
  my $fh;
  if (defined $options{outfh}) {
    $fh = $options{outfh};
  }
  elsif ($options{outfile}) {
    (my $target = $options{outfile}) =~ s/^([^>])/>$1/;
    $fh = IO::File->new($target) or die "cannot open $target: $!";
  }
  else {
    my $prog = $options{prog} || _sendmail_open();
    my $sender_raw = $options{envelope_sender} || $headers{From};
    $sender_raw =~ /^([\w\.]+\@[\w\.]+)$/;  # security
    my $sender = $1;
    $prog .= ' -r '.$sender if $sender;
    (my $target = $prog) =~ s/^([^|])/|$1/;
    open $fh, $target or die "cannot open $target: $!";
  }

  # expand some headers that might be passed in as arrayrefs
  foreach (qw/To Cc Bcc/) {
    if (exists $headers{$_} and ref $headers{$_} eq 'ARRAY') {
      $headers{$_} = join(', ', @{$headers{$_}});
    }
  }

  # build the ordinal list of headers now
  # start with most important headers, then rest of headers
  my @headers;
  foreach (qw/To From Reply-To Subject/) {
    my $value = $headers{$_} or next;
    $value = join(', ', @{$value}) if ref $value;
    push @headers, [$_ => $value];
    delete $headers{$_};
  }
  if (%headers) {
    foreach (sort keys %headers) {
      push @headers, [$_ => $headers{$_}];
    }
  }
  # convert to line format
  @headers = map { $_->[0].': '.$_->[1]."\n" } @headers;

  # you can insert other commands here to act upon @_:
  my $print = sub { print $fh @_;
		    #warn @_;
		  };

  # emit a formatted data stream to sendmail (or whatever)
  $print->(@headers,
	   "\n",
	   @body,
	   "\n",
	   ".\n");

  # close up shop
  close $fh unless defined $options{outfh};  # don't close a passed-in filehandle

  return 1;
}

# call as plural($seconds, 'second', 'seconds') to get "6 seconds" but "1 second"
sub plural {
  shift if ref $_[0] or $_[0] eq __PACKAGE__;
  my ($amount, $singular, $plural, $no_space) = @_;
  $amount = 0 unless defined $amount;
  (my $numeric = $amount) =~ s/\D//g;
  my $noun = ($numeric == 1 ? $singular : (defined $plural ? $plural : $singular.'s'));
  return join($no_space ? '' : ' ', $amount, $noun);
}

# convert 12345678 -> 12,345,678
# also $12345678 USD -> $12,345,678 USD
sub commas {
  my $str   = shift;
  my $comma = shift || ',';
  my ($leading, $trailing);
  local $_;
  ($leading, $_, $trailing) = ($str =~ /^(\D*)(\d+)(.*)$/);
  1 while s/(.*)(\d)(\d\d\d)/$1$2$comma$3/;
  return join('', $leading, $_, $trailing);
}

sub decode_entities {
  shift if ref $_[0] or $_[0] eq __PACKAGE__;
  local $_ = shift;
  # because the one supplied by HTML::Entities 1.35 doesn't do *all* the characters (<255?)
  #s/(&\#(\d+);)/chr($2) || $1/eg;
  #s/(&\#[xX]([0-9a-fA-F]+);)/my $c = hex($2); chr($c) || $1/eg;
  return HTML::Entities::decode_entities($_);
}

sub hrtime {
  my $action = pop;
  my $start  = gethrtime;
  my $result = $action->();
  my $end    = gethrtime;
  return ($result, sprintf('%0.4f', ($end - $start) / 1000000000));
}

# '1 to 2' => (1,2)
# '1-2'    => (1,2)
# '12-3'   => (12,13)
sub split_page_range {
  my $pages = shift or return ();
  my ($start, $end) = $pages =~ /(\d+)\D+(\d+)/;
  if (!defined $start) {
    ($start) = $pages =~ /(\d+)/;
    $end = $start;
  }
  elsif ($end < $start) {  # e.g. '27-8' yields (27, 8) and must be corrected to (27, 28)
    $end = substr($start, 0, -length($end)) . $end;
  }
  return ($start, $end);
}

sub parse_author {
  Bibliotech::Unwritten::Author->from_name_str(pop);
}

sub split_names {
  local $_ = shift;
  s/(\w\.)(\w{3,})/$1 $2/g;  # correct 'B.Lund' to 'B. Lund'
  s/(\w{3,})(?:, |,| )(\w\.( ?\w\.)*)(,|$)/$2 $1;/g;  # correct 'Lund, B.,' to 'B. Lund;'
  s/ *;$//;
  s/; +and +/; /g;
  return ("$2 $1") if /^(\w+), (\w+)$/;
  return split(/ *; */) if /;/;
  return split(/ +and +/) if /, +\w+ +and +\w+,/ or !/,/;
  return split(/(?:(?: |,) *and +|, *)/);
}

sub remove_et_al {
  local $_ = shift;
  s/,? +[Ee]t\.? [Aa]l\.?$//;
  return $_;
}

sub split_author_names {
  map { parse_author($_) } split_names(remove_et_al(pop));
}

sub divide {
  my ($a, $b, $places, $multiplier) = @_;
  my $result = eval { return 0 unless $a and $a =~ /^[\d\.]+$/;
		      return 0 unless $b and $b =~ /^[\d\.]+$/;
		      return 0 if $b == 0;
		      return $a / $b; };
  return sprintf('%0.'.(defined $places ? $places : 1).'f', $result * ($multiplier || 1));
}

sub percent {
  my ($a, $b, $places) = @_;
  divide($a, $b, $places, 100).'%';
}

1;
__END__
