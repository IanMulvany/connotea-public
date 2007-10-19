package Bibliotech::User_Article_Comment;
use strict;
use base 'Bibliotech::DBI';
use Bibliotech::Query;

__PACKAGE__->table('user_article_comment');
__PACKAGE__->columns(Primary => qw/user_article_comment_id/);
__PACKAGE__->columns(Essential => qw/user_article comment created/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_a(user_article => 'Bibliotech::User_Article');
__PACKAGE__->has_a(comment => 'Bibliotech::Comment');

sub my_alias {
  'uac';
}

__PACKAGE__->set_sql(from_article_need_privacy => <<'');
SELECT 	 __ESSENTIAL(uac)__
FROM     __TABLE(Bibliotech::Article=a)__,
         __TABLE(Bibliotech::User_Article=ua)__,
       	 __TABLE(Bibliotech::User_Article_Comment=uac)__
WHERE  	 __JOIN(a ua)__
AND    	 __JOIN(ua uac)__
AND    	 a.article_id = ?
AND      %s
GROUP BY uac.user_article_comment_id
ORDER BY uac.created

sub search_from_article {
  my ($self, $article_id) = @_;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_from_article_need_privacy($privacywhere);
  return $self->sth_to_objects($sth, [$article_id, @privacybind]);
}

sub plain_content {
  my ($self, $verbose) = @_;
  return $self->comment->plain_content(0) unless $verbose;
  my ($text, $time) = $self->comment->plain_content(1);
  my $username = $self->user_article->user->username;
  return "$text ($username $time)";
}

1;
__END__
