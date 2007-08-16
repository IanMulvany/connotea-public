# 
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
# 
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
# 
# The Original Code is the RDF::Core module
# 
# The Initial Developer of the Original Code is Ginger Alliance Ltd.
# Portions created by Ginger Alliance are 
# Copyright (C) 2001 Ginger Alliance Ltd.
# All Rights Reserved.
# 
# Contributor(s):
# 
# Alternatively, the contents of this file may be used under the
# terms of the GNU General Public License Version 2 or later (the
# "GPL"), in which case the provisions of the GPL are applicable 
# instead of those above.  If you wish to allow use of your 
# version of this file only under the terms of the GPL and not to
# allow others to use your version of this file under the MPL,
# indicate your decision by deleting the provisions above and
# replace them with the notice and other provisions required by
# the GPL.  If you do not delete the provisions above, a recipient
# may use your version of this file under either the MPL or the
# GPL.
# 

package Bibliotech::RDF::Core::Serializer;

use strict;

use Encode qw(decode_utf8 is_utf8);
use Carp;

use constant RDF_NS => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';

sub new {
    my ($pkg,%options) = @_;
    $pkg = ref $pkg || $pkg;
    my $self = {};
    carp "InlineURI parameter is deprecated" if $self->{_options}->{InlineURI};
    #Implemented options are:
    #getNamespaces, getSubjects, getStatements, existsStatement callback functions
    #output - output filehandle reference (a reference to a typeglob or FileHandle) or scalar variable reference (default \*STDOUT)
    $self->{_options} = \%options;
    $self->{_options}->{Output} = \*STDOUT
      unless defined $self->{_options}->{Output};
    $self->{_options}->{BaseURI};
    $self->{_options}->{InlinePrefix} ||= 'genid'
      unless defined $self->{_options}->{InlinePrefix};
    $self->{_descriptions} = undef;
    $self->{_namespaces} = undef;
    $self->{_recursionlvl} = 0;
    $self->{_idAttr} = 1;
    $self->{_anonym} = undef;
    bless $self, $pkg;
}
  sub getOptions {
      my $self = shift;
      return $self->{_options};
  }
