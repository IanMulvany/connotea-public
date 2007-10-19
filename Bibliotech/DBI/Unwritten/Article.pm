package Bibliotech::Unwritten::Article;
use strict;
use base ('Bibliotech::Unwritten', 'Bibliotech::Article');
use Class::DBI::Iterator;

sub citation {
  my $self = shift;
  return $self->SUPER::citation(@_) if @_;
  return $self->SUPER::citation if $self->_attribute_exists('citation');
  return undef;
}

# it is not necessarily the truth that a particular article has no
# user_articles, but it is usually the practically useful response
# when dealing with an unwritten article object because it's probably
# just being displayed somewhere
sub user_articles {
  return wantarray ? () : Class::DBI::_ids_to_objects('Bibliotech::User_Article', []);
}

# helper routine for citation web service
# takes a URI and Bibliotech::Unwritten::Citation and returns a Bibliotech::Unwritten::Article
# basically just takes care of setting created and hash for you
sub new_from_url_and_citation {
  my ($class, $url, $citation) = @_;
  my $article = $class->construct({url => $url,
				   citation => $citation,
				   created => Bibliotech::Date->new});
  $article->set_correct_hash;
  return $article;
}

1;
__END__
