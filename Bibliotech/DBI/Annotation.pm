package Bibliotech::Annotation;
use strict;
use base 'Class::Accessor::Fast';
# that MUST be ::Fast or you will have inheritance problems in Bibliotech::User_Tag_Annotation

__PACKAGE__->mk_accessors(qw/comment title/);

sub html_content {
  my ($self, $bibliotech, $class, $verbose, $main) = @_;
  my $cgi = $bibliotech->cgi;
  my $comment = $self->comment;
  my $title = $self->title;
  my $annotation = $comment->html_content($bibliotech, $class, $verbose, $main);
  return $cgi->div({class => 'annotation'},
		   $cgi->div({class => 'comment'}, $annotation),
		   (defined $title
		    ? $cgi->div({class => 'title'},
				Bibliotech::Util::encode_markup_xhtml_utf8($title))
		    : ()));
}

sub standard_annotation_html_content {
  my ($self, $bibliotech, $class, $verbose, $main, $comment_text) = @_;
  my $comment = construct Bibliotech::Unwritten::Comment ({entry => $comment_text});
  my $a = new Bibliotech::Annotation ({comment => $comment});
  return $a->html_content($bibliotech, $class, $verbose, $main);
}

1;
__END__
