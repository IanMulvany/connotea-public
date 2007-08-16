package Bibliotech::WebAPI;
use strict;

package Bibliotech::WebAPI::Answer;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/list code message vars/);

sub new {
  my ($class, $options) = @_;
  $options ||= {};
  chomp $options->{message} if $options->{message};
  $options->{list} ||= [];
  $options->{vars} ||= {};
  return $class->SUPER::new($options);
}

sub is_success { 
  my $code = shift->code or return;
  return $code =~ /^2\d\d$/;
}

sub is_failure {
  return !shift->is_success;
}

package Bibliotech::WebAPI::Action;
use base 'Class::Accessor::Fast';
use Bibliotech::Util;

__PACKAGE__->mk_accessors(qw/bibliotech/);

sub answer {
  return;
}

# match a Bibliotech::Page legacy object
sub last_updated {
  my $now = Bibliotech::Util::time();
  return wantarray ? ($now, $now) : $now;
}

# match a Bibliotech::Page legacy object
sub data_content {
  shift->answer(@_);
}

package Bibliotech::WebAPI::Action::NotImplemented;
use base 'Bibliotech::WebAPI::Action';

sub not_implemented_message {
  'Not Implemented';
}

sub answer {
  return Bibliotech::WebAPI::Answer->new({code    => 501,
					  message => shift->not_implemented_message,
					  list    => [],
					});
}

package Bibliotech::WebAPI::Action::Noop::Get;
use base 'Bibliotech::WebAPI::Action';

sub answer {
  return Bibliotech::WebAPI::Answer->new({code    => 200,
					  message => 'No Operation OK',
					  list    => [],
					});
}

package Bibliotech::WebAPI::Action::GenericQuery;
use base ('Bibliotech::WebAPI::Action', 'Bibliotech::Page');

sub main_component {
  my $self   	 = shift;
  my $class  	 = ref $self || $self;
  my ($page)     = $class =~ m/^Bibliotech::WebAPI::Action::(\w+)::\w+$/;
  die "cannot deduce page from class \"$class\"" unless $page;
  my $page_class = 'Bibliotech::Page::'.$page;
  return $page_class->main_component;
}

sub last_updated {
  Bibliotech::Page::last_updated(@_);
}

sub answer {
  my $self = shift;
  my $main = $self->instance($self->main_component) or die 'no main component instance';
  my $iter = $main->list(main => 1); defined $iter or die 'no iterator';  # should be a Bibliotech::DBI::Set
  #if ($iter->count == 0) {
    #return Bibliotech::WebAPI::Answer->new
	#({code    => 404,
	  #message => 'No items found',
	  #list    => [],
	#});
  #}
  my $bibliotech = $self->bibliotech;
  my $num = $bibliotech->command->num;
  my $max_num = 1000;
  if (defined $num and $num > $max_num) {
    $num = $max_num;
    my $host = $bibliotech->location->host;
    my $text = 'Not all records - '.
               "parameter num set a value greater than the maximum of $max_num; reset to $max_num";
    $bibliotech->request->headers_out->set(Warning => "199 $host $text");
  }
  return Bibliotech::WebAPI::Answer->new
        ({code    => 200,
	  message => 'Items found',
	  list    => $iter,
	});
}

package Bibliotech::WebAPI::Action::Recent::Get;
use base 'Bibliotech::WebAPI::Action::GenericQuery';

package Bibliotech::WebAPI::Action::Tags::Get;
use base 'Bibliotech::WebAPI::Action::GenericQuery';

package Bibliotech::WebAPI::Action::Populartags::Get;
use base 'Bibliotech::WebAPI::Action::GenericQuery';

package Bibliotech::WebAPI::Action::Users::Get;
use base 'Bibliotech::WebAPI::Action::GenericQuery';

package Bibliotech::WebAPI::Action::Bookmarks::Get;
use base 'Bibliotech::WebAPI::Action::GenericQuery';

package Bibliotech::WebAPI::Action::Home::Get;
use base 'Bibliotech::WebAPI::Action::Recent::Get';

package Bibliotech::WebAPI::Action::AddOrEdit::Post;
use base 'Bibliotech::WebAPI::Action';

sub answer {
  my $self          = shift;
  my $action        = shift;
  my $bibliotech    = $self->bibliotech;
  my $addform       = Bibliotech::Component::AddForm->new({bibliotech => $bibliotech});
  my $user_bookmark
      = eval { $addform->call_action_with_cgi_params($action, $bibliotech->user, $bibliotech->cgi); };
  if ($@) {
    my $code = 500;
    $code = 404 if $@ =~ /\bnot found\b/;
    $code = 400 if $@ =~ /\bmalformed tags\b/;
    return Bibliotech::WebAPI::Answer->new
	({code    => $code,
	  message => $@,
	  list    => [],
	});
  }
  $bibliotech->request->headers_out->set(Location => $user_bookmark->href_search_global($bibliotech));
  return Bibliotech::WebAPI::Answer->new
        ({code    => 201,
	  message => "\u$action OK",
	  list    => [$user_bookmark],
	});
}

package Bibliotech::WebAPI::Action::Add::Post;
use base 'Bibliotech::WebAPI::Action::AddOrEdit::Post';

sub answer {
  shift->SUPER::answer('add');
}

package Bibliotech::WebAPI::Action::Edit::Post;
use base 'Bibliotech::WebAPI::Action::AddOrEdit::Post';

sub answer {
  shift->SUPER::answer('edit');
}

package Bibliotech::WebAPI::Action::Remove::Post;
use base 'Bibliotech::WebAPI::Action';

sub answer {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $user       = $bibliotech->user;
  eval {
    my $uri = $bibliotech->cgi->param('uri') or die "No URI specified.\n";
    $bibliotech->remove(user => $user, uri => $uri) or die "No URI removed.\n";
  };
  if ($@) {
    my $code = 500;
    $code = 404 if $@ =~ /^No URI/;
    return Bibliotech::WebAPI::Answer->new
	({code    => $code,
	  message => $@,
	  list    => [],
	});
  }
  return Bibliotech::WebAPI::Answer->new
        ({code    => 200,
	  message => 'Remove OK',
	  list    => [],
	});
}

package Bibliotech::WebAPI::Action::Adminstats::Get;
use base 'Bibliotech::WebAPI::Action';
use Bibliotech::Component::AdminStats;

sub answer {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $stats      = Bibliotech::Component::AdminStats->new({bibliotech => $bibliotech});
  return Bibliotech::WebAPI::Answer->new
        ({code    => 200,
	  message => 'Stats',
	  list    => [],
	  vars    => $stats->stat_vars,
	});
}

1;
__END__
