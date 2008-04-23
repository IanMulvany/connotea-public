package Bibliotech::Unwritten::Author;
use strict;
use base ('Bibliotech::Unwritten', 'Bibliotech::Author');

our $PARSER;

sub parser {
  $PARSER = Bibliotech::Lingua::EN::NameParse->new unless defined $PARSER;
  return $PARSER;
}

sub from_name_str {
  my ($class, $name) = @_;
  my $p = parser();
  $p->parse($name) or return $class->new({misc => $name});
  my %name = $p->case_components;
  return $class->new
      ({firstname  => undef,
	forename   =>          $name{given_name_1}
	              || join(' ', map { s/\.//g; $_; } grep { $_ }
			      (substr($name{initials_1}, 0, 1),
			       $name{initials_2}))
                      || undef,
	initials   => join('', map { s/\.//g; split(/\s+/) } grep { $_ }
			      (substr($name{given_name_1}, 0, 1),
			       $name{initials_1},
			       $name{initials_2},
			       substr($name{middle_name}, 0, 1)))
	              || undef,
	middlename =>          $name{middle_name}
	              || undef,
	lastname   => join(' ', grep { $_ }
			      ($name{surname_1},
			       $name{surname_2}))
	              || undef,
	suffix     =>          $name{suffix}
	              || undef,
      });
}

# some citationsource modules use Bibliotech::Util::parse_author() and
# Bibliotech::CitationSource::Simple and this bridges the gap for
# individual author names to be backed out of an object to a hash
sub as_hash {
  my $self = shift;
  return {firstname  => $self->firstname  || undef,
	  forename   => $self->forename   || undef,
	  initials   => $self->initials   || undef,
	  middlename => $self->middlename || undef,
	  lastname   => $self->lastname   || undef,
	  suffix     => $self->suffix     || undef};
}

sub json_content {
  shift->as_hash;
}

package Bibliotech::Lingua::EN::NameParse;
use Lingua::EN::NameParse;
use base 'Lingua::EN::NameParse';
use Parse::RecDescent;

sub new {
  my ($class, %options) = @_;
  my $self = Lingua::EN::NameParse->new(auto_clean     => 0,
					force_case     => 0,
					lc_prefix      => 1,
					allow_reversed => 0, # we do it in special_fixes
					initials       => 4,
					%options);
  bless $self, ref $class || $class;
  $self->{parse}->Replace('initials: /([A-Z]\. ){1,4}/i | /([A-Z]\.){1,4} /i | /([A-Z] ){1,4}/ | /([A-Z]){1,4} /');
  $self->{parse}->Replace('single_initial: initials');
  $self->{parse}->Replace('given_name: /[A-Z]{2,} /i | /[A-Z]{2,}\-[A-Z]{2,} /i | /[A-Z]{1,}\'[A-Z]{2,} /i');
  $self->{parse}->Replace('name: /[A-Z\']{2,} ?/i');
  return $self;
}

sub parse {
  my ($self, $name) = @_;

  $self->SUPER::parse(special_fixes(make_name_all_ascii(clean_name_str($name))));

  # return value is backwards from Lingua::EN::NameParse, and checks
  # properties because rc from parse() is sometimes 1 when it worked!
  my %properties = $self->properties;
  return $properties{type} eq 'unknown' ? 0 : 1;
}

sub special_fixes {
  local $_ = shift or return;

  s/^(.*?), *(.*)$/$2 $1/;  # reverse

  my $precursor = precursor_qr();
  my $title     = title_qr();
  my $initials  = qr/([A-Z]{2,4})/;
  my $mixed     = qr/([A-Za-z][a-z\'][A-Za-z\']*)/;
  my $suffix    = suffix_qr();

  my ($used_precursor) = s/^($precursor)//;
  my ($used_title)     = s/^($title)//;

  # ED Smith -> E. D. Smith
  s/^$initials $mixed/join(' ', map($_.'.', split('', $1)), $2)/e or

  # P.J de Vries -> P. J. de Vries
  s/^([A-Z]\.)([A-Z]) /$1 $2. / or

  # John ED Smith -> John E. D. Smith
  s/^$mixed $initials $mixed$/join(' ', $1, map($_.'.', split('', $2)), $3)/e or

  # Parise O Jr -> O Parise Jr
  s/^$mixed ([A-Z]|$initials) ($suffix)$/$2 $1 $4/;

  return join('', grep {$_ } $used_precursor, $used_title, $_);
}

sub case_components {
  my $self = shift;
  my %c = $self->SUPER::case_components(@_);
  $c{$_} = restore_name_non_ascii($c{$_}) foreach (grep { defined $c{$_} } keys %c);
  if ($c{surname_1}) {
    $c{surname_1} =~ s/Th\'(.)/Th\'\L$1/;  # Th'ng - don't capitalize second part
    $c{surname_1} =~ s/\b(Mc)([a-z]+)/$1\u$2/ig;  # this was left out of current version (bug)
  }
  return %c;
}

sub precursor_qr {
  qr/Estate Of (The Late )?|His (Excellency|Honou?r) |Her (Excellency|Honou?r) |The Right Honou?rable |The Honou?rable |Right Honou?rable |The Rt\.? Hon\.? |The Hon\.? |Rt\.? Hon\.? /i;
}

sub title_qr {
  qr/Mr\.? |Ms\.? |M\/s\.? |Mrs\.? |Miss\.? |Dr\.? |Sir |Dame |Messrs |Mme\.? |Mister |Mast(\.|er)? |Ms?gr\.? |Lord |Lady |Madam(e)? |Doctor |Sister |Matron |Judge |Justice |Det\.? |Insp\.? |Brig(adier)? |Captain |Capt\.? |Colonel |Col\.? |Commander |Commodore |Cdr\.? |Field Marshall |Fl\.? Off\.? |Flight Officer |Flt Lt |Flight Lieutenant |Gen(\.|eral)? |Gen\. |Pte\. |Private |Sgt\.? |Sargent |Air Commander |Air Commodore |Air Marshall |Lieutenant Colonel |Lt\.? Col\.? |Lt\.? Gen\.? |Lt\.? Cdr\.? |Lieutenant |(Lt|Leut|Lieut)\.? |Major General |Maj\.? Gen\.?|Major |Maj\.? |Rabbi |Bishop |Brother |Chaplain |Father |Pastor |Mother Superior |Mother |Most Rever[e|a]nd |Very Rever[e|a]nd |Rever[e|a]nd |Mt\.? Revd\.? |V\.? Revd?\.? |Revd?\.? |Prof(\.|essor)? |Ald(\.|erman)? /i;
}

sub suffix_qr {
  qr/Esq(\.|uire)?\b ?|Sn?r\.?\b ?|Jn?r\.?\b ?|PhD\.?\b ?|MD\.?\b ?|LLB\.?\b ?|XI{1,3}\b ?|X\b ?|IV\b ?|VI{1,3}\b ?|V\b ?|IX\b ?|I{1,3}\b ?/i;
}

# Lingua::EN::NameParse being based on Parse::RecDescent cannot handle
# UTF-8 characters. We will sometimes provide names that have such
# characters, so we need an escaping mechanism. It also cannot handle
# digits and it will change the case of characters, so the escaping
# string must be all lowercase letters and be recognized if uppercase.
# Thus the strategy is as follows:
# e.g. "\x{017C}" -> 'xescapediax'
#                     ^^^^^^^   ^  these delimit and mark it
#                            ^^^   these are the ord() value encoded
# ord("\x{017C}") -> '380' and we encode 0-9 as a-j.
# Because this ends up as eleven simple letters it can be in the
# middle of a name and be worked upon by the name functions without
# any issues until it is time to unescape back to a wide
# character. Escaping is done in parse() and unescpaing is done in
# case_components(). The next four functions provide this scheme.

sub num2letter {
  local $_ = shift;
  tr/0123456789/abcdefghij/;
  return $_;
}

sub letter2num {
  local $_ = shift;
  tr/abcdefghij/0123456789/;
  return $_;
}

sub make_name_all_ascii {
  local $_ = shift;
  s/([^[:ascii:]])/'xescape'.num2letter(ord($1)).'x'/ge;
  return $_;
}

sub restore_name_non_ascii {
  local $_ = shift;
  s/xescape([a-j]+)x/chr(letter2num($1))/gie;
  return $_;
}

sub clean_name_str {
  local $_ = shift;
  s/\d//g;
  return $_;
}

1;
__END__
