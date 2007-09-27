package Bibliotech::User_Bookmark_Comment;
use strict;
use base 'Bibliotech::DBI';
use Bibliotech::Query;

__PACKAGE__->table('user_bookmark_comment');
__PACKAGE__->columns(Primary => qw/user_bookmark_comment_id/);
__PACKAGE__->columns(Essential => qw/user_bookmark comment created/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_a(user_bookmark => 'Bibliotech::User_Bookmark');
__PACKAGE__->has_a(comment => 'Bibliotech::Comment');

sub my_alias {
  'ubc';
}

__PACKAGE__->set_sql(from_bookmark_need_privacy => <<'');
SELECT 	 __ESSENTIAL(ubc)__
FROM     __TABLE(Bibliotech::Bookmark=b)__,
         __TABLE(Bibliotech::User_Bookmark=ub)__,
       	 __TABLE(Bibliotech::User_Bookmark_Comment=ubc)__
WHERE  	 __JOIN(b ub)__
AND    	 __JOIN(ub ubc)__
AND    	 b.bookmark_id = ?
AND      %s
GROUP BY ubc.user_bookmark_comment_id
ORDER BY ubc.created

sub search_from_bookmark {
  my ($self, $bookmark_id) = @_;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_from_bookmark_need_privacy($privacywhere);
  return $self->sth_to_objects($sth, [$bookmark_id, @privacybind]);
}

sub plain_content {
  my ($self, $verbose) = @_;
  return $self->comment->plain_content(0) unless $verbose;
  my ($text, $time) = $self->comment->plain_content(1);
  my $username = $self->user_bookmark->user->username;
  return "$text ($username $time)";
}

1;
__END__
