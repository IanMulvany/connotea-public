# Copyright 2005 Nature Publishing Group
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# The Bibliotech::Page class calls the component modules required
# and constructs a "page" of output.

package Bibliotech::Page;
use strict;
use base 'Class::Accessor::Fast';
use IO::File;
use XML::Element;
use XML::RSS;
use YAML;
use Template;
use List::Util qw/first reduce/;
use List::MoreUtils qw/any/;
use Encode qw/decode_utf8/;
use Bibliotech;
use Bibliotech::Const;
use Bibliotech::FilterNames;
use Bibliotech::Component::List;
use Bibliotech::Cache;
use Bibliotech::Util;
use Bibliotech::Profile;
use Bibliotech::Cookie;
use Bibliotech::Bookmarklets;
use Bibliotech::BibUtils qw(ris2bib xml2bib ris2end ris2xml ris2word);

our $TEMPLATE_ROOT    = Bibliotech::Config->get('TEMPLATE_ROOT');
our $EXPORT_MAX_COUNT = Bibliotech::Config->get('EXPORT_MAX_COUNT') || 1000;
our $TITLE_OVERRIDE   = Bibliotech::Config->get('TITLE_OVERRIDE') || {};
our $GLOBAL_CSS_FILE  = Bibliotech::Config->get('GLOBAL_CSS_FILE') || 'global.css';
our $HOME_CSS_FILE    = Bibliotech::Config->get('HOME_CSS_FILE') || $GLOBAL_CSS_FILE;

__PACKAGE__->mk_accessors(qw/bibliotech component_obj_cache last_updated_basis_cache/);

sub cache_key_internal {
  my ($self, $module, $options) = @_;
  return Bibliotech::Cache::Key->new(class => $module, options => $options);
}

sub instance {
  my ($self, $module, $options) = @_;
  $options = $self->parse_component_call_options($module, $options) unless ref $options;
  my $cache_key = $self->cache_key_internal($module, $options);
  my $cache = $self->component_obj_cache || {};
  my $cache_entry = $cache->{$cache_key};
  return wantarray ? ($cache_entry, $cache_key) : $cache_entry if defined $cache_entry;
  my $class = 'Bibliotech::Component::'.$module;
  unless (defined &{$class.'::list'} or defined &{$class.'::html_content'} or defined &{$class.'::list'}) {
    eval 'use '.$class;
    die $@ if $@;
  }
  my $bibliotech = $self->bibliotech or die 'no bibliotech object';
  my $obj = $class->new({bibliotech => $bibliotech, parts => {}, options => $options});
  $cache->{$cache_key} = $obj;
  $self->component_obj_cache($cache);
  return wantarray ? ($obj, $cache_key) : $obj;
}

sub plain_content {
  my ($self, $verbose) = @_;
  my $obj = $self->instance($self->main_component);
  return $obj->plain_content($verbose);
}

sub txt_content {
  my ($self, $verbose) = @_;
  my $obj = $self->instance($self->main_component);
  return $obj->txt_content($self->bibliotech, $verbose);
}

sub find_template_root_calc {
  my $site_docroot = shift;
  my $templateroot = $TEMPLATE_ROOT or return $site_docroot;
  $templateroot =~ s|^([^/])|$site_docroot.$1|e;
  $templateroot =~ s|([^/])$|$1/|;
  return $templateroot;
}

sub find_template_root {
  find_template_root_calc(shift->bibliotech->docroot);
}

