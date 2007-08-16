package Bibliotech::Component::LoginBox;
use strict;
use base 'Bibliotech::Component';
use Bibliotech::DBI;

sub last_updated_basis {
  ('LOGIN')
}

sub html_content {
  my ($self, $class, $verbose) = @_;
  my $bibliotech = $self->bibliotech;
  my $o;
  if (my $username = $bibliotech->request->notes->{'username'}) {
    my $location = $bibliotech->location;
    $o = qq|
	<div id="loginbox">
	<h1 class="loginbox">|.$username.qq|\'s account</h1>
	<p class="tooltype"><img src="arrow.gif" width="9" height="9" alt="" /> <a href="${location}library">My library</a></p>
	<p class="tooltype"><img src="arrow.gif" width="9" height="9" alt="" /> <a href="${location}register">Change my registration details</a></p>
	<p class="tooltype"><a href="${location}logout"><img src="logout.gif" alt="logout" title="logout" border="0" /> </a></p>
	</div>
	|;
  }
  else {
    $o = $self->include('loginbox');
  }
  return Bibliotech::Page::HTML_Content->simple($o);
}

1;
__END__
