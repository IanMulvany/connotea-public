package Bibliotech::WebAPI;
use strict;

package Bibliotech::WebAPI::Answer;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/list code message vars url dnote/);

sub new {
  my ($class, $options) = @_;
  $options ||= {};
  chomp $options->{message} if $options->{message};
  $options->{list} ||= [];
  $options->{vars} ||= {};
  return $class->SUPER::new($options);
}

sub simple {
  my ($class, $code, $message, $list, $vars, $url, $dnote) = @_;
  return $class->new({code    => $code,
		      message => $message,
		      list    => $list,
		      vars    => $vars,
		      url     => $url,
		      dnote   => $dnote});
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

# utility routine for children classes
sub make_answer {
  my $class = shift;
  return Bibliotech::WebAPI::Answer->simple(@_);
}

package Bibliotech::WebAPI::Action::NotImplemented;
use base 'Bibliotech::WebAPI::Action';

sub not_implemented_message {
  'Not Implemented';
}

sub answer {
  my $self = shift;
  $self->make_answer(501, $self->not_implemented_message);
}

package Bibliotech::WebAPI::Action::Noop::Get;
use base 'Bibliotech::WebAPI::Action';

sub answer {
  shift->make_answer(200, 'No Operation OK');
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
  #return $self->make_answer(404, 'No Items Found') if $iter->count == 0;
  my $bibliotech = $self->bibliotech;
  my $num = $bibliotech->command->num;
  my $max_num = 1000;
  my $dnote;
  if (defined $num and $num > $max_num) {
    $num = $max_num;
    $dnote = join(' ',
		  '199',
		  $bibliotech->location->host,
		  "Not all records - parameter num set a value greater than the maximum of $max_num; reset to $max_num");
  }
  return $self->make_answer(200, 'Items Found', $iter, undef, $dnote);
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
  my $self         = shift;
  my $action       = shift;
  my $bibliotech   = $self->bibliotech;
  my $addform      = Bibliotech::Component::AddForm->new({bibliotech => $bibliotech});
  my $user_article = eval { $addform->call_action_with_cgi_params($action, $bibliotech->user, $bibliotech->cgi); };
  if (my $e = $@) {
    my $code = 500;
    $code = 404 if $e =~ /\bnot found\b/;
    $code = 400 if $e =~ /\bmalformed tags\b/;
    if ($e =~ /^SPAM/) {
      $code = 403;
      $e = "SPAM\n";  # suppress additional information
    }
    return $self->make_answer($code, $e);
  }
  return $self->make_answer(201, ucfirst($action).' OK', [$user_article], $user_article->href_search_global($bibliotech));
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
  if (my $e = $@) {
    my $code = 500;
    $code = 404 if $e =~ /^No URI/;
    return $self->make_answer($code, $e);
  }
  return $self->make_answer(200, 'Remove OK');
}

package Bibliotech::WebAPI::AdminUtil;
use Bibliotech::Component::AdminForm;

sub is_admin_user {
  my $user = shift;
  my $username = $user->username;
  return grep { $username eq $_ } @{$Bibliotech::Component::AdminForm::ADMIN_USERS};
}

sub check_admin_user {
  return if is_admin_user(shift);
  return Bibliotech::WebAPI::Answer->new
        ({code    => 403,
	  message => 'Forbidden',
	  list    => [],
	});
}

package Bibliotech::WebAPI::Action::Admin::GetOrPost;
use base 'Bibliotech::WebAPI::Action';
use Bibliotech::Component::AdminForm;

sub answer {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $denied     = Bibliotech::WebAPI::AdminUtil::check_admin_user($bibliotech->user);
  return $denied if $denied;
  my $admin      = Bibliotech::Component::AdminForm->new({bibliotech => $bibliotech});
  my $results    = $admin->results($bibliotech->cgi);
  return Bibliotech::WebAPI::Answer->new
        ({code    => 200,
	  message => 'Admin Lookup',
	  list    => $results,
	  vars    => $admin->vars($results),
	});
}

package Bibliotech::WebAPI::Action::Admin::Get;
use base 'Bibliotech::WebAPI::Action::Admin::GetOrPost';

package Bibliotech::WebAPI::Action::Admin::Post;
use base 'Bibliotech::WebAPI::Action::Admin::GetOrPost';

package Bibliotech::WebAPI::Action::Adminstats::Get;
use base 'Bibliotech::WebAPI::Action';
use Bibliotech::Component::AdminStats;

sub answer {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $denied     = Bibliotech::WebAPI::AdminUtil::check_admin_user($bibliotech->user);
  return $denied if $denied;
  my $stats      = Bibliotech::Component::AdminStats->new({bibliotech => $bibliotech});
  return $self->make_answer(200, 'Stats', undef, $stats->stat_vars);
}

1;
__END__