# look for a template; actually a worker sub called by find_template() below
# given a static filesystem this is a theoretically functional routine
sub find_template_calc {
  shift if $_[0] eq __PACKAGE__;  # support class method or plain call
  my $templateroot 	    = shift or die 'no template root specified';   # e.g. '/var/templates'
  my $output 	   	    = shift or die 'no output format specified';   # e.g. 'html'
  my $page   	   	    = shift or die 'no page type specified';       # e.g. 'recent'
  my $filters_used_arrayref = shift || [];  	                           # e.g. ['user','tag']
  my $extension             = shift or die 'no file extension specified';  # e.g. '.tpl'
  my $verb                  = shift;                                       # e.g. 'GET', 'POST'
  my $return_code           = shift;                                       # e.g. 200, 404

  $templateroot    =~ s|([^/])$|$1/|;  # ensure trailing slash
  my $folder       = $output ne 'html' ? $output.'/' : '';
  my $localroot    = $templateroot.$folder;
  -e $localroot or $localroot = $templateroot;  # /rss won't work because it doesn't exist
  my $name         = $page; # join('_', map { lc $_ } grep { $_ } ($page, $verb, $return_code));
  my $base         = $localroot.$name;

  my @recognized_qualifiers = (lc($verb),
			       int($return_code),
			       map { my $name = $_;
				     my $filter = first { $_->{name} eq $name } @FILTERS;
				     $filter->{label};
				   } @{$filters_used_arrayref},
			       );
  my %recognized_qualifiers = map { $_ => 1 } @recognized_qualifiers;

  my @match;
  foreach my $path (glob qq($base*$extension)) {
    my ($q) = $path =~ m|^\Q$base\E(.*)\Q$extension\E|;               # e.g. $1 = '_user_tag'
    next if $q =~ /^[^_]/;                                            # e.g. reject 'editpopup' for 'edit'
    my @file_qualifiers = ($q =~ /_([a-z0-9]+)/g);                    # split up based on leading underscore
    next if any { not $recognized_qualifiers{$_} } @file_qualifiers;  # reject if any not expected
    my $score = @file_qualifiers + 1;  # the 1 represents the basename match but it's a bit academic
    push @match, [$score => $path];    # e.g. [2, recent_user.tpl] and [3, recent_user_tag.tpl] are both matches
  }

  # return path with highest score, or alpha to break tie
  return (reduce { return $a if $a->[0] > $b->[0];
		   return $b if $a->[0] < $b->[0];
		   return $a if ($a->[1] cmp $b->[1]) < 0;
		   return $b;
		 } @match)->[1] if @match;

  # drop back to default template file - either popup, admin, or normal
  if ($page =~ /popup$/) {
    if (-e (my $defaultpopup = $localroot.'defaultpopup'.$extension)) {
      return $defaultpopup;
    }
  }
  if ($page =~ /^admin/) {
    if (-e (my $defaultadmin = $localroot.'defaultadmin'.$extension)) {
      return $defaultadmin;
    }
  }
  if (-e (my $default = $localroot.'default'.$extension)) {
    return $default;
  }

  return;  # not even a default - complete failure
}

sub find_template_for_command {
  my ($self, $extension, $command, $rc) = @_;
  find_template_calc($self->find_template_root,
		     $command->output,
		     $command->page_or_inc,
		     $command->filters_used_arrayref,
		     $extension || '.tpl',
		     $command->verb,
		     $rc,
		     );
}

sub find_template {
  my ($self, $extension, $rc) = @_;
  $extension ||= '.tt'; # '.tpl';
  my $cache_key = 'template:'.$extension.':'.($rc || '');
  if (defined (my $cached = $Bibliotech::Apache::QUICK{$cache_key})) {
    return $cached;
  }
  my $command = $self->bibliotech->command;
  return $Bibliotech::Apache::QUICK{$cache_key} = $self->find_template_for_command($extension, $command, $rc);
}

sub template_filename {
  shift->find_template(@_);
}

sub components {
  my ($self, $output) = @_;
  my $components;
  eval { $self->tt_content(undef, {$self->tt_functions_for_html_content(sub { $components = shift; 1; })}) };
  die $@ if $@ and $@ !~ /END PREPARE/;
  return defined $components ? @{$components} : ();
}

sub parse_component_call_options {
  my ($self, $module, $options) = @_;

  my %options;
  foreach (split(/\s*,\s*/, $options)) {
    my ($key, $value) = /^(\w+)(?:\s*=\s*(.*))?$/;
    next unless $key;
    $value = 1 unless length $value;
    $options{$key} = $value;
  }

  # hack to make include-based pages work
  if ($module eq 'Inc' and !$options{filename}) {
    my $page = $self->bibliotech->command->page;
    if ($page and ref $page) {
      $options{filename} = $page->[1];
    }
  }

  return \%options;
}

