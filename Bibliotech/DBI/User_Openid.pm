package Bibliotech::User_Openid;
use strict;
use base 'Bibliotech::DBI';
use URI;

__PACKAGE__->table('user_openid');
__PACKAGE__->columns(Primary => qw/user/);
__PACKAGE__->columns(Essential => qw/openid created/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_a(openid => 'URI');

sub my_alias {
  'uo';
}

1;
__END__
