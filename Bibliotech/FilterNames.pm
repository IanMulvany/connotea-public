# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::FilterNames class simply exports an informational structure that lists
# the filters available to a user and defines basic metadata that the program code can
# use in a loop. Changes to the available filters are not quite complete by editing this
# file alone (although a single point like that would be nice); you must also visit
# Bibliotech::DBI, ::Command, ::Parser, and sometimes ::Query.

package Bibliotech::FilterNames;
use strict;
require Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(@FILTERS %FILTERS);

# the order of this array must match the order of the units in the 'command' production in Bibliotech::Parser right after output and page
our @FILTERS = ({code => 'USER',
		 name => 'user',
		 label => 'user',
		 class => 'Bibliotech::User',
		 db => 1,
		 table => 'user',
		 table_primary => 'u.user_id',
		 table_search => 'u.username'},
		{code => 'GANG',
		 name => 'gang',
		 label => 'group',
		 class => 'Bibliotech::User',
		 db => 1,
		 table => 'gang',
		 table_primary => 'g.gang_id',
		 table_search => 'g.name'},
		{code => 'TAG',
		 name => 'tag',
		 label => 'tag',
		 class => 'Bibliotech::Tag',
		 db => 1,
		 table => 'tag',
		 table_primary => 't.tag_id',
		 table_search => 't.name'},
		{code => 'DATE',
		 name => 'date',
		 label => 'date',
		 class => 'Bibliotech::Date',
		 db => 0,
		 table => 'date'},
		{code => 'BOOKMARK',
		 name => 'bookmark',
		 label => 'uri',
		 class => 'Bibliotech::Bookmark',
		 db => 1,
		 table => 'bookmark',
		 table_primary => 'b.bookmark_id',
		 table_search => 'b.url'});
our %FILTERS;
$FILTERS{$_->{name}} = $_ foreach (@FILTERS);

1;
__END__