sub last_updated {
  my ($self, $output, $disregard_pid) = @_;
  my $basis_cache = $self->last_updated_basis_cache;
  my %times;
  my $generic = new Bibliotech::Component ({bibliotech => $self->bibliotech});
  unless ($disregard_pid) {
    my $time = $generic->last_updated_calc('PID', $basis_cache);
    $times{PID} = ref $time ? $time->epoch : $time;
  }
  if ($output eq 'html') {
    my $filename = $self->template_filename;
    my $time = $generic->last_updated_calc($filename, $basis_cache);
    $times{$filename} = ref $time ? $time->epoch : $time;
  }
  foreach ($self->components($output)) {
    my ($module, undef, $options_ref) = @{$_};
    my $obj = $self->instance($module, $options_ref);
    my $obj_times = $obj->last_updated_hash($basis_cache);
    foreach (keys %{$obj_times}) {
      my $time = $obj_times->{$_};
      $times{$_} = $time if $time > $times{$_};
    }
  }
  my @times = sort {$b <=> $a} grep(defined $_, values %times);
  return $times[0] unless wantarray;
  return ($times[0], $times[0]) if !$times{LOGIN} or $times{LOGIN} != $times[0];
  return ($times[0], $times[1]);
}

sub html_content_component_section {
  my ($module, $part, $key, $obj,
      $cgi, $local_cache, $last_updated_basis_cache,
      $init_main_sub, $add_main_html_sub, $add_javascript_onload_sub, $add_javascript_block_sub) = @_;

  my $result = '';

  eval {
    my $options = $obj->options;
    my $last_updated = $obj->last_updated($last_updated_basis_cache);

    my $html_content_obj;
    unless ($html_content_obj = $local_cache->{$key}) {
      Bibliotech::Profile::start("generating component html_content ($key)");
      $local_cache->{$key} = $html_content_obj = $obj->html_content($options->{element_class} || lc($module),
								    $options->{verbose},
								    $options->{main});
      Bibliotech::Profile::stop();
      unless (UNIVERSAL::can($html_content_obj, 'content')) {
	warn 'deprecated non-object return value received from '.ref($obj);
	$html_content_obj = Bibliotech::Page::HTML_Content->simple($html_content_obj);
      }
      if (my $script = $html_content_obj->get_javascript) {
	$add_javascript_block_sub->($script->{block})   if $script->{block};
	$add_javascript_onload_sub->($script->{onload}) if $script->{onload};
      }
    }

    if ($result = $html_content_obj->get_part($part)) {
      my $css_id    = $options->{id};
      my $css_class = $options->{class};
      $result = $cgi->div({$css_id ? (id => $css_id) : (),
			   $css_class ? (class => $css_class) : ()},
			  $result) if $css_id or $css_class;
      my $trailing_br_count = $options->{br};
      $result .= ($cgi->br x (int($trailing_br_count)) || 1) if $trailing_br_count;
    }

    $init_main_sub->($obj->main_title, $obj->main_heading, $obj->main_description) if $options->{main};
  };
  if ($@) {
    if ($@ =~ / at line /) {
      $result = "<!-- No \"$module\": $@ -->";
    }
    else {
      die $@;
    }
  }

  $add_main_html_sub->($result);
}

