# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Const module just exports some constants.

package Bibliotech::Const;
use strict;
require Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(HTML_MIME_TYPE
		 XML_MIME_TYPE
		 RDF_MIME_TYPE
		 RSS_MIME_TYPE
		 RSS_MIME_TYPE_STRICT
		 RIS_MIME_TYPE
		 TEXT_MIME_TYPE
		 GEO_MIME_TYPE
		 CSS_MIME_TYPE
		 BIBTEX_MIME_TYPE
		 ENDNOTE_MIME_TYPE
		 MODS_MIME_TYPE
		 URI_TERM
		 URI_TERM_CAPITALIZED
		 URI_TERM_PROMPT);

use constant HTML_MIME_TYPE 	    => 'text/html';
use constant XML_MIME_TYPE  	    => 'application/xml';
use constant RDF_MIME_TYPE  	    => 'application/xml';
use constant RSS_MIME_TYPE  	    => 'application/xml';
use constant RSS_MIME_TYPE_STRICT   => 'application/rss+xml';
use constant RIS_MIME_TYPE          => 'application/x-research-info-systems';
use constant TEXT_MIME_TYPE         => 'text/plain';
use constant GEO_MIME_TYPE          => 'application/vnd.google-earth.kml+xml';
use constant CSS_MIME_TYPE          => 'text/css';
use constant BIBTEX_MIME_TYPE       => 'application/x-bibtex';
use constant ENDNOTE_MIME_TYPE      => 'application/x-bibliographic';
use constant MODS_MIME_TYPE         => 'application/xml';

use constant URI_TERM               => 'bookmark';
use constant URI_TERM_CAPITALIZED   => 'Bookmark';
use constant URI_TERM_PROMPT        => 'Bookmark URL';

1;
__END__
