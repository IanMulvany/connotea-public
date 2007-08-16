# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This file determines what the main component for each page is.

use strict;

package Bibliotech::Page::None;
use base 'Bibliotech::Page';

sub main_component {
  'None';
}

package Bibliotech::Page::Reportspam;
use base 'Bibliotech::Page';

sub main_component {
    'ReportSpam';
}

package Bibliotech::Page::Inc;
use base 'Bibliotech::Page';

sub main_component {
  'Inc';
}

package Bibliotech::Page::Error;
use base 'Bibliotech::Page';

sub main_component {
  'Error';
}

package Bibliotech::Page::Recent;
use base 'Bibliotech::Page';

sub main_component {
  'ListOfRecent';
}

package Bibliotech::Page::Home;
use base 'Bibliotech::Page';

sub main_component {
  'ListOfRecent';
}

package Bibliotech::Page::Wiki;
use base 'Bibliotech::Page';

sub main_component {
  'Wiki';
}

package Bibliotech::Page::Cloud;
use base 'Bibliotech::Page';

sub main_component {
  'TagCloud';
}

package Bibliotech::Page::Blog;
use base 'Bibliotech::Page';

sub main_component {
  'Blog';
}

package Bibliotech::Page::Forgotpw;
use base 'Bibliotech::Page';

sub main_component {
  'ForgotPasswordForm';
}

package Bibliotech::Page::Resendreg;
use base 'Bibliotech::Page';

sub main_component {
  'ResendVerificationForm';
}

package Bibliotech::Page::Reportproblem;
use base 'Bibliotech::Page';

sub main_component {
  'ReportProblemForm';
}

package Bibliotech::Page::Popular;
use base 'Bibliotech::Page';

sub main_component {
  'ListOfPopular';
}

package Bibliotech::Page::Populartags;
use base 'Bibliotech::Page';

sub main_component {
  'PopularTags';
}

package Bibliotech::Page::Bookmarks;
use base 'Bibliotech::Page';

sub main_component {
  'ListOfBookmarks';
}

package Bibliotech::Page::Users;
use base 'Bibliotech::Page';

sub main_component {
  'ListOfUsers';
}

package Bibliotech::Page::Groups;
use base 'Bibliotech::Page';

sub main_component {
  'ListOfGangs';
}

package Bibliotech::Page::Tags;
use base 'Bibliotech::Page';

sub main_component {
  'ListOfTags';
}

package Bibliotech::Page::Comments;
use base 'Bibliotech::Page';

sub main_component {
  'Comments';
}

package Bibliotech::Page::Commentspopup;
use base 'Bibliotech::Page';

sub main_component {
  'Comments';
}

package Bibliotech::Page::Register;
use base 'Bibliotech::Page';

sub main_component {
  'RegisterForm';
}

package Bibliotech::Page::Advanced;
use base 'Bibliotech::Page';

sub main_component {
  'AdvancedForm';
}

package Bibliotech::Page::Login;
use base 'Bibliotech::Page';

sub main_component {
  'LoginForm';
}

package Bibliotech::Page::Loginpopup;
use base 'Bibliotech::Page';

sub main_component {
  'LoginForm';
}

package Bibliotech::Page::Logout;
use base 'Bibliotech::Page';

sub main_component {
  'LogoutForm';
}

package Bibliotech::Page::Verify;
use base 'Bibliotech::Page';

sub main_component {
  'VerifyForm';
}

package Bibliotech::Page::Search;
use base 'Bibliotech::Page';

sub main_component {
  'SearchForm';
}

package Bibliotech::Page::Add;
use base 'Bibliotech::Page';

sub main_component {
  'AddForm';
}

package Bibliotech::Page::Upload;
use base 'Bibliotech::Page';

sub main_component {
  'UploadForm';
}

package Bibliotech::Page::Addcomment;
use base 'Bibliotech::Page';

sub main_component {
  'AddCommentForm';
}

package Bibliotech::Page::Addcommentpopup;
use base 'Bibliotech::Page';

sub main_component {
  'AddCommentForm';
}

package Bibliotech::Page::Edit;
use base 'Bibliotech::Page';

sub main_component {
  'EditForm';
}

package Bibliotech::Page::Editpopup;
use base 'Bibliotech::Page';

sub main_component {
  'EditForm';
}

package Bibliotech::Page::Remove;
use base 'Bibliotech::Page';

sub main_component {
  'RemoveForm';
}

package Bibliotech::Page::Addpopup;
use base 'Bibliotech::Page';

sub main_component {
  'AddForm';
}

package Bibliotech::Page::Retag;
use base 'Bibliotech::Page';

sub main_component {
  'RetagForm';
}

package Bibliotech::Page::Addgroup;
use base 'Bibliotech::Page';

sub main_component {
  'AddGroupForm';
}

package Bibliotech::Page::Editgroup;
use base 'Bibliotech::Page';

sub main_component {
  'EditGroupForm';
}

package Bibliotech::Page::Addtagnote;
use base 'Bibliotech::Page';

sub main_component {
  'AddUserTagAnnotationForm';
}

package Bibliotech::Page::Edittagnote;
use base 'Bibliotech::Page';

sub main_component {
  'EditUserTagAnnotationForm';
}

package Bibliotech::Page::Killspammer;
use base 'Bibliotech::Page';

sub main_component {
  'KillSpammerForm';
}

package Bibliotech::Page::Export;
use base 'Bibliotech::Page';

sub main_component {
  'ExportForm';
}

package Bibliotech::Page::Admin;
use base 'Bibliotech::Page';

sub main_component {
  'AdminForm';
}

package Bibliotech::Page::Adminstats;
use base 'Bibliotech::Page';

sub main_component {
  'AdminStats';
}

package Bibliotech::Page::Adminrenameuser;
use base 'Bibliotech::Page';

sub main_component {
  'AdminRenameUserForm';
}

1;
__END__
