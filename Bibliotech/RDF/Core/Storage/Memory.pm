package Bibliotech::RDF::Core::Storage::Memory;
use base 'RDF::Core::Storage::Memory';

# this entire file works around a bug in the original that mixes up
# Resource's and Literal's that are identical URI's (we use a Literal
# for dc:title in rss feeds sometimes)

sub existsStmt {
    my ($self, $subject, $predicate, $object) = @_;

    my $indexArray = $self->_getIndexArray($subject, $predicate, $object);
    foreach (@$indexArray) {
        if ((!defined $subject || $self->{_data}->{$_}->getSubject->getURI eq $subject->getURI) &&
           (!defined $predicate || $self->{_data}->{$_}->getPredicate->getURI eq $predicate->getURI) &&
           (!defined $object || (
                        $object->isLiteral && $self->{_data}->{$_}->getObject->isLiteral
                                ? ($object->equals($self->{_data}->{$_}->getObject))
                                : $self->{_data}->{$_}->getObject->getLabel eq $object->getLabel
                ))) {
            return 1; #found statement                                                                                        
        }
    }
    return 0; #didn't find statement                                                                                          
}

sub getStmts {
    my ($self, $subject, $predicate, $object) = @_;
    my @data ;

    my @indexArray = @{$self->_getIndexArray($subject, $predicate, $object)};
    foreach (@indexArray) {
        if ((!defined $subject || $self->{_data}->{$_}->getSubject->getURI eq $subject->getURI) &&
            (!defined $predicate || $self->{_data}->{$_}->getPredicate->getURI eq $predicate->getURI) &&
            (!defined $object || (
                        $object->isLiteral && $self->{_data}->{$_}->getObject->isLiteral
                                ? ($object->equals($self->{_data}->{$_}->getObject))
                                : $self->{_data}->{$_}->getObject->getLabel eq $object->getLabel
                ))) {
            push(@data,$self->{_data}->{$_});
        }
    }
    return RDF::Core::Enumerator::Memory->new(\@data) ;

}

sub countStmts {
    my ($self, $subject, $predicate, $object) = @_;

    my $count = 0;
    return $count = keys %{$self->{_data}}
      unless defined $subject || defined $predicate || defined $object;
    my @indexArray = @{$self->_getIndexArray($subject, $predicate, $object)};
    foreach (@indexArray) {
        if ((!defined $subject || $self->{_data}->{$_}->getSubject->getURI eq $subject->getURI) &&
            (!defined $predicate || $self->{_data}->{$_}->getPredicate->getURI eq $predicate->getURI) &&
            (!defined $object || (
                        $object->isLiteral && $self->{_data}->{$_}->getObject->isLiteral
                                ? ($object->equals($self->{_data}->{$_}->getObject))
                                : $self->{_data}->{$_}->getObject->getLabel eq $object->getLabel
                ))) {
            $count++;
        }
    }
    return $count;

}

sub _getKey {
    #Same as existsStmt, but returns key of statement and doesn't handle undef elements (takes $stmt as a parameter)          
    my ($self, $stmt) = @_;

    my @indexArray = @{$self->_getIndexArray($stmt->getSubject, $stmt->getPredicate, $stmt->getObject)};
    foreach (@indexArray) {
        if ($self->{_data}->{$_}->getSubject->getURI eq $stmt->getSubject->getURI &&
            $self->{_data}->{$_}->getPredicate->getURI eq $stmt->getPredicate->getURI &&
            ($self->{_data}->{$_}->getObject->isLiteral && $stmt->getObject->isLiteral
                                ? ($stmt->getObject->equals($self->{_data}->{$_}->getObject))
                                : $self->{_data}->{$_}->getObject->getLabel eq $stmt->getObject->getLabel)) {
            return $_;          #found statement                                                                              
        }
    }
    return 0;                   #didn't find statement                                                                        
}

1;
__END__
