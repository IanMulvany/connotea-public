package Bibliotech::User_Bookmark_Tag;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('user_bookmark_tag');
#__PACKAGE__->columns(All => qw/user_bookmark_tag_id user_bookmark tag created/);
__PACKAGE__->columns(Primary => qw/user_bookmark_tag_id/);
__PACKAGE__->columns(Essential => qw/user_bookmark tag/);
__PACKAGE__->columns(Others => qw/created/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_a(user_bookmark => 'Bibliotech::User_Bookmark');
__PACKAGE__->has_a(tag => 'Bibliotech::Tag');

sub my_alias {
  'ubt';
}

__PACKAGE__->set_sql(user_tag => <<'');
SELECT 	 __ESSENTIAL(c2)__
FROM     __TABLE(Bibliotech::User_Bookmark=c1)__,
         __TABLE(Bibliotech::User_Bookmark_Tag=c2)__
WHERE  	 __JOIN(c1 c2)__
AND      c1.user = ?
AND      c2.tag = ?
ORDER BY c2.created

1;
__END__
