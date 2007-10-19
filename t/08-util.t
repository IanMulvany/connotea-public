#!/usr/bin/perl

use Test::More tests => 120;
use Test::Exception;
use strict;
use warnings;
use Encode qw/is_utf8/;
use Data::Dumper;

BEGIN {
  use_ok('Bibliotech::Util', ('clean_whitespace',
			      'text_encode_wide_characters',
			      'text_decode_wide_characters',
			      'text_decode_wide_characters_to_xml_entities',
			      'text_encode_newlines',
			      'text_decode_newlines',
			      'ua_clean_title',
			      'force_to_utf8',
			      'undo_force_to_utf8',
			      'clean_block',
			      'is_html_mime_type',
			      'speech_join',
			      'encode_xml_utf8',
			      'encode_xhtml_utf8',
			      'encode_markup_xhtml_utf8',
			      'now',
			      'plural',
			      'decode_entities',
			      'hrtime',
			      'split_page_range',
			      'split_names',
			      'remove_et_al',
			      'parse_author',
			      'split_author_names')) or exit;
  use_ok('Bibliotech::DBI');
};

is(clean_whitespace(' front'), 'front', 'clean_whitespace front');
is(clean_whitespace('back '), 'back', 'clean_whitespace back');
is(clean_whitespace(' front back '), 'front back', 'clean_whitespace front/back');
is(clean_whitespace(' front  middle  back '), 'front middle back', 'clean_whitespace front/middle/back');

my $jnews = "\x{30cb}\x{30e5}\x{30fc}\x{30b9}";  # "news" in japanese from google.jp
my $o = $jnews;
ok($o =~ /[\x{FF}-\x{FFFF}]/, 'original text contains wide characters');
my $e = text_encode_wide_characters($o);
ok($e !~ /[\x{FF}-\x{FFFF}]/, 'encoded text contains no wide characters');
my $d = text_decode_wide_characters($e);
ok($d =~ /[\x{FF}-\x{FFFF}]/, 'decoded text contains wide characters');
is($d, $o, 'decoded text equals original text');

is(text_decode_wide_characters_to_xml_entities($e), '&#x30CB;&#x30E5;&#x30FC;&#x30B9;', 'wide characters to xml');

$o = "a\nb\nc\n";
ok($o =~ /\n/, 'original text contains newlines');
$e = text_encode_newlines($o);
ok($e !~ /\n/, 'encoded text contains no newlines');
$d = text_decode_newlines($e);
ok($d =~ /\n/, 'decoded text contains newlines');
is($d, $o, 'decoded text equals original text');

is(ua_clean_title('My <b>Big</b> Web Site'), 'My Big Web Site', 'ua_clean_title remove tags');
is(ua_clean_title('  My <b> Big</b> Web Site'), 'My Big Web Site', 'ua_clean_title clean whitespace');
is(ua_clean_title('  My <b> Big &amp; Awesome</b> Web Site'), 'My Big & Awesome Web Site', 'ua_clean_title entities');
is(ua_clean_title("My <b>$jnews</b> Page"), "My $jnews Page", 'ua_clean_title remove tags with wide characters');

$o = 'abc';
ok(!is_utf8($o), 'original text not utf8');
$e = force_to_utf8('abc');
ok(is_utf8($e), 'forced text is utf8');
$d = undo_force_to_utf8($e);
is($d, $o, 'undo force equals original text');

is(clean_block('me &amp; you'), 'me & you', 'clean_block');

ok(is_html_mime_type('text/html'), 'html mime type: text/html');
ok(is_html_mime_type('text/xhtml'), 'html mime type: text/xhtml');
ok(is_html_mime_type('text/shtml'), 'html mime type: text/shtml');
ok(is_html_mime_type('application/xhtml+xml'), 'html mime type: application/xhtml+xml');
ok(!is_html_mime_type('text/plain'), 'not html mime type: text/plain');
ok(!is_html_mime_type('text/csv'), 'not html mime type: text/csv');

is(speech_join('and', 1),       '1',           'speech_join: 1');
is(speech_join('and', 1, 2),    '1 and 2',     'speech_join: 1 and 2');
is(speech_join('and', 1, 2, 3), '1, 2, and 3', 'speech_join: 1, 2, and 3');

is(encode_xml_utf8('2 > 1 < 2'), '2 &#x3E; 1 &#x3C; 2', 'encode_xml_utf8 escaping');
is(encode_xhtml_utf8('2 > 1 < 2'), '2 &gt; 1 &lt; 2', 'encode_xhtml_utf8 escaping');
is(encode_markup_xhtml_utf8("<b>$jnews</b>"), '<b>&#x30CB;&#x30E5;&#x30FC;&#x30B9;</b>', 'encode_markup_xhtml_utf8');

isa_ok(now(), 'DateTime', 'now');
ok(time() > 0, 'time');

is(plural(1, 'second', 'seconds'), '1 second', 'plural: 1 second');
is(plural(2, 'second', 'seconds'), '2 seconds', 'plural: 2 seconds');

