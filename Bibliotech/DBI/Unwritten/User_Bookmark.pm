package Bibliotech::Unwritten::User_Bookmark;
use strict;
use base ('Bibliotech::Unwritten', 'Bibliotech::User_Bookmark');

__PACKAGE__->columns(TEMP => qw/x_tags title description/);
# title and description are needed in TEMP because you can't relate a User_Bookmark_Details object to an undefined User_Bookmark

sub tags {
  my ($self, $value) = @_;
  $self->x_tags($value) if defined $value;
  my $tags_ref = $self->x_tags or return ();
  return @{$tags_ref};
}

sub link_tag {
  my $self = shift;
  my @tags = $self->tags;
  foreach (@_) {
    my $tag = ref $_ ? $_ : construct Bibliotech::Tag ({Bibliotech::Tag->unique => $_});
    push @tags, $tag;
  }
  $self->tags(\@tags);
}

1;
__END__
