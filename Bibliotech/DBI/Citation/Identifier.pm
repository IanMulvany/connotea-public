package Bibliotech::Citation::Identifier;
use strict;
use base 'Class::Accessor::Fast';
use URI;
use URI::Escape;

__PACKAGE__->mk_accessors(qw/value/);

sub source   	{ undef }
sub type     	{ undef }
sub infotype 	{ undef }
sub noun     	{ undef }
sub xmlnoun 	{ undef }
sub prefix  	{ undef }
sub suffix  	{ undef }
sub urilabel    { undef }
sub uri         { undef }
sub natural_fmt { undef }

sub new {
  my $class = shift;
  my $value = shift or return;
  return $class->SUPER::new($value) if ref($value) eq 'HASH';
  $class->validate($value) or return;
  return $class->SUPER::new({value => $value});
}

sub as_string {
  my $self = shift;
  return join('', $self->prefix || '', $self->value || '', $self->suffix || '');
}

sub info_uri {
  my $self = shift;
  return URI->new(join('', 'info:', $self->infotype || $self->type, '/', $self->value));
}

sub info_or_link_uri {
  my $self = shift;
  return $self->info_uri if $self->value;
  return $self->uri;
}

sub info_or_link_text {
  my $self = shift;
  return $self->info_uri->as_string if $self->value;
  return $self->link_text;
}

sub format {
  my $self = shift;
  local $_ = shift;
  s/\%s/$self->source/eg;
  s/\%t/$self->type/eg;
  s/\%i/$self->infotype/eg;
  s/\%n/$self->noun/eg;
  s/\%</$self->prefix/eg;
  s/\%v/$self->value/eg;
  s/\%>/$self->suffix/eg;
  s/\%L/$self->urilabel/eg;
  s/\%U/$self->uri/eg;
  return $_;
}

sub natural_uri {
  my $self = shift;
  return $self->format($self->natural_fmt);
}

sub link_text {
  my $self = shift;
  return ($self->prefix || '').($self->value || '') || $self->noun || 'link';
}

sub _base_value_uri {
  my $base  = shift or die 'no base';
  my $value = shift or return;
  return URI->new($base.uri_escape($value, "^A-Za-z0-9\-_.!~*'()/"));  # escape exclusion is default plus '/'
}

sub uri {
  my $self = shift;
  return _base_value_uri($self->uri_base, $self->clean_value);
}

sub clean {
  pop;
}

sub clean_value {
  my $self = shift;
  return $self->clean($self->value);
}

package Bibliotech::Citation::Identifier::Pubmed;
use base 'Bibliotech::Citation::Identifier';

sub source   	{ 'Pubmed' }
sub type     	{ 'pubmed' }
sub infotype 	{ 'pmid' }
sub prefix   	{ 'PMID:' }
sub noun        { 'PubMedID' }
sub xmlnoun     { 'PubMedID' }
sub urilabel    { 'pmidResolver' }
sub natural_fmt { 'info:pmid/%v' }
sub uri_base    { 'http://www.ncbi.nlm.nih.gov/pubmed/' }

sub validate {
  local $_ = pop or return;
  return /^\d+$/;
}

sub clean {
  local $_ = pop or return;
  s/\D//g;
  return unless $_;
  return $_;
}

package Bibliotech::Citation::Identifier::DOI;
use base 'Bibliotech::Citation::Identifier';

sub source   	{ 'doi' }
sub type     	{ 'doi' }
sub infotype 	{ 'doi' }
sub prefix   	{ 'doi:' }
sub noun     	{ 'DOI' }
sub xmlnoun  	{ 'DOI' }
sub urilabel 	{ 'doiResolver' }
sub natural_fmt { 'info:doi/%v' }
sub uri_base    { 'http://dx.doi.org/' }

sub validate {
  local $_ = pop or return;
  return m|^10\..+/.+$|;
}

sub clean {
  local $_ = pop or return;
  m|^10\..+/.+$| or return;
  return $_;
}

package Bibliotech::Citation::Identifier::ASIN;
use base 'Bibliotech::Citation::Identifier';

sub source   	{ 'Amazon.com' }
sub type     	{ 'asin' }
sub infotype 	{ 'isbn' }
sub prefix   	{ 'ASIN: ' }
sub noun     	{ 'ASIN' }
sub xmlnoun  	{ 'ASIN' }
sub urilabel 	{ 'asinResolver' }
sub natural_fmt { 'urn:isbn:%v' }
sub uri_base    { 'http://www.amazon.com/exec/obidos/ASIN/' }

