package Bibliotech::Gang;
use strict;
use base 'Bibliotech::DBI';

__PACKAGE__->table('gang');
#__PACKAGE__->columns(All => qw/gang_id name owner description private created/);
__PACKAGE__->columns(Primary => qw/gang_id/);
__PACKAGE__->columns(Essential => qw/name owner private updated/);
__PACKAGE__->columns(Others => qw/description created/);
__PACKAGE__->force_utf8_columns(qw/name/);
__PACKAGE__->datetime_column('created', 'before_create');
__PACKAGE__->datetime_column('updated', 'before_update');
__PACKAGE__->has_a(owner => 'Bibliotech::User');
__PACKAGE__->has_many(users => ['Bibliotech::User_Gang' => 'user']);

__PACKAGE__->set_sql(from_user_packed => <<'');
SELECT 	 __ESSENTIAL(g)__, COUNT(ug2.user_gang_id) as member
FROM     __TABLE(Bibliotech::User_Gang=ug)__
         LEFT JOIN __TABLE(Bibliotech::Gang=g)__ ON (__JOIN(ug g)__)
   	 LEFT JOIN __TABLE(Bibliotech::User_Gang=ug2)__ ON (__JOIN(g ug2)__ AND ug2.user = ?)
WHERE  	 ug.user = ?
GROUP BY g.gang_id
HAVING   g.private = 0 OR g.owner = ? OR member != 0

sub my_alias {
  'g';
}

sub noun {
  'group';
}

sub access_users {
  my $self = shift;
  my @users = $self->users;
  my $owner = $self->owner;
  my $owner_user_id = $owner->user_id;
  push @users, $owner unless grep { $_->user_id == $owner_user_id } @users;
  return @users;
}

sub is_accessible_by_user {
  my ($self, $user) = @_;
  return unless defined $user;
  my $user_id = $user->user_id;
  return grep { $_->user_id == $user_id } $self->access_users;
}

sub access_message {
  'You must be a member/owner of group '.shift->label.' to view this page.';
}

sub tags {
  my $self = shift;
  my %seen;
  my @tags;
  foreach my $user ($self->users) {
    foreach my $tag ($user->tags) {
      next if $seen{$tag->get('tag_id')}++;
      push @tags, $tag;
    }
  }
  return @tags;
}

sub user_bookmarks {
  my $self = shift;
  my $q = new Bibliotech::Query;
  $q->set_gang($self);
  $q->activeuser($Bibliotech::Apache::USER);
  return $q->user_bookmarks;
}

sub unique {
  'name';
}

sub visit_link {
  my ($self, $bibliotech, $class) = @_;
  return $bibliotech->cgi->div({class => ($class || 'referent')},
			       'Go to the group',
			       $self->SUPER::link($bibliotech, undef, 'href_search_global', undef, 1).'\'s',
			       $bibliotech->sitename,
			       'library.',
			       );
}

sub link_user {
  my $self = shift;
  my @ug = map(Bibliotech::User_Gang->find_or_create({gang => $self, user=> Bibliotech::User->new($_)}), @_);
  return wantarray ? @ug : $ug[0];
}

sub unlink_user {
  my $self = shift;
  foreach (@_) {
    my $user = Bibliotech::User->new($_) or next;
    my ($link) = Bibliotech::User_Gang->search(gang => $self, user => $user) or next;
    $link->delete;
    $self->delete unless $self->users->count;
  }
}

sub link {
  my ($self, $bibliotech, $class, $verbose, $main, $href_type) = @_;
  my $link = $self->SUPER::link($bibliotech, $class, $verbose, $main, $href_type);
  if ($verbose) {
    my $cgi = $bibliotech->cgi;
    $link .= ' ';
    if ($Bibliotech::Apache::USER_ID and $Bibliotech::Apache::USER_ID == $self->get('owner')) {
      $link .= '('.$cgi->a({class => 'editlink', href => $bibliotech->location.'editgroup?name='.$self->name}, 'edit').')';
    }
    else {
      $link .= $cgi->span({class => 'ownedby'},
			  '(created by '.$self->owner->link($bibliotech, 'owner', 'href_search_global', undef, 1).')');
    }
  }
  return $link;
}

sub standard_annotation_text {
  my ($self, $bibliotech, $register) = @_;
  my $sitename = $bibliotech->sitename;
  my $gangname = $self->name;
  return "This is a list of the articles and links in the collection of $sitename group $gangname.
          To create your own $sitename collection, $register";
}

sub delete {
  #warn 'delete gang';
  my $self = shift;
  # one extra chore with deleting a gang is the user_bookmarks that are private to that gang:
  #   private to gang -> becomes private to user
  #   private to gang with embargo date -> becomes private to user, keep embargo date
  my $iter = Bibliotech::User_Bookmark->search(private_gang => $self);
  while (my $user_bookmark = $iter->next) {
    $user_bookmark->private(1);
    $user_bookmark->private_gang(undef);
    $user_bookmark->mark_updated;
  }
  return $self->SUPER::delete(@_);
}

1;
__END__
