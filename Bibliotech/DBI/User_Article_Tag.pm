package Bibliotech::User_Article_Tag;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('user_article_tag');
__PACKAGE__->columns(Primary => qw/user_article_tag_id/);
__PACKAGE__->columns(Essential => qw/user_article tag/);
__PACKAGE__->columns(Others => qw/created/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_a(user_article => 'Bibliotech::User_Article');
__PACKAGE__->has_a(tag => 'Bibliotech::Tag');

sub my_alias {
  'uat';
}

__PACKAGE__->set_sql(user_tag => <<'');
SELECT 	 __ESSENTIAL(uat)__
FROM     __TABLE(Bibliotech::User_Article=ua)__,
         __TABLE(Bibliotech::User_Article_Tag=uat)__
WHERE  	 __JOIN(ua uat)__
AND      ua.user = ?
AND      uat.tag = ?
ORDER BY uat.created

1;
__END__