sub tt_functions_for_html_content {
  my ($self, $prepared_callback) = @_;
  my $bibliotech = $self->bibliotech;
  my $content = Bibliotech::Page::HTML_Content->new_with_parts;
  my %local_cache;
  my $init_main = 0;
  my $init_main_sub = sub {
    $content->title(shift);
    $content->heading(shift);
    $content->description(shift);
    $init_main++;
  };
  my @prepare_component;
  return
      (prepare_component_begin => sub {
	 #warn 'prepare_component_begin called';
	 @prepare_component = ();
	 return '';
       },
       prepare_component => sub {
	 my ($module, $parts, $options) = @_;
	 $module = $self->main_component if !$module or $module eq 'main';
	 $parts ||= 'main';
	 my $options_parsed = $self->parse_component_call_options($module, $options);
	 my ($obj, $key) = ($self->instance($module, $options_parsed));
	 my @parts = split(/,\s*/, $parts);
	 $obj->parts->{$_}++ foreach (@parts);
	 push @prepare_component, [$module, $options, $options_parsed, \@parts, $key, $obj];
	 return '';
       },
       prepare_component_end => sub {
	 #warn 'prepare_component_end called';
	 # if calculating last_updated() for page, bail out:
	 if (defined $prepared_callback) {
	   die "END PREPARE\n" if $prepared_callback->(\@prepare_component);
	 }
	 # otherwise run components:
	 foreach (@prepare_component) {
	   my ($module, $options, $options_parsed, $parts, $key, $obj) = @{$_};
	   foreach my $part (@{$parts}) {
	     html_content_component_section
		 ($module, $part, $key, $obj,
		  $bibliotech->cgi, \%local_cache, $self->last_updated_basis_cache,
		  $init_main_sub,
		  sub { push @{$content->html_parts->{join(':', $module, $part, $options)}}, shift },
		  sub { push @{$content->javascript_onload}, shift },
		  sub { push @{$content->javascript_block}, shift },
		  );
	   }
	 }
	 # for when there is no component selected as the main one
	 unless ($init_main) {
	   my $obj = Bibliotech::Component->new({bibliotech => $bibliotech});
	   $init_main_sub->($obj->main_title, $obj->main_heading, $obj->main_description);
	 }
	 # for title overrides from master config
	 if (my $title_override = $TITLE_OVERRIDE->{$bibliotech->command->page_or_inc_filename}) {
	   $content->title($bibliotech->replace_text_variables([$title_override], $bibliotech->user)->[0]);
	 }
	 return '';
       },
       component_html => sub { 
	 my ($module, $part, $options) = @_;
	 $module = $self->main_component if !$module or $module eq 'main';
	 $part ||= 'main';
	 my $key = join(':', $module, $part, $options);
	 my $html = $content->get_part($key);
	 return "Component part \"$key\" was not prepared." unless defined $html;
	 return $html;
       },
       without_heading => sub {
	 local $_ = shift;
	 s|<h1.*?>.*?<\/h1>||mi or
	 s|<h2.*?>.*?<\/h2>||mi;
	 return $_;
       },
       component_javascript_onload => sub {
	 return $content->get_javascript->{onload} || '';
       },
       component_javascript_onload_if_needed => sub {
	 my $onload = $content->get_javascript->{onload} or return '';
	 return ' onload="'.Bibliotech::Util::encode_xhtml_utf8($onload).'"';
       },
       component_javascript_block => sub {
	 return $content->get_javascript->{block} || '';
       },
       component_javascript_block_if_needed => sub {
	 my $script = $content->get_javascript->{block} or return '';
	 return join('', "<script>\n", $script, ($script =~ /\n\z/ ? '' : "\n"), "</script>\n");
       },
       main_title_set => sub {
	 $content->title(shift); '';
       },
       main_title => sub {
	 return $content->title || join(': ', $bibliotech->sitename, $bibliotech->command->page_or_inc);
       },
       main_heading => sub {
	 return $content->heading || '';
       },
       main_description => sub {
	 return $content->description || '';
       },
       css_link => sub {
	 return join("\n",
		     map { "<link rel=\"stylesheet\" type=\"text/css\" href=\"$_\" />" }
		     map { $bibliotech->location.$_ }
		     map { ref $_ ? @{$_} : ($_) }
		     ($bibliotech->command->page_or_inc eq 'home' ? $HOME_CSS_FILE : $GLOBAL_CSS_FILE)
		     ) || '';
       },
       rss_link => sub {
	 return join("\n",
		     map { "<link type=\"".RSS_MIME_TYPE_STRICT."\" title=\"RSS\" rel=\"alternate\" href=\"$_\" />" }
		     ($bibliotech->has_rss ? ($bibliotech->command->rss_href($bibliotech)) : ())
		     );
       },
       );
}

sub html_content {
  my $self = shift;
  return $self->tt_content(undef, {$self->tt_functions_for_html_content});
}

