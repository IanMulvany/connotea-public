package Bibliotech::Comment;
use strict;
use base 'Bibliotech::DBI';
use Bibliotech::Query;
use Bibliotech::Util;

__PACKAGE__->table('comment');
__PACKAGE__->columns(Primary => qw/comment_id/);
__PACKAGE__->columns(Essential => qw/entry created/);
__PACKAGE__->columns(Others => qw/updated/);
__PACKAGE__->force_utf8_columns(qw/entry/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->has_many(user_article_comments => 'Bibliotech::User_Article_Comment');

sub my_alias {
  'c';
}

sub unique {
  'entry';
}

sub html_content {
  my ($self, $bibliotech, $class, $verbose, $main) = @_;
  my $entry = $self->entry;
  $entry =~ s/^(.{50,65})\s.+$/$1.../ unless $verbose;
  return $bibliotech->cgi->div({class => $class}, Bibliotech::Util::encode_markup_xhtml_utf8($entry));
}

__PACKAGE__->set_sql(from_article_need_privacy => <<'');
SELECT 	 __ESSENTIAL(c)__
FROM     __TABLE(Bibliotech::Article=a)__,
         __TABLE(Bibliotech::User_Article=ua)__,
       	 __TABLE(Bibliotech::User_Article_Comment=uac)__,
         __TABLE(Bibliotech::Comment=c)__
WHERE  	 __JOIN(a ua)__
AND    	 __JOIN(ua uac)__
AND    	 __JOIN(uac c)__
AND    	 a.article_id = ?
AND      %s
GROUP BY c.comment_id
ORDER BY c.created

sub search_from_article {
  my ($self, $article_id) = @_;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_from_article_need_privacy($privacywhere);
  return $self->sth_to_objects($sth, [$article_id, @privacybind]);
}

__PACKAGE__->set_sql(from_user_article => <<'');
SELECT 	 __ESSENTIAL(c)__
FROM     __TABLE(Bibliotech::User_Article=ua)__,
       	 __TABLE(Bibliotech::User_Article_Comment=uac)__,
         __TABLE(Bibliotech::Comment=c)__,
WHERE  	 __JOIN(ua uac)__
AND    	 __JOIN(uac c)__
AND    	 ua.user_article_id = ?
GROUP BY c.comment_id
ORDER BY uac.created

1;
__END__
