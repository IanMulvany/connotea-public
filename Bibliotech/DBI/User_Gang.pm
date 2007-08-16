package Bibliotech::User_Gang;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('user_gang');
#__PACKAGE__->columns(All => qw/user_gang_id user gang created updated/);
__PACKAGE__->columns(Primary => qw/user_gang_id/);
__PACKAGE__->columns(Essential => qw/user gang/);
__PACKAGE__->columns(Others => qw/created updated/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->has_a(user => 'Bibliotech::User');
__PACKAGE__->has_a(gang => 'Bibliotech::Gang');

sub my_alias {
  'ug';
}

1;
__END__