sub rss_content_profiled {
  my $self = shift;
  Bibliotech::Profile::start('Bibliotech::Page::rss_content()');
  my $rss = $self->rss_content_(@_);
  Bibliotech::Profile::stop();
  return $rss;
}

sub rss_content {
  my ($self) = @_;

  my $bibliotech  = $self->bibliotech;
  my $location    = $bibliotech->location;
  my $command     = $bibliotech->command;
  my $obj         = $self->instance($self->main_component);
  my @rss_items   = $obj->rss_content(1);

  return $rss_items[0] if @rss_items && !ref($rss_items[0]);

  Bibliotech::Profile::start('building XML::RSS object');

  my $title 	  = $obj->main_title;
  my $about 	  = $command->canonical_uri($location);
  my $link  	  = $command->canonical_uri($location, {output => [set => 'html']});
  my $description = $obj->main_description;

  # to accomodate the fact that XML::RSS cannot handle multilpe dc:subjects directly we handle encoding ourselves
  # and pass in a cheated string for dc:subject
  my $rss = XML::RSS->new(encode_output => 0);
  $rss->add_module(prefix => 'connotea', uri => 'http://www.connotea.org/2005/01/schema#');
  $rss->add_module(prefix => 'content',  uri => 'http://purl.org/rss/1.0/modules/content/');
  $rss->add_module(prefix => 'annotate', uri => 'http://purl.org/rss/1.0/modules/annotate/');
  $rss->add_module(prefix => 'slash',    uri => 'http://purl.org/rss/1.0/modules/slash/');
  $rss->add_module(prefix => 'prism',    uri => 'http://prismstandard.org/namespaces/1.2/basic/');
  $rss->add_module(prefix => 'dcterms',  uri => 'http://purl.org/dc/terms/');
  $rss->channel(title        => Bibliotech::Util::encode_xml_utf8($title),
		about        => Bibliotech::Util::encode_xml_utf8($about),
		link         => Bibliotech::Util::encode_xml_utf8($link),
		description  => Bibliotech::Util::encode_xml_utf8($description));
  foreach my $item (@rss_items) {
    $item->{title}       = Bibliotech::Util::encode_xml_utf8($item->{title}) 	   if $item->{title};
    $item->{link}        = Bibliotech::Util::encode_xml_utf8($item->{link})  	   if $item->{link};
    $item->{link}        =~ s/ /\%20/g;
    $item->{description} = Bibliotech::Util::encode_xml_utf8($item->{description}) if $item->{description};
    $item->{dc}->{subject} = join("</dc:subject>\n<dc:subject>",
				  map(Bibliotech::Util::encode_xml_utf8($_),
				      @{$item->{dc}->{subject}}))
	if $item->{dc}->{subject};
    $rss->add_item(%$item);
  }

  my $remove_superfluous_xml_namespace_inclusion = sub {
    local $_ = shift;
    my $alternation = join('|', @_);
    s/^\s*xmlns:(?:$alternation)=\"[^\"]*\"\s*\n//gm;
    return $_;
  };

  my $final = $remove_superfluous_xml_namespace_inclusion->($rss->as_string, qw/syn taxo admin/);

  Bibliotech::Profile::stop();

  return $final;
}

sub ris_content {
  my ($self) = @_;
  my $obj = $self->instance($self->main_component);
  my @items = $obj->ris_content(1);
  die "More than $EXPORT_MAX_COUNT items, RIS disallowed.\n" if @items > $EXPORT_MAX_COUNT;
  return array_hash2ris(\@items);
}

sub array_hash2ris {
  join("\r\n", grep { defined $_ } map { hash2ris($_) } @{$_[0]});
}

my @hash2ris = qw/TY ID T1 TI CT BT T2 BT T3 A1 AU A2 ED A3 Y1 PY Y2 N1 AB N2 KW RP JF JO JA J1 J2
                  VL IS SP EP CP CY PB SN AD AV M1 M2 M3 U1 U2 U3 U4 U5 UR L1 L2 L3 L4/;