sub serialize {
    my $self = shift;
    #get options if passed
    $self->{_options} = $_[0]
      if (@_ gt 0);
    $self->_rdfOpen;
    my $description = $self->_descriptionNext;
    while (defined $description) {
	$self->_descriptionProcess($description);
	$description = $self->_descriptionNext;
    }
    $self->_rdfClose;
    $self->_outputdone;
}
#callback functions
sub getNamespaces {
    my $self = shift;
    $self->{_namespaces} ||= &{$self->getOptions->{getNamespaces}}(@_);
    return $self->{_namespaces};
}
sub getSubjects {
    #Subjects are stored with 2 flags that say that corresponding description item was open/closed.
    #Array ($subject, openedFlag, closedFlag) will be called description not to mess with $subject itself (RDF::Core::Resource instance)
    my $self = shift;
    $self->{_descriptions} ||= &{$self->getOptions->{getSubjects}}(@_);
    return $self->{_descriptions};
}
sub getStatements {
    my $self = shift;
    return &{$self->getOptions->{getStatements}}(@_);
}
sub countStatements {
    my $self = shift;
    return &{$self->getOptions->{countStatements}}(@_);
}
sub existsStatement {
    my $self = shift;
    return &{$self->getOptions->{existsStatement}}(@_);
}
# new _rdfOpen allows you to specify order of XML namespace definitions, and pick one to be the default namespace
sub _rdfOpen {
    my $self = shift;
    #$self->_print ("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    my $defaultns = $self->getOptions->{defaultns};
    my $nsorder = $self->getOptions->{nsorder};
    my %nsorder = $nsorder ? %{$nsorder} : ();
    my %namespaces = %{$self->getNamespaces()};
    my %byprefix = map {$namespaces{$_} => $_;} keys %namespaces;
    my @namespaces = map {
	my $uri = $byprefix{$_}; $_ eq $defaultns ? "xmlns=\"$uri\"" : "xmlns:$_=\"$uri\"";
    } sort { ($nsorder{$a}||(100+length($a))) <=> ($nsorder{$b}||(100+length($b))); } values %namespaces;
    $self->_print ("<rdf:RDF\n", map("   $_\n", @namespaces), ">\n");
}
sub _rdfClose {
    my $self = shift;
    $self->_print ("</rdf:RDF>\n");
}
#get next description to be processed
sub _descriptionNext {
    my $self = shift;
    my $retval = undef;
    my %searched;
    # look for resources we noted to serialize
    if (defined $self->{_resources}) {
      for (my $i = 0; $i < @{$self->{_resources}}; $i++) {
	my ($referrer, $resource) = @{$self->{_resources}->[$i]};
	if (defined($self->getSubjects->{$resource}) &&
	    $self->getSubjects->{$referrer}->[2] &&
	    !$self->getSubjects->{$resource}->[1]) {
	  $retval = $self->getSubjects->{$resource};
	  splice @{$self->{_resources}}, $i, 1;
	  last;
	}
      }
    }
    if ($retval) {
      #print STDERR 'resource we noted to serialize: ', $retval->[0]->getURI, "\n";
      return $retval;
    }
    #first, look for subjects that are not objects of any statement
    foreach (values %{$self->getSubjects}) {
	unless ($_->[1]) {	#search in not yet opened descriptions
	    unless ($self->existsStatement(undef,undef,$_->[0])) {
		$retval = $_;
		last;
	    }
	}
    }
    if ($retval) {
      #print STDERR 'subject that is not object of any statement: ', $retval->[0]->getURI, "\n";
      return $retval;
    }
    #then look for subjects that are objects of a statement already serialized
    foreach (values %{$self->getSubjects}) {
      unless ($_->[1]) {	#search in not yet opened descriptions
	my $enum = $self->getStatements(undef,undef,$_->[0]);
	my $stmt = $enum->getNext;
	while (defined $stmt) {
	  if ($self->getSubjects->{$stmt->getSubject->getURI}->[2]) {
	    $retval = $_;
	    last;
	  }
	  $stmt = $enum->getNext;
	}
	$enum->close;
      }
      last if $retval;
    }
    if ($retval) {
      #print STDERR 'subject that is object of a statement already serialized: ', $retval->[0]->getURI, "\n";
      return $retval;
    }
    #return a subject of preferred type
    my $preferred_subject_type = $self->getOptions->{'preferred_subject_type'};
    my $preferred_search = $self->getStatements(undef, new RDF::Core::Resource(+RDF_NS.'type'), $preferred_subject_type);
    my $statement = $preferred_search->getFirst;
    while (defined $statement) {
      my $uri = $statement->getSubject->getURI;
      foreach (values %{$self->getSubjects}) {
	unless ($_->[1]) {	#search in not yet opened descriptions
	  if ($uri eq $_->[0]->getURI) {
	    $retval = $_;
	    last;
	  }
	}
      }
      $statement = $preferred_search->getNext;
    }
    if ($retval) {
      #print STDERR 'subject of preferred type: ', $retval->[0]->getURI, "\n";
      return $retval;
    }
    #at last, return any subject not serialized yet
    foreach (values %{$self->getSubjects}) {
      unless ($_->[1]) {	#search in not yet opened descriptions
	$retval = $_;
	last;
      }
    }
    #if ($retval) {
      #print STDERR 'any subject not yet serialized: ', $retval->[0]->getURI, "\n";
    #}
    return $retval;
}
sub _descriptionProcess {
    my ($self, $description) = @_;
    $self->_descriptionOpen($description);
    my $enumerator = $self->getStatements($description->[0],undef,undef);
    my $statement = $enumerator->getNext;
    while (defined $statement) {
	$self->_descriptionData($statement);
	$statement = $enumerator->getNext;
    }
    $enumerator->close;
    $self->_descriptionClose($description);
}
sub _tag {
    my ($self,$namespace,$propertyname) = @_;
    my $tag;
    my $prefix = $self->{_namespaces}->{$namespace};
    if ($self->getOptions->{defaultns} and $prefix eq $self->getOptions->{defaultns}) {
	$tag = $propertyname;
    }
    else {
	$tag = "${prefix}:${propertyname}";
    }
    return $tag;
}
sub _descriptionOpen {
    my ($self,$description) = @_;
    my $subjectID= $description->[0]->getURI;
    my $subjectTYPE;
    eval {
	my $subjectTYPE_enum = $self->getStatements($description->[0],new RDF::Core::Resource(+RDF_NS.'type'),undef)
	    or die 'cannot find subject type (no enum)';
	my $subjectTYPE_enum_first = $subjectTYPE_enum->getFirst or die 'cannot find subject type (no first)';
	$subjectTYPE = $subjectTYPE_enum_first->getObject or die 'cannot find subject type (no object)';
    };
    #die $@.' description[0]: '.$description->[0]->getLabel if $@;
    # subjectTYPE will be, for example: http://purl.org/rss/1.0/item
    my $idAboutAttr;
    #Anonymous subject can be serialized as anonymous if it's an object of one or zero statements
    #and the referencing statement's subject has already been opened
    my $InlineURI = "_:";
    my $baseURI = $self->getOptions->{BaseURI};
    if ($subjectID =~ /^$InlineURI/i) {
	use Data::Dumper;
	my $cnt = $self->countStatements(undef,undef,$description->[0]);
	if (!$cnt || ($self->{_recursionlvl} && $cnt < 2)){
	    $idAboutAttr = '';
	} else {
	    #deanonymize resource
	    my $idNew = $self->getOptions->{InlinePrefix}.$self->{idAttr}++;
	    $idAboutAttr = " ID=\"$idNew\"";
	    carp "Giving attribute $idAboutAttr to blank node $subjectID.";
	    #store its ID to reference it in other statements
	    $self->{_anonym}->{$subjectID} = '#'.$idNew;
	}
    } elsif ($baseURI && $subjectID =~ /^$baseURI/i) {
	#relative URI - choose whether idAttr or aboutAttr should be produced
	#suggestion - produce aboutAttr every time
	#TODO-synchronize this with isuue rdfms-difference-between-ID-and-about
	my $id = 1;#$';
	$idAboutAttr = " rdf:about=\"$'\"";
    } else {
	#absolute URI - produce aboutAttr
        $subjectID =~ s/&/&amp;/g;
	$idAboutAttr = " rdf:about=\"$subjectID\"";
    }
    $self->_printindent;
    if ($subjectTYPE) {
	$self->_print('<'.$self->_tag($subjectTYPE->getNamespace,$subjectTYPE->getLocalValue).$idAboutAttr.">\n");
	$self->{'_notype'}->{$description->[0]->getURI} = 1;
    }
    else {
	$self->_print ("<rdf:Description$idAboutAttr>\n");
    }
    $self->{_recursionlvl}++;
    $description->[1] = 1;
}
sub _descriptionClose {
    my ($self,$description) = @_;
    $self->{_recursionlvl}--;
    my $subjectTYPE;
    eval {
	my $subjectTYPE_enum = $self->getStatements($description->[0],new RDF::Core::Resource(+RDF_NS.'type'),undef) or die 'cannot find subject type (no enum)';
	my $subjectTYPE_enum_first = $subjectTYPE_enum->getFirst or die 'cannot find subject type (no first)';
	$subjectTYPE = $subjectTYPE_enum_first->getObject or die 'cannot find subject type (no object)';
    };
    # subjectTYPE will be, for example: http://purl.org/rss/1.0/item
    $self->_printindent;
    if ($subjectTYPE) {
	$self->_print('</'.$self->_tag($subjectTYPE->getNamespace,$subjectTYPE->getLocalValue).">\n");
    }
    else {
	$self->_print ("</rdf:Description>\n");
    }
    $description->[2] = 1;
}
sub _predicateOpen {
    my ($self,$statement,$inline) = @_; #inline says that nested resource should be scripted inline, not referenced
    my $propName = $self->_tag($statement->getPredicate->getNamespace, $statement->getPredicate->getLocalValue);
    return if ($propName eq 'rdf:type' and $self->{'_notype'}->{$statement->getSubject->getURI});
    #return if $propName eq 'rdf:type' and $statement->getObject->getLocalValue =~ /^(channel|item)$/;
    if ($propName =~ /^rdf:_\d+$/) {
	if (my $rdfSeq = $statement->getSubject) {
	    if (my $enumerator = $self->getStatements(undef,undef,$rdfSeq)) {
		if (my $stmt = $enumerator->getFirst) {
		    if ($stmt->getPredicate->getLocalValue eq 'items') {
			$propName = 'rdf:li';
		    }
		}
	    }
	}
    }
    #$propName =~ s/^rdf:_\d+$/rdf:li/;  # convert _# to li
    my $propertyElt;
    if ($statement->getObject->isLiteral) {
	#don't express xml:lang if not necessary
	my $lang = $statement->getObject->getLang ? 
	  " xml:lang=\"".($statement->getObject->getLang)."\"" : "";
	my $datatype = $statement->getObject->getDatatype ? 
	  " rdf:datatype=\"".$statement->getObject->getDatatype."\"" : "";
	$propertyElt="<${propName}${lang}${datatype}>";
    } else {
	if ($inline) {
	    $propertyElt="<$propName>\n";
	} else {
	    my $objectURI = $statement->getObject->getURI;
	    $objectURI = $self->{_anonym}->{$objectURI}
	      if exists  $self->{_anonym}->{$objectURI};
	    push @{$self->{_resources}}, [$statement->getSubject->getURI, $objectURI];
	    $objectURI =~ s/&/&amp;/g;
	    $propertyElt="<$propName rdf:resource=\"".$self->_cutBaseURI($objectURI)."\"/>\n";
	}
    }
    $self->_printindent;
    $self->_print ($propertyElt);
}
sub _predicateClose {
    my ($self,$statement,$inline) = @_;
    my $propName = $self->_tag($statement->getPredicate->getNamespace, $statement->getPredicate->getLocalValue);
    my $propertyElt;
    if ($inline || $statement->getObject->isLiteral) {
	$propertyElt="</$propName>\n";
    } else {
	$propertyElt="";
    }
    $self->_printindent if $inline;
    $self->_print ($propertyElt);
}
sub _descriptionData {
    my ($self,$statement) = @_;
    my $RDF_NS = +RDF_NS;
    if (!$statement->getObject->isLiteral && #object is resource
	defined $self->getSubjects->{$statement->getObject->getURI} && #and statement about the resource exists
	!$self->getSubjects->{$statement->getObject->getURI}->[1] &&
	!grep($statement->getPredicate->getURI eq $_, map('http://purl.org/rss/1.0/'.$_, ('item', 'image', 'textinput'))) &&
	$statement->getPredicate->getURI !~ /^$RDF_NS(_\d+|li)$/
	) { #and is opened not yet
        $self->_predicateOpen($statement,1);
	$self->_descriptionProcess($self->getSubjects->{$statement->getObject->getURI});
	$self->_predicateClose($statement,1);
    } else {
	$self->_predicateOpen($statement,0);
	if ($statement->getObject->isLiteral) {
	    my $literal = $statement->getObject->getValue;
	    $literal =~ s/\&/\&amp;/g;
	    $literal =~ s/([^[:ascii:]])/sprintf('&#x%X;', ord($1))/ge;
	    $literal =~ s/\</\&lt;/g;
	    $literal =~ s/\>/\&gt;/g;
	    $self->_print($literal);
	}
	$self->_predicateClose($statement,0);

    }
}
sub _printindent {
  my ($self) = @_;
  $self->_print('  ' x $self->{_recursionlvl});
}
sub _print {
    my ($self,@params) = @_;
    if (ref($self->{_options}->{Output}) eq 'SCALAR') {
	${$self->getOptions->{Output}} .= join('', @params);
    } elsif (ref($self->{_options}->{Output}) =~ /^GLOB|^FileHandle/) {
	print {$self->getOptions->{Output}} @params;
    }

}
sub _outputdone {
    my ($self) = @_;
    # repack as Unicode
    if (ref($self->{_options}->{Output}) eq 'SCALAR') {
	${$self->getOptions->{Output}} = decode_utf8(${$self->getOptions->{Output}})
	    unless is_utf8(${$self->getOptions->{Output}});
    }
}
sub _cutBaseURI {
    my ($self, $uriRef) = @_;
    my $baseURI = $self->getOptions->{BaseURI};
    if ($baseURI) {
	$uriRef =~ s/^$baseURI//i;
    }
    return $uriRef;
}

