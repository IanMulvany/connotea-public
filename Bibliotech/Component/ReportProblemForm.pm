# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::ReportProblem class provides a form
# to report site bugs.

package Bibliotech::Component::ReportProblemForm;
use strict;
use base ('Bibliotech::Component', 'Class::Accessor::Fast');
use Bibliotech::Util qw/without_hyperlinks_or_trailing_spaces without_spaces/;

__PACKAGE__->mk_accessors(qw/exception/);

sub last_updated_basis {
  ('NOW');
}

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $cgi        = $bibliotech->cgi;

  my $validationmsg;
  if ($cgi->param('button') eq 'Report') {
    eval {
      my $problem = $cgi->param('problem') or die "Please describe the problem.\n";
      validate_problem_text($problem);
      $bibliotech->notify_admin(file => 'report_problem_email',
				var  => {exception => $cgi->param('exception') || undef,
					 problem   => $problem,
					 email     => $cgi->param('email')     || undef,
					 referer   => $cgi->param('referer')   || $cgi->referer || undef,
					 clicktime => $cgi->param('clicktime') || undef,
				        })
	  or die 'could not send administrator notification';
    };
    if ($@) {
      $validationmsg = $@;
    }
    else {
      return Bibliotech::Page::HTML_Content->simple($self->tt('compreportproblemthanks'));
    }
  }

  my $o = $self->tt('compreportproblem',
		    {referer   => $cgi->param('referer') || $cgi->referer || undef,
		     clicktime => $cgi->param('clicktime') || Bibliotech::Util::now->mysql_datetime,
		     exception => $self->exception || 'User-reported.',
		     is_main   => $main,
		    },
		    $self->validation_exception('', $validationmsg));

  my $javascript_first_empty = $self->firstempty($cgi, 'problem', qw/problem/);

  return Bibliotech::Page::HTML_Content->new({html_parts => {main => $o},
					      javascript_onload => ($main ? $javascript_first_empty : undef)});
}

sub validate_problem_text {
  local $_ = shift;
  length(without_spaces($_))
      or die "You may not submit a report without text.\n";
  length(without_hyperlinks_or_trailing_spaces($_))
      or die "You may not submit a report consisting only of hyperlinks. ".
             "Please note that reports submitted here are directed only to management and are not seen by users.\n";
  return 1;
}

1;
__END__
