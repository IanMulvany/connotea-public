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
__PACKAGE__->has_many(user_bookmark_comments => 'Bibliotech::User_Bookmark_Comment');

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

__PACKAGE__->set_sql(from_bookmark_need_privacy => <<'');
SELECT 	 __ESSENTIAL(c)__
FROM     __TABLE(Bibliotech::Bookmark=b)__,
         __TABLE(Bibliotech::User_Bookmark=ub)__,
       	 __TABLE(Bibliotech::User_Bookmark_Comment=ubc)__,
         __TABLE(Bibliotech::Comment=c)__
WHERE  	 __JOIN(b ub)__
AND    	 __JOIN(ub ubc)__
AND    	 __JOIN(ubc c)__
AND    	 b.bookmark_id = ?
AND      %s
GROUP BY c.comment_id
ORDER BY c.created

sub search_from_bookmark {
  my ($self, $bookmark_id) = @_;
  my ($privacywhere, @privacybind) = Bibliotech::Query->privacywhere($Bibliotech::Apache::USER);
  my $sth = $self->sql_from_bookmark_need_privacy($privacywhere);
  return $self->sth_to_objects($sth, [$bookmark_id, @privacybind]);
}

__PACKAGE__->set_sql(from_user_bookmark => <<'');
SELECT 	 __ESSENTIAL(c3)__
FROM     __TABLE(Bibliotech::User_Bookmark=c1)__,
       	 __TABLE(Bibliotech::User_Bookmark_Comment=c2)__,
         __TABLE(Bibliotech::Comment=c3)__,
WHERE  	 __JOIN(c1 c2)__
AND    	 __JOIN(c2 c3)__
AND    	 c1.user_bookmark_id = ?
GROUP BY c3.comment_id
ORDER BY c2.created

1;
__END__
