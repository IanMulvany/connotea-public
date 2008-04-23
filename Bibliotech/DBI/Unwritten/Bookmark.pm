package Bibliotech::Unwritten::Bookmark;
use strict;
use base ('Bibliotech::Unwritten', 'Bibliotech::Bookmark');
use Class::DBI::Iterator;

sub citation {
  my $self = shift;
  return $self->SUPER::citation(@_) if @_;
  return $self->SUPER::citation if $self->_attribute_exists('citation');
  return undef;
}

# it is not necessarily the truth that a particular URI has no
# user_articles, but it is usually the practically useful response
# when dealing with an unwritten bookmark object because it's probably
# just being displayed somewhere
sub user_articles {
  return wantarray ? () : Class::DBI::_ids_to_objects('Bibliotech::User_Article', []);
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

# used for JSON output in WebCite
sub json_content {
  my $self = shift;
  return {url      => $self->url->as_string,
	  hash     => $self->hash,
	  citation => $self->citation->json_content};
}

1;
__END__