1;
__END__

=head1 NAME

RDF::Core::Serializer - produce XML code for RDF model

=head1 SYNOPSIS

  require RDF::Core::Serializer;

  my %options = (getSubjects => \&getSubjectsHandler,
                 getNamespaces => \&getNamespacesHandler,
                 getStatements => \&getStatementsHandler,
                 existsStatement => \&existsStatementHandler,
                 BaseURI => 'http://www.foo.com/',
                );
  my $serializer = new RDF::Core::Serializer(%options);
  $serializer->serialize;

=head1 DESCRIPTION

Serializer takes RDF data provided by handlers and generates a XML document. Besides the trivial job of generating one description for one statement the serializer attempts to group statements with common subject into one description and makes referenced descriptions nested into referencing ones. Using baseURI option helps to keep relative resources instead of making them absolute. Blank nodes are preserved where possible, though the new rdf:nodeID attribute production is not implemented yet.

=head2 Interface

=over 4

=item * new(%options)

Available options are:

=over 4

=item * getSubjects

A reference to a subroutine that provides all distinct subjects in serialized model.

=item * getNamespaces

A reference to a subroutine that provides all predicates' namespaces.

=item * getStatements($subject, $predicate, $object)

A reference to a subroutine that provides all statements conforming given mask.

=item * existsStatement($subject, $predicate, $object)

