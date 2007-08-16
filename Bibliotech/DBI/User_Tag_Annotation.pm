package Bibliotech::User_Tag_Annotation;
use strict;
use base ('Bibliotech::Annotation', 'Bibliotech::DBI');

__PACKAGE__->table('user_tag_annotation');
__PACKAGE__->columns(Primary => qw/user_tag_annotation_id/);
__PACKAGE__->columns(Essential => qw/user tag comment/);
__PACKAGE__->columns(Others => qw/created/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->has_a(user => 'Bibliotech::User');
__PACKAGE__->has_a(tag => 'Bibliotech::Tag');
__PACKAGE__->has_a(comment => 'Bibliotech::Comment');

sub my_alias {
  'uta';
}

sub delete {
  my $self = shift;
  my $comment = $self->comment;
  #$self->SUPER::delete(@_);
  Class::DBI::delete($self, @_);
  $comment->delete if $comment;
}

sub html_content {
  my ($self, $bibliotech, $class, $verbose, $main) = @_;
  my $cgi = $bibliotech->cgi;
  my $user = $self->user;
  my $user_link = $user->link($bibliotech, undef, 'href_search_global');
  my $tag = $self->tag;
  my $tag_link = $tag->link($bibliotech, undef, 'href_search_global');
  my $title;
  if (defined $bibliotech->user && $user->user_id == $bibliotech->user->user_id) {
    $title = join(' ',
		  'This is your note for tag',
		  $tag_link,
		  '('.$cgi->a({href => $bibliotech->location.'edittagnote?tag='.$tag->name}, 'edit').')'
		  );
  }
  else {
    $title = join(' ',
		  'Note provided by',
		  $user_link,
		  'for tag',
		  $tag_link
		  );
  }
  $self->title($title);
  #return $self->SUPER::html_content($bibliotech, $class, $verbose, $main);
  return Bibliotech::Annotation::html_content($self, $bibliotech, $class, $verbose, $main);
}

__PACKAGE__->set_sql(by_users_and_tags => <<'');
SELECT 	 __ESSENTIAL__
FROM   	 __TABLE__
WHERE  	 user IN (%s) AND tag IN (%s)
ORDER BY created

sub by_users_and_tags {
  my ($self, $users_ref, $tags_ref) = @_;
  my @users = grep(defined $_, @{$users_ref}) or return ();
  my @tags = grep(defined $_, @{$tags_ref}) or return ();
  my $sth = $self->sql_by_users_and_tags(join(',', map('?', @users)), join(',', map('?', @tags)));
  $sth->execute(map($_->user_id, @users), map($_->tag_id, @tags));
  return map($self->construct($_), @{$sth->fetchall_hash});
}

sub change_tag {
  my ($class, $user, $old_tag, $new_tag) = @_;
  my $iter = $class->search(user => $user, tag => $old_tag);
  while (my $user_tag_annotation = $iter->next) {
    if ($class->search(user => $user, tag => $new_tag)->count == 0) {
      $user_tag_annotation->tag($new_tag);
      $user_tag_annotation->update;
    }
    else {
      $user_tag_annotation->delete;
    }
  }
}

1;
__END__