sub validate {
  local $_ = pop or return;
  return m/^[0-9A-Za-z \-]+$/;
}

sub clean {
  local $_ = pop or return;
  y|a-z|A-Z|;
  s|[^0-9A-Z]||;
  return unless $_;
  return $_;
}

package Bibliotech::Citation::Identifier::OpenURL;
use base 'Bibliotech::Citation::Identifier';
use URI;
use URI::OpenURL;

sub source   	{ 'OpenURL' }
sub type     	{ 'openurl' }
sub prefix   	{ shift->resolver_alias }
sub noun     	{ shift->resolver_alias }
sub xmlnoun  	{ 'OpenURL' }
sub urilabel 	{ 'openurlResolver' }
sub natural_fmt { '%U' }

sub _make_referrer {
  my ($location, $sitename) = @_;
  return unless defined $location;
  my $host = $location->host or return;
  $host =~ s|^www\.||;
  if (my $path = $location->path) {
    $path =~ s|/$||;
    $host .= $path;
  }
  $host .= ':'.$sitename if $sitename;
  return 'info:sid/'.$host;
}

sub _uri {
  my ($citation, $resolver_uri, $resolver_alias, $location, $sitename, $user_library_location) = @_;

  my $sid_uri_list_ref;
  if (my @id = $citation->standardized_identifiers(just_with_values => 1)) {
    $sid_uri_list_ref = [map($_->natural_uri, @id)];
  }

  my $openurl = URI::OpenURL->new($resolver_uri);
  $openurl->referrer (id => _make_referrer($location, $sitename)) if defined $location;
  $openurl->requester(id => $user_library_location) 		  if defined $user_library_location;
  $openurl->referent (id => $sid_uri_list_ref)      		  if defined $sid_uri_list_ref;

  my %citation;
  if (my $first_author = $citation->first_author) {
    if    (my $lastname  = $first_author->lastname)   { $citation{aulast}  = $lastname; }
    if    (my $firstname = $first_author->firstname)  { $citation{aufirst} = $firstname; }
    elsif (my $initials  = $first_author->initials)   { $citation{auinit}  = $initials; }
    elsif (my $forename  = $first_author->forename)   { $citation{auinit1} = substr($forename, 0, 1); }
  }
  if (my $journal = $citation->journal) {
    if (my $title = $journal->name || $journal->medline_ta) { $citation{jtitle} = $title; }
    if (my $issn = $journal->issn) { $citation{issn} = $issn; }
  }
  if (my $volume     = $citation->volume)     { $citation{volume} = $volume; }
  if (my $issue      = $citation->issue)      { $citation{issue}  = $issue; }
  if (my $date       = $citation->date)       { $citation{date}   = $date->ymd_ordered_cut; }
  if (my $start_page = $citation->start_page) { $citation{spage}  = $start_page; }
  if (my $end_page   = $citation->end_page)   { $citation{epage}  = $end_page; }

  my $ris_type = $citation->inferred_ris_type;
  my $typefunc = 'journal';
  if ($ris_type eq 'BOOK') {
    $typefunc = 'book';
    if (my $title = $citation->title) { $citation{title} = $title; }
    if (my $asin  = $citation->asin)  { $citation{isbn}  = $asin; }
  }
  elsif ($ris_type eq 'CONF') {
    $citation{genre} = 'conference';
  }
  elsif ($ris_type eq 'PAT') {
    $typefunc = 'patent';
  }
  else {
    $citation{genre} = 'article';
    if (my $title = $citation->title) { $citation{atitle} = $title; }
  }
  $openurl->$typefunc(%citation);

  my $hybrid = $openurl->as_hybrid || $openurl;
  return wantarray ? ($hybrid, $resolver_alias) : $hybrid;
}

__PACKAGE__->mk_accessors(qw/citation resolver_uri resolver_alias location sitename user_library_location/);

sub uri {
  my $self = shift;
  _uri($self->citation,
       $self->resolver_uri,
       $self->resolver_alias,
       $self->location,
       $self->sitename,
       $self->user_library_location);
}

sub new {
  my ($class, $citation, $bibliotech, $user) = @_;
  return unless defined $user and $user->openurl_resolver;
  return $class->SUPER::new
      ({citation       	      => $citation,
	resolver_uri   	      => $user->openurl_resolver,
	resolver_alias 	      => $user->openurl_name || 'OpenURL',
	location       	      => $bibliotech->location,
	sitename       	      => $bibliotech->sitename,
	user_library_location => (($bibliotech->can('library_location') && defined $user)
				      ? $bibliotech->library_location($user) : undef),
       });
}

1;
__END__
