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
		 JAVASCRIPT_MIME_TYPE
		 BIBTEX_MIME_TYPE
		 ENDNOTE_MIME_TYPE
		 MODS_MIME_TYPE
                 WORD_MIME_TYPE
                 HTML_EXTENSION
                 XML_EXTENSION
                 RDF_EXTENSION
                 RSS_EXTENSION
                 RIS_EXTENSION
                 TEXT_EXTENSION
                 GEO_EXTENSION
                 CSS_EXTENSION
                 JAVASCRIPT_EXTENSION
                 BIBTEX_EXTENSION
                 ENDNOTE_EXTENSION
                 MODS_EXTENSION
                 WORD_EXTENSION
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
use constant JAVASCRIPT_MIME_TYPE   => 'application/x-javascript';
use constant BIBTEX_MIME_TYPE       => 'application/x-bibtex';
use constant ENDNOTE_MIME_TYPE      => 'application/x-bibliographic';
use constant MODS_MIME_TYPE         => 'application/xml';
use constant WORD_MIME_TYPE  	    => 'application/xml';

use constant HTML_EXTENSION 	    => '.html';
use constant XML_EXTENSION  	    => '.xml';
use constant RDF_EXTENSION  	    => '.rdf';
use constant RSS_EXTENSION  	    => '.rss';
use constant RIS_EXTENSION          => '.ris';
use constant TEXT_EXTENSION         => '.txt';
use constant GEO_EXTENSION          => '.kml';
use constant CSS_EXTENSION          => '.css';
use constant JAVASCRIPT_EXTENSION   => '.js';
use constant BIBTEX_EXTENSION       => '.bib';
use constant ENDNOTE_EXTENSION      => '.end';
use constant MODS_EXTENSION         => '.xml';
use constant WORD_EXTENSION  	    => '.xml';

use constant URI_TERM               => 'bookmark';
use constant URI_TERM_CAPITALIZED   => 'Bookmark';
use constant URI_TERM_PROMPT        => 'Bookmark URL';

1;
__END__