is(decode_entities("&mdash;"), "\x{2014}", 'decode_entities');

my ($value, $time) = hrtime(sub { 100 });
is($value, 100, 'hrtime value');
ok($time >= 0.0 && $time < 0.1, 'hrtime time');

sub test_split_page_range {
  my ($raw, $expected) = @_;
  is_deeply([split_page_range($raw)], $expected, 'split_page_range: '.$raw);
}

test_split_page_range('1 to 2',  [1,2]);
test_split_page_range('1-2',     [1,2]);
test_split_page_range('1-11',    [1,11]);
test_split_page_range('1-13',    [1,13]);
test_split_page_range('1-130',   [1,130]);
test_split_page_range('12-3',    [12,13]);
test_split_page_range('13-130',  [13,130]);
test_split_page_range('102-3',   [102,103]);
test_split_page_range('102-13',  [102,113]);
test_split_page_range('102-30',  [102,130]);
test_split_page_range('120-30',  [120,130]);
test_split_page_range('120-130', [120,130]);

sub test_split_names {
  my ($raw, $expected) = @_;
  is_deeply([split_names($raw)], $expected, 'split_names: '.$raw);
}

test_split_names('Lund, Ben',
		 ['Ben Lund']);
test_split_names('Lund, Ben and Flack, Martin',
		 ['Lund, Ben', 'Flack, Martin']);
test_split_names('B Lund; M Flack',
		 ['B Lund', 'M Flack']);
test_split_names('Lund, B., Flack, M., and Hannay, T.',
		 ['B. Lund', 'M. Flack', 'T. Hannay']);
test_split_names('Lund B J and Scott J',
		 ['Lund B J', 'Scott J']);
test_split_names('Eric Verdin, Mark A Goldsmith, and Oliver T Keppler',
		 ['Eric Verdin', 'Mark A Goldsmith', 'Oliver T Keppler']);
test_split_names('Prerana Jayakumar, Irina Berger, Frank Autschbach, Mark Weinstein, '.
		 'Benjamin Funke, Eric Verdin, Mark A Goldsmith, and Oliver T Keppler',
		 ['Prerana Jayakumar', 'Irina Berger', 'Frank Autschbach', 'Mark Weinstein',
		  'Benjamin Funke', 'Eric Verdin', 'Mark A Goldsmith', 'Oliver T Keppler']);

is(remove_et_al('Martin Flack, et al.'), 'Martin Flack', 'remove_et_al: Martin Flack, et al.');

# is_deeply was thrown by the string override so we use is(Dumper())
my $johnsmith = Bibliotech::Unwritten::Author->new({firstname  => undef,
						    forename   => 'John',
						    initials   => 'J',
						    middlename => undef,
						    lastname   => 'Smith',
						    suffix     => undef,
						   });
my $jsmith    = Bibliotech::Unwritten::Author->new({firstname  => undef,
						    forename   => 'J',
						    initials   => 'J',
						    middlename => undef,
						    lastname   => 'Smith',
						    suffix     => undef,
						   });
my $johnsmithD = Dumper($johnsmith),
my $jsmithD    = Dumper($jsmith);

sub test_parse_author {
  my $expected = shift;
  foreach my $name (@_) {
    is(Dumper(parse_author($name)), $expected, 'parse_author: '.$name);
  }
}

test_parse_author($johnsmithD, ('Smith, John',
				'John Smith',
				'John SMITH',
				'SMITH, John'));
test_parse_author($jsmithD,    ('Smith, J.',
				'Smith, J',
				'J. Smith',
				'J Smith',
				'J SMITH',
				'SMITH, J.',
				'SMITH, J'));

sub test_parse_author_2 {
  my ($raw, $firstname, $forename, $initials, $middlename, $lastname, $suffix, $misc) = @_;
  lives_and {
    is(Dumper(parse_author($raw)),
       Dumper(Bibliotech::Unwritten::Author->new({$misc ? (misc => $misc)
						        : (firstname  => $firstname,
							   forename   => $forename,
							   initials   => $initials,
							   middlename => $middlename,
							   lastname   => $lastname,
							   suffix     => $suffix,
							   )})),
       );
  } 'parse_author: '.$raw;
}

