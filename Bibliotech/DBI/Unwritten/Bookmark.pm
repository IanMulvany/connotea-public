package Bibliotech::Unwritten::Bookmark;
use strict;
use base ('Bibliotech::Unwritten', 'Bibliotech::Bookmark');
use Class::DBI::Iterator;

sub citation {
  my $self = shift;
  if (@_) {
    $self->SUPER::citation(@_);
  }
  else {
    return $self->SUPER::citation if $self->_attribute_exists('citation');
  }
  return undef;
}

# this is not necessarily the truth - that a particular URI has no user_bookmarks, but it is usually the practically useful response
sub user_bookmarks {
  return wantarray ? () : Class::DBI::_ids_to_objects('Bibliotech::User_Bookmark', []);
}

# helper routine for citation web service
# takes a URI and Bibliotech::Unwritten::Citation and returns a Bibliotech::Unwritten::Bookmark
# basically just takes care of setting created and hash for you
sub new_from_url_and_citation {
  my ($class, $url, $citation) = @_;
  my $bookmark = $class->construct({url => $url,
				    citation => $citation,
				    created => Bibliotech::Date->new});
  $bookmark->set_correct_hash;
  return $bookmark;
}

1;
__END__