A reference to a subroutine that returns true if a statement exists conforming the mask.

=item * Output

Output can be assigned a filehandle reference (a reference to a typeglob or FileHandle object), or a reference to a scalar variable. If a filehendle is set, serializer assumes it's open and valid, just prints there and doesn't close it. If a variable is set, XML is appended to it.
Serializer writes to STDOUT with default settings.

=item * BaseURI

A base URI of a document that is created. If a subject of a statement matches the URI, about attribute with relative URI is generated. No ID attributes are produced until corresponding RDF issue is closed. (See rdfms-difference-between-ID-and-about at http://www.w3.org/2000/03/rdf-tracking/)

=item * InlineURI

Deprecated.

=item * InlinePrefix

If an anonymous description is to be generated and need is to give it ID attribute, the attribute will be InlinePrefix concatenated with unique number. Unique is ment in the scope of the document. Default prefix is 'genid'. This is wrong practice and will be replaced by rdf:nodeID usage in next versions. Warning is generated when this occurs.

=back

=item * serialize

Does the job.

=back

=head2 Handlers

B<getSubjects> should return an array of references, each reference pointing to an array of one item ($subject), where $subject is a reference to RDF::Core::Resource. (I.e. C<$subject = $returnValue-E<gt>[$someElementOfArray]-E<gt>[0]>)

B<getNamespaces> should return a hash reference where keys are namespaces and values are namespace prefixes. There must be a rdf namespace present with value 'rdf'

B<getStatements($subject, $predicate, $object)> should return all statements that match given mask. That is the statements' subject is equal to $subject or $subject is not defined and the same for predicate and subject. Return value is a reference to RDF::Core::Enumerator object.

B<getStatements($subject, $predicate, $object)> should return number of statements that match given mask.

B<existsStatement($subject, $predicate, $object)> should return true if exists statement that matches given mask and false otherwise.

=head1 LICENSE

This package is subject to the MPL (or the GPL alternatively).

=head1 AUTHOR

Ginger Alliance, rdf@gingerall.cz

=head1 SEE ALSO

 FileHandle, RDF::Core::Model::Serializer, RDF::Core::Enumerator

=cut
