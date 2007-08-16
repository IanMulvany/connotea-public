#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 16;
use Test::Exception;
use File::Temp;

BEGIN {
  use_ok('Bibliotech::Config', noinit => 1) or exit;
}

my $token = "test $$";

{
  my ($fh, $filename) = put_in_file(<<EOF);
GENERAL {
  SITE_NAME = \'$token\'
}
EOF
  lives_ok  { Bibliotech::Config->reload(file => $filename)    } 'load with just GENERAL->SITE_NAME';
  is $Bibliotech::Config::FILE => $filename,                     '$FILE is correct';
  lives_and { is(Bibliotech::Config->get('SITE_NAME'), $token) } 'GENERAL->SITE_NAME reads back token';
  lives_and { is(Bibliotech::Config->get('OTHER'),     undef)  } 'GENERAL->OTHER returns undef';
}

{
  my ($fh, $filename) = put_in_file(<<EOF);
GENERAL {
  MEMCACHED_SERVERS = [ \'127.0.0.1:11211\', \'192.168.1.1:11211\' ]
}
EOF
  lives_ok  { Bibliotech::Config->reload(file => $filename) }    'load with just GENERAL->MEMCACHED_SERVERS';
  lives_and { is_deeply(Bibliotech::Config->get('MEMCACHED_SERVERS'), [ '127.0.0.1:11211', '192.168.1.1:11211' ]) } 'GENERAL->MEMCACHED_SERVERS reads back addresses';
}

{
  my ($fh, $filename) = put_in_file(<<EOF);
GENERAL {
  SITENAME = \'Test\'
}

CITATION TEST1 {
  USER = \'$token\'
  PASSWORD = \'somepassword\'
}

CITATION TEST2 {
  USER = \'red herring\'
}

CITATION WOWZERS {
  USER = \'proper user\'
  PASSWORD = \'phew\'
}

COMPONENT TEST1 {
  USER = \'$token\'
  PASSWORD = \'somepassword\'
}

COMPONENT TEST2 {
  USER = \'red herring\'
}

COMPONENT WOWZERS {
  USER = \'proper user\'
  PASSWORD = \'phew\'
}
EOF
  my $cite1 = Bibliotech::CitationSource::Test1->new or die 'no cite1';
  my $cite2 = Bibliotech::CitationSource::Test2->new or die 'no cite2';
  my $comp1 = Bibliotech::Component::Test1->new or die 'no comp1';
  my $comp2 = Bibliotech::Component::Test2->new or die 'no comp2';
  lives_ok  { Bibliotech::Config->reload(file => $filename)    } 'load with CITATION and COMPONENT sections';
  lives_and { is $cite1->cfg('USER')      => $token            } 'CITATION TEST1->USER read';
  lives_and { is $cite1->cfg('PASSWORD')  => 'somepassword'    } 'CITATION TEST1->PASSWORD read';
  lives_and { is $cite2->cfg('USER')      => 'proper user'     } 'CITATION WOWZERS->USER read';
  lives_and { is $cite2->cfg('PASSWORD')  => 'phew'            } 'CITATION WOWZERS->PASSWORD read';
  lives_and { is $comp1->cfg('USER')      => $token            } 'COMPONENT TEST1->USER read';
  lives_and { is $comp1->cfg('PASSWORD')  => 'somepassword'    } 'COMPONENT TEST1->PASSWORD read';
  lives_and { is $comp2->cfg('USER')      => 'proper user'     } 'COMPONENT WOWZERS->USER read';
  lives_and { is $comp2->cfg('PASSWORD')  => 'phew'            } 'COMPONENT WOWZERS->PASSWORD read';
}

sub put_in_file {
  my $str = shift;
  my $fh = File::Temp->new or die 'cannot get a temporary file';
  my $filename = $fh->filename;
  print $fh $str, "\n";
  $fh->close;
  return ($fh, $filename);
}

package Bibliotech::CitationSource::Test1;
use base 'Bibliotech::CitationSource';

sub name {
  'Test1';
}

package Bibliotech::CitationSource::Test2;
use base 'Bibliotech::CitationSource';

sub name {
  'Test2';
}

sub cfgname {
  'wowzers';
}

package Bibliotech::Component::Test1;
use base 'Bibliotech::Component';

package Bibliotech::Component::Test2;
use base 'Bibliotech::Component';

sub cfgname {
  'wowzers';
}