sub hash2ris {
  my $hash = shift;
  die 'too many arguments' if @_;
  my @entry = (map { my ($k, $v) = ($_, $hash->{$_}); map { "$k  - $_" } (ref $v eq 'ARRAY' ? @{$v} : ($v)) }
	       grep { $hash->{$_} } @hash2ris)
      or return;
  push @entry, 'ER  - ', '';
  return join('', map { "$_\r\n" } @entry);
}

sub data_content {
  my ($self) = @_;
  my $obj = $self->instance($self->main_component);
  return YAML::Dump([$obj->list]);
}

sub geo_content {
  my ($self) = @_;

  my $list = $self->instance($self->main_component);

  my $bibliotech = $self->bibliotech;
  my $command = $bibliotech->command;
  my $cgi = $bibliotech->cgi;
  my $location = $bibliotech->location;
  my $sitename = $bibliotech->sitename;

  my $description_content = 'Geotagged bookmarks from '.$cgi->a({href => $location}, $sitename);
  my $icon_href = $location.'icon.png';
  my $heading = $command->description(user_block => [undef,
						     [undef, 1, "\'s"],
						     [undef, 1, "\'s"]],
				      gang_block => [undef,
						     [undef, 1, "\'s"],
						     [undef, 1, "\'s"]],
				      tag_block  => [undef,
						     [undef, 1, undef],
						     [undef, 1, undef]],
				      postfix    => 'bookmarks from '.$sitename
				      );
  my $xml_pi = XML::Element->new('~pi', text => 'xml version="1.0"');
  my $root = XML::Element->new('kml', xmlns => 'http://earth.google.com/kml/2.0');
  my $document = XML::Element->new('Document');
  $root->push_content($document);
  $document->push_content(XML::Element->new('description')->push_content($description_content));
  $document->push_content(XML::Element->new('name')->push_content($heading));
  $document->push_content(XML::Element->new('open')->push_content(1));
  $document->push_content(XML::Element->new('Style', id => 'connoteaPlacemark')
			  ->push_content(XML::Element->new('IconStyle')
					 ->push_content(XML::Element->new('Icon')
							->push_content(XML::Element->new('href')
								       ->push_content($icon_href)))));

  my $lookat_range = 2200000;
  my $lookat_tilt = 26.4;
  my $lookat_heading = 10;

  foreach my $item ($list->geo_content(1)) {
    next unless defined $item;
    my $longitude = $item->{longitude};
    my $latitude = $item->{latitude};
    my $lookat_longitude = $longitude + 10;
    my $lookat_latitude = $latitude - 10;

    my $placemark = XML::Element->new('Placemark');
    $placemark->push_content(XML::Element->new('name')->push_content($item->{name}));
    $placemark->push_content(XML::Element->new('description')->push_content($item->{description}));
    my $point = XML::Element->new('Point');
    $point->push_content(XML::Element->new('altitudeMode')->push_content('absolute'));
    $point->push_content(XML::Element->new('coordinates')->push_content("$longitude,$latitude,0"));
    $placemark->push_content($point);
    my $lookat = XML::Element->new('LookAt');  # not well named, really "look from"
    $lookat->push_content(XML::Element->new('latitude')->push_content($lookat_latitude));
    $lookat->push_content(XML::Element->new('longitude')->push_content($lookat_longitude));
    $lookat->push_content(XML::Element->new('range')->push_content($lookat_range));
    $lookat->push_content(XML::Element->new('tilt')->push_content($lookat_tilt));
    $lookat->push_content(XML::Element->new('heading')->push_content($lookat_heading));
    $placemark->push_content($lookat);
    $placemark->push_content(XML::Element->new('styleUrl')->push_content('#connoteaPlacemark'));
    $document->push_content($placemark);
  }

  return $xml_pi->as_XML.$root->as_XML;
}

sub text_decode_wide_characters_to_bibhacks {
  local $_ = shift;
  s/-\[c(\d+)c\]-/sprintf('(bibhack(&#x%X;q%d))', $1, $1)/ge;
  return $_;
}