test_parse_author_2('John Doppelgänger',   	  undef, 'John',   'J',    undef,    'Doppelgänger',  undef);
test_parse_author_2('Adrian O\'Dowd',      	  undef, 'Adrian', 'A',    undef,    'O\'Dowd',       undef);
test_parse_author_2('O\'Dowd, Adrian',            undef, 'Adrian', 'A',    undef,    'O\'Dowd',       undef);
test_parse_author_2('Monica Hoyos-Flight', 	  undef, 'Monica', 'M',    undef,    'Hoyos-Flight',  undef);
test_parse_author_2('Monica Kylie Hoyos-Flight',  undef, 'Monica', 'MK',   'Kylie',  'Hoyos-Flight',  undef);
test_parse_author_2('MKKK Flight',                undef, 'M',      'MKKK', undef,    'Flight',        undef);
test_parse_author_2('M K K K Flight',             undef, 'M',      'MKKK', undef,    'Flight',        undef);
test_parse_author_2('M. K. K. K. Flight',         undef, 'M',      'MKKK', undef,    'Flight',        undef);
test_parse_author_2('Hoyos-Flight, Monica',       undef, 'Monica', 'M',    undef,    'Hoyos-Flight',  undef);
test_parse_author_2('Hoyos-Flight, Monica C',     undef, 'Monica', 'MC',   undef,    'Hoyos-Flight',  undef);
test_parse_author_2('Hoyos-Flight, Monica C.',    undef, 'Monica', 'MC',   undef,    'Hoyos-Flight',  undef);
test_parse_author_2('B. Joseph Lund',             undef, 'B',      'BJ',   'Joseph', 'Lund',          undef);
test_parse_author_2('James Wu',                   undef, 'James',  'J',    undef,    'Wu',            undef);
test_parse_author_2('Wu, James',                  undef, 'James',  'J',    undef,    'Wu',            undef);
test_parse_author_2('James K Wu',                 undef, 'James',  'JK',   undef,    'Wu',            undef);
test_parse_author_2('James K. Wu',                undef, 'James',  'JK',   undef,    'Wu',            undef);
test_parse_author_2('James KW Wu',                undef, 'James',  'JKW',  undef,    'Wu',            undef);
test_parse_author_2('James K. W. Wu',             undef, 'James',  'JKW',  undef,    'Wu',            undef);
test_parse_author_2('Wu, James K',                undef, 'James',  'JK',   undef,    'Wu',            undef);
test_parse_author_2('Wu, James K. W.',            undef, 'James',  'JKW',  undef,    'Wu',            undef);
test_parse_author_2('Ye, S',                      undef, 'S',      'S',    undef,    'Ye',            undef);
test_parse_author_2('Ye, SR',                     undef, 'S',      'SR',   undef,    'Ye',            undef);
test_parse_author_2('SR Ye',                      undef, 'S',      'SR',   undef,    'Ye',            undef);
test_parse_author_2('Jo Griffiths',               undef, 'Jo',     'J',    undef,    'Griffiths',     undef);
test_parse_author_2('Th\'ng, JP',                 undef, 'J',      'JP',   undef,    'Th\'ng',        undef);
test_parse_author_2('Andrew van der Kojel',       undef, 'Andrew', 'A',    undef,    'van der Kojel', undef);
test_parse_author_2('Andrew James van der Kojel', undef, 'Andrew', 'AJ',   'James',  'van der Kojel', undef);
test_parse_author_2('van der Kojel, A',           undef, 'A',      'A',    undef,    'van der Kojel', undef);
test_parse_author_2('van der kojel, AJ',          undef, 'A',      'AJ',   undef,    'van der Kojel', undef);
test_parse_author_2('van der kojel, A J',         undef, 'A',      'AJ',   undef,    'van der Kojel', undef);
test_parse_author_2('A van der Kojel',            undef, 'A',      'A',    undef,    'van der Kojel', undef);
test_parse_author_2('A.J. van der Kojel',         undef, 'A',      'AJ',   undef,    'van der Kojel', undef);
test_parse_author_2('AJ van der Kojel',           undef, 'A',      'AJ',   undef,    'van der Kojel', undef);
test_parse_author_2('Peter de vries',             undef, 'Peter',  'P',    undef,    'de Vries',      undef);
test_parse_author_2('Peter K de vries',           undef, 'Peter',  'PK',   undef,    'de Vries',      undef);
test_parse_author_2('de vries, P',                undef, 'P',      'P',    undef,    'de Vries',      undef);
test_parse_author_2('de vries, PJ',               undef, 'P',      'PJ',   undef,    'de Vries',      undef);
test_parse_author_2('de vries, P.J.',             undef, 'P',      'PJ',   undef,    'de Vries',      undef);
test_parse_author_2('P.J de vries',               undef, 'P',      'PJ',   undef,    'de Vries',      undef);
test_parse_author_2('PJ de vries',                undef, 'P',      'PJ',   undef,    'de Vries',      undef);
test_parse_author_2('P de vries',                 undef, 'P',      'P',    undef,    'de Vries',      undef);
test_parse_author_2('McCampbell, AZ',             undef, 'A',      'AZ',   undef,    'McCampbell',    undef);
test_parse_author_2('Parise O Jr',                undef, 'O',      'O',    undef,    'Parise',        'Jr');
test_parse_author_2('O Parise Jr',                undef, 'O',      'O',    undef,    'Parise',        'Jr');
test_parse_author_2('O. Parise Jr',               undef, 'O',      'O',    undef,    'Parise',        'Jr');
test_parse_author_2('Oliver Parise Jr',           undef, 'Oliver', 'O',    undef,    'Parise',        'Jr');


# split_author_names() is a fairly trivial combination of split_names() and parse_author() so we just do one test
is(Dumper(split_author_names('Smith, John; Smith, J.')), Dumper($johnsmith, $jsmith), 'split_author_names');
