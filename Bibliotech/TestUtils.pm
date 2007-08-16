package Bibliotech::TestUtils;
use strict;
use warnings;
use base 'Exporter';
use Test::More;
use Test::Exception;
use Bibliotech::Config file => $ENV{CONFIG};
use Bibliotech;
use Bibliotech::Parser;
use Bibliotech::Config;

our @EXPORT = qw(get_test_bibliotech_object_1_test
                 is_table_count
		 is_table_empty
		 is_table_empty_or_bail
		 get_test_user_7_tests
		 get_test_bookmark_7_tests
                 simple_create_3_tests
		 );

sub get_test_bibliotech_object_1_test {
  my $parser     = Bibliotech::Parser->new;  # need for new_user username validation
  my $location   = URI->new(Bibliotech::Config->get('LOCATION'));  # need for new_user email text
  my $docroot    = Bibliotech::Config->get('DOCROOT');             # need for new_user email text
  my $bibliotech = Bibliotech->new({parser => $parser, location => $location, docroot => $docroot});
  ok($bibliotech, 'Bibliotech object creation.');
  return $bibliotech;
}

sub is_table_count {
  my ($class, $expected_count) = @_;
  is($class->count_all, $expected_count, join(' ', $class->table, 'has', $expected_count, 'rows'));
}

sub is_table_empty {
  is_table_count(shift, 0);
}

sub is_table_empty_or_bail {
  my $class = shift;
  is_table_empty($class)
      or BAIL_OUT($class->table.' not empty - please use TRUNCATE TABLE in mysql');
}

sub get_test_user_7_tests {
  my $bibliotech = shift or return;
  my $username   = shift || 'test_user';
  my $password   = shift || 'password';
  my $firstname  = shift || 'John';
  my $lastname   = shift || 'Smith';
  my $email      = shift || 'root@'.`hostname`;

  do {
    my $tmp = File::Temp->new;  # send new user welcome email here
    my $tmp_filename = $tmp->filename;
    lives_ok {
      $bibliotech->new_user($username, $password, $firstname, $lastname, $email, undef, undef, $tmp_filename);
    } 'new_user routine';
  };

  my $iter;
  lives_ok { $iter = Bibliotech::User->search(username => $username) } 'search for user';
  isa_ok($iter, 'Class::DBI::Iterator');
  is($iter->count, 1, '1 result found')
      or BAIL_OUT('test user not created - cannot continue');
  my $user_found;
  lives_ok { $user_found = $iter->next } 'get user found';
  isa_ok($user_found, 'Bibliotech::User');
  is($user_found->username, $username, 'username on object matches creation')
      or BAIL_OUT('test user not created - cannot continue');

  return $user_found;
}

sub get_test_bookmark_7_tests {
  my $bibliotech  = shift or return;
  my $testuri     = shift || 'http://www.slashdot.org/';
  my $booktitle   = shift || 'Slashdot';

  lives_ok {
    $bibliotech->preadd(uri => $testuri, title => $booktitle);
  } 'preadd routine';
  my $iter;
  lives_ok {
    $iter = Bibliotech::Bookmark->search(url => $testuri);
  } 'search for bookmark';
  isa_ok($iter, 'Class::DBI::Iterator');
  is($iter->count, 1, '1 result found')
      or BAIL_OUT('test bookmark not created - cannot continue');
  my $bookmark_found;
  lives_ok {
    $bookmark_found = $iter->next;
  } 'get bookmark found';
  isa_ok($bookmark_found, 'Bibliotech::Bookmark');
  is($bookmark_found->url, $testuri, 'url on object matches creation')
      or BAIL_OUT('test bookmark not created - cannot continue');

  return $bookmark_found;
}

sub simple_create_3_tests {
  my ($class, $params, $count) = @_;
  my $obj = $class->create($params);
  isa_ok($obj, $class);
  is_table_count($class, $count || 1);
  return $obj;
}

1;
__END__