sub fix_bibhack {
  my ($possibly_latex_entity, $original_char_code) = @_;
  return $possibly_latex_entity if $possibly_latex_entity =~ m|[\\\{]|;
  return chr($original_char_code);
}

sub cleanup_bibhacks {
  local $_ = shift;
  s/\(bibhack\(([^q]+)q(\d+)\)\)/fix_bibhack($1,$2)/ge;
  return $_;
}

sub bib_fix_key {
  local $_ = shift;
  s/[^\x00-\xFF]/_/g;
  return $_;
}

sub bib_fix_utf8_in_keys {
  local $_ = shift;
  s/^(\@[^{]+{)([^,]+)(,)/$1.bib_fix_key($2).$3/mge;
  return $_;
}

# also consider prefixing with \usepackage[utf8]{inputenc}
sub bib_content {
  bib_fix_utf8_in_keys
    (cleanup_bibhacks
      (decode_utf8
        (xml2bib
	  (text_decode_wide_characters_to_bibhacks
	    (ris2xml
	      (Bibliotech::Util::text_encode_wide_characters
	        (shift->ris_content)))))));
}

sub end_content {
  Bibliotech::Util::text_decode_wide_characters
    (ris2end
      (Bibliotech::Util::text_encode_wide_characters
        (shift->ris_content)));
}

sub mods_content {
  Bibliotech::Util::text_decode_wide_characters_to_xml_entities
   (ris2xml
     (Bibliotech::Util::text_encode_wide_characters
       (shift->ris_content)));
}

sub word_content {
  Bibliotech::Util::text_decode_wide_characters
   (ris2word
     (Bibliotech::Util::text_encode_wide_characters
       (shift->ris_content)));
}

sub tt_content_template_toolkit_object {
  my $include_path = pop;
  Template->new({INCLUDE_PATH => $include_path,
		 INTERPOLATE  => 1,
		 POST_CHOMP   => 0,
		 EVAL_PERL    => 1,
	        });
}

sub tt_content {
  my ($self, $rc, $special_vars_hashref) = @_;
  my $root     = $self->find_template_root;
  my $filename = $self->template_filename('.tt', $rc) or die "no acceptable template found ($root)";
  $filename =~ s/^$root//;  # INCLUDE_PATH takes care of the root
  return $self->tt_process($self->tt_content_template_toolkit_object($root),
			   $filename,
			   $special_vars_hashref);
}

sub tt_content_for_web_api {
  my ($self, $answer) = @_;
  return $self->tt_content($answer->code, {answer => $answer});
}

sub tt_process {
  my ($self, $tt, $filename_without_root, $special_vars_hashref) = @_;
  return tt_process_calc($tt,
			 $filename_without_root,
			 {$self->tt_general_vars, %{$special_vars_hashref||{}}});
}

sub tt_process_calc {
  my ($tt, $filename_without_root, $vars_hashref) = @_;
  my $output = '';
  $tt->process($filename_without_root, $vars_hashref, \$output) or die $tt->error;
  return $output;
}

sub tt_general_vars {
  my $self       = shift;
  my $bibliotech = $self->bibliotech;
  my $command    = $bibliotech->command;
  return $self->tt_general_vars_calc($bibliotech, $command);
}

sub tt_general_vars_calc {
  my ($self, $bibliotech, $command) = @_;
  return (bibliotech         => $bibliotech,
	  location           => $bibliotech->location,
	  link               => $bibliotech->link,
	  sitename           => $bibliotech->sitename,
	  siteemail          => $bibliotech->siteemail,
	  user               => $bibliotech->user,
	  do {
	    my $browser;
	    my $get_done = 0;
	    my $get = sub { unless ($get_done) { $browser = $bibliotech->request->header_in('User-Agent');
						 $get_done = 1; }
			    return $browser || '';
			  };
	    (is_browser_safari  => sub { $get->() =~ /Safari/ },
	     is_browser_firefox => sub { $get->() =~ /Firefox/ },
	     is_browser_ie      => sub { $get->() =~ /MSIE/ },
	     is_browser_other   => sub { $get->() !~ /(MSIE|Firefox|Safari)/ },
	     ),
	  },
	  browser_redirect => sub {
	    my $uri = shift;
	    $uri = $bibliotech->location.$uri unless $uri =~ /^[a-z]{3,6}:/;
	    die "Location: $uri\n";
	  },
	  is_virgin          => sub { Bibliotech::Cookie->has_virgin_cookie($bibliotech->request) },
	  canonical_uri      => sub { $command->canonical_uri },
	  canonical_location => sub { $command->canonical_uri($bibliotech->location) },
	  object_location    => sub { $command->canonical_uri_via_html($bibliotech->location) },
	  no_num             => sub { local $_ = shift; s/([?&])num=\d+&?(.*)/$1$2/; s/\?$//; $_; },
	  instance           => sub { scalar $self->instance(shift || $self->main_component, @_) },
	  encode_xml_utf8    => \&Bibliotech::Util::encode_xml_utf8,
	  encode_xhtml_utf8  => \&Bibliotech::Util::encode_xhtml_utf8,
	  now                => \&Bibliotech::Util::now,
	  time               => \&Bibliotech::Util::time,
	  join               => \&join,
	  speech_join        => \&Bibliotech::Util::speech_join,
	  plural             => \&Bibliotech::Util::plural,
	  commas             => \&Bibliotech::Util::commas,
	  divide             => \&Bibliotech::Util::divide,
	  percent            => \&Bibliotech::Util::percent,
	  date_obj           => sub { Bibliotech::Date->new(@_) },
	  bookmarklets       => sub { Bibliotech::Bookmarklets::bookmarklets
					  ($bibliotech->sitename, $bibliotech->location, $bibliotech->cgi) },
	  bookmarklet        => sub { Bibliotech::Bookmarklets::bookmarklet
					  ($bibliotech->sitename, $bibliotech->location, $bibliotech->cgi, @_) },
	  bookmarklet_js     => sub { Bibliotech::Bookmarklets::bookmarklet_javascript
					  ($bibliotech->sitename, $bibliotech->location, $bibliotech->cgi, @_) },
	  user_in_own_library     => sub { $bibliotech->in_my_library },
	  user_in_another_library => sub { $bibliotech->in_another_library },
	  click_counter_onclick   => sub { Bibliotech::Clicks::CGI::onclick_bibliotech($bibliotech, @_) },
	  debug_param        => sub { my $cgi = $bibliotech->cgi or return;
				      $cgi->param('debug'); },
	  design_test_param  => sub { my $cgi = $bibliotech->cgi or return;
				      $cgi->param('designtest'); },
	  passed_bookmark    => sub { my $cgi = $bibliotech->cgi or return;
				      my $uri = $cgi->param('uri') or return;
				      Bibliotech::Bookmark->new($uri); },
	  );
}

package Bibliotech::Page::HTML_Content;
use strict;
use base 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw/html_parts javascript_block javascript_onload title description heading/);

sub new_with_parts {
  shift->new({html_parts        => {main => []},
	      javascript_block  => [],
	      javascript_onload => [],
	     });
}

sub blank {
  shift->simple('');
}

sub simple {
  my ($self, $html, $title) = @_;
  # not required here but makes cached objects more ready for output:
  $html = join('', @{$html}) if ref($html) eq 'ARRAY';
  return $self->new({html_parts => {main => $html}, title => $title});
}

sub get_part {
  my ($self, $part) = @_;
  my $parts = $self->html_parts or return undef;
  my $html = $parts->{$part};
  return join('', @{$html}) if ref($html) eq 'ARRAY';
  return $html;
}

sub content {
  shift->get_part('main');
}

sub get_javascript {
  my $self     = shift;
  my $block    = $self->javascript_block;
  my $onload   = $self->javascript_onload;
  return {$block  ? (block  => _flatten_javascript_array("\n", $block)) : (),
	  $onload ? (onload => _flatten_javascript_array(' ', $onload)) : ()};
}

sub _flatten_javascript_array {
  my ($joinchar, $block) = @_;
  return undef unless $block;
  return $block unless ref $block eq 'ARRAY';
  return join($joinchar, map { s/(?<![;\n])\z/;/; $_; } @{$block});
}

1;
__END__
