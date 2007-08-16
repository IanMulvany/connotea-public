# Copyright 2006 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Component::ExportForm class provides a format
# selector for the implicit query.

package Bibliotech::Component::ExportForm;
use strict;
use base 'Bibliotech::Component';
use URI;
use URI::QueryParam;
use Bibliotech::Parser;
use Bibliotech::Component::List;
use Bibliotech::Const;

sub html_content {
  my ($self, $class, $verbose, $main) = @_;

  my $bibliotech = $self->bibliotech;
  my $location   = $bibliotech->location;
  my $command    = $bibliotech->command;

  my $output_uri = sub {
    my ($output, $download) = @_;
    die "invalid output format in output_uri() call: $output\n"
	unless grep { $output eq $_ } @Bibliotech::Parser::OUTPUTS;
    my $uri = $command->canonical_uri($location, {output => [set => $output],
						  page   => [set => 'recent'],
						  start  => [set => undef],
						  num    => [set => undef],
						});
    $uri->query_param(download => $download) if $download;
    return $uri;
  };

  my ($full_count, $full_geocount);
  my $get_full_count = sub { return $full_count if defined $full_count;
			     return $full_count = $bibliotech->query->full_count($bibliotech->user);
			   };
  my $get_geo_count  = sub { return $full_geocount if defined $full_geocount;
			     return $full_geocount = $bibliotech->query->full_geocount($bibliotech->user);
			   };
  my %vars =
      (output_uri          => $output_uri,
       output_uri_download => sub { $output_uri->(shift, 'file') },
       output_uri_view     => sub { $output_uri->(shift, 'view') },
       download_value      => 'file',
       view_value          => 'view',
       normal_heading      => sub { Bibliotech::Component::List->new({bibliotech => $bibliotech})
					->heading_dynamic(1) },
       count               => $get_full_count,
       count_str           => sub { my $count = $get_full_count->();
				    my $term = URI_TERM;
				    return "$count ${term}s" unless $count == 1;
				    return "1 $term";
				  },
       geo_count           => $get_geo_count,
       has_geo             => sub { $get_geo_count->() > 0 },
      );

  return Bibliotech::Page::HTML_Content->simple($self->tt('compexport', \%vars));
}

1;
__END__
