package OMP::MSB;

=head1 NAME

OMP::MSB - Class representing an OMP Science Program

=head1 SYNOPSIS

  $msb = new OMP::MSB( XML => $xml );
  $msb = new OMP::MSB( Tree => $tree, Refs => \@trees );

=head1 DESCRIPTION

This class can be used to manipulate and interrogate Minimum
Schedulable Blocks (MSB).

=cut


use 5.006;
use strict;
use warnings;
use Carp;

# External modules
use XML::LibXML; # Our standard parser
use Digest::MD5 qw/ md5_hex /;
use OMP::Error;

our $VERSION = (qw$Revision$)[1];

# Overloading
use overload '""' => "stringify";

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

The constructor takes an XML representation of the science
program as argument and returns a new object.

		$msb = new OMP::MSB( XML => $xml );

		$msb = new OMP::MSB( TREE => $tree, REFS => \%refs 
                                     PROJECTID => $proj);

The argument hash can either refer to an XML string or an
C<XML::LibXML::Element> object representing the MSB and, optionally, a
hash of C<XML::LibXML::Element> objects representing any references
referred to in the MSB.  If neither is supplied no object will be
instantiated. If both C<XML> and C<TREE> keys exist, the C<XML> key
takes priority.

The PROJECTID key can be used to inform the MSB the project with
which it is associated. This information can be added at a later 
date by using the C<projectID()> method.

If parsed, the MSB is checked for well formedness. The XML form of the
MSB is assumed to be self-contained (no external references).

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  throw OMP::Error::BadArgs('Usage : OMP::MSB->new(XML => $xml, TREE => $tree)') unless @_;

  my %args = @_;

  my ($parser, $tree);
  my $refs = {};
  if (exists $args{XML}) {
    # Now convert XML to parse tree
    XML::LibXML->validation(1);
    $parser = new XML::LibXML;
    $tree = eval { $parser->parse_string( $args{XML} ) };
    return undef if $@;
  } elsif (exists $args{TREE}) {
    $tree = $args{TREE};
    # Now get the references
    $refs = $args{REFS} if exists $args{REFS};
  } else {
    # Nothing of use
    return undef;
  }

  my $projid;
  $projid = $args{PROJECTID} if exists $args{PROJECTID};

  # Now create our Science Program hash
  my $sp = {
	    ProjectID => $projid,
	    Parser => $parser,
	    XMLRefs => $refs,
	    Tree => $tree,
	    CheckSum => undef,
	   };

  # and create the object
  bless $sp, $class;

}

=back

=head2 Accessor Methods

Instance accessor methods. Methods beginning with an underscore
are deemed to be private and do not form part of the publi interface.

=over 4

=item B<_parser>

Retrieves or sets the underlying XML parser object. This will only be
defined if the constructor was invoked with an XML string rather
than a pre-existing C<XML::LibXML::Element>.

=cut

sub _parser {
  my $self = shift;
  if (@_) { $self->{Parser} = shift; }
  return $self->{Parser};
}

=item B<projectID>

Retrieves or sets the name of the project this MSB is associated with.

  my $pid = $msb->projectID;

=cut

sub projectID {
  my $self = shift;
  if (@_) { $self->{ProjectID} = shift; }
  return $self->{ProjectID};
}

=item B<checksum>

Retrieves or sets the value to be used to uniquely identify the
MSB. This is usually an MD5 checksum determined by the C<find_checksum>
method. The checksum is stored in hexadecimal format.

  $checksum = $msb->checksum;

A C<checksum> attribute is added to the XML tree.

=cut

sub checksum {
  my $self = shift;
  if (@_) { 
    $self->{CheckSum} = shift;

    # And update the XML
    $self->_tree->setAttribute("checksum", $self->{CheckSum});

  } else {
    $self->find_checksum unless defined $self->{CheckSum};
  }
  return $self->{CheckSum};
}


=item B<_tree>

Retrieves or sets the base of the document tree associated
with the science program. In general this is DOM based. The
interface does not guarantee the underlying object type
since that relies on the choice of XML parser.

=cut

sub _tree {
  my $self = shift;
  if (@_) { $self->{Tree} = shift; }
  return $self->{Tree};
}

=item B<_xmlrefs>

Retrieves a hash containing the parse trees associated with
elements of the core science program that are referenced by
an MSB. The type of tree depends on the underlying XML parser.

  $hashref = $msb->_xmlrefs;

Returns a reference in scalar context and a hash in list context.

=cut

sub _xmlrefs {
  my $self = shift;
  if (wantarray()) {
    return %{$self->{XMLRefs}};
  } else {
    return $self->{XMLRefs};
  }
}


=item B<remaining>

Returns the number of times the MSB is to be observed.

  $remaining = $msb->remaining;

This is related to the C<remaining> attribute of an SpObs
and SpMSB element. The value can also be modified.

  $msb->remaining(5);

or decremented:

  $msb->remaining(-1);

Negative numbers are treated as a special case. When found the
value is subtracted from the current count.

The number remaining can not go below zero.

If the argument is the constant C<MSB::REMOVED>
this indicates that the MSB has not been observed but
it has been removed from consideration (generally because
another MSB has been observed in an SpOR folder).

=cut

# This is an attribute of the XML rather than this object
# but the two are synonymous, the only difference being
# that we do not store the value in our hash

sub remaining {
  my $self = shift;
  if (@_) {
    my $arg = shift;

    # Get the current value
    my $current = $self->_tree->getAttribute("remaining");


    # Decrement the counter if the argument is negative
    # unless either the current value or the new value are the 
    # MAGIC value

    if ($arg != REMOVED() and $current != REMOVED() and $arg < 0){
      $current += $arg;

      # Now Force to zero if necessary
      $current = 0 if $current < 0;

    }

    # Set the new value
    $self->_tree->setAttribute("remaining", $current);
  }

  return $self->_tree->getAttribute("remaining");
}


=back

=head2 General Methods

=over 4

=item B<find_checksum>

Calculates the MD5 checksum associated with the MSB and stores
it in the object. Usually this method is invoked automatically
the first time the C<checksum> method is invoked.

The checksum is calculated from the string form of the MSB
with the outer layer removed (ie the SpMSB or SpObs tags
are not present for the calculation). This is so that the transient
information (eg the number of times the MSB is to be observed) can
be separated from the information that uniquely identifies the MSB.

=cut

sub find_checksum {
  my $self = shift;

  # Get all the children (this is "safer" than stringifying
  # the XML and stripping off the tags and allows me to expand references).
  # I want to do this without having to know anything about XML.

  my @children = $self->_get_qualified_children;

  # Now generate a string form of the MSB
  my $string;
  for my $child (@children) {
    $string .= $child->toString;
  }

  # and generate a checksum
  my $checksum = md5_hex( $string );

  # And store it
  $self->checksum($checksum);

}

=item B<summary>

Summarize the MSB.  This is useful for providing entries in the
feedback system and summaries for the query tool.

In list context, returns the summary as a hash:

  %summary = $msb->summary();

All keys are lower-cased. The hash includes a special key.
C<summary> contains a hash with the following keys:

  string => Plain text representation suitable for a log file.
  header => Header text suitable for first line of log file.
  keys   => Array of keys, in order, used to create the text summary.

In scalar context the summary is returned in XML format:

  $string = $msb->summary();

The XML format will be something like the following:

 <SpMSBSummary id="string">
    <checksum>de252f2aeb3f8eeed59f0a2f717d39f9</checksum>
    <remaining>2</remaining>
     ...
  </SpMSBSummary>

where the elements match the key names in the hash. An C<id> key
is treated specially. When present this id is used in the SpMSBSummary
element directly.

If an optional argument is supplied this method will act like
a class method that uses the supplied hash to form a summary rather
than the object itself.

  $summary = OMP::MSB->summary( \%hash );

Warnings will be issued if fundamental keys such as "remaining",
"checksumn" and "projectid" are missing.

=cut

sub summary {
  my $self = shift;

  my %summary;
  if (@_) {
    my $summary_ref = shift;
    %summary = %$summary_ref;
  } else {

    # Populate the hash from the object if no arg
    $summary{checksum} = $self->checksum;
    $summary{remaining} = $self->remaining;
    $summary{projectid} = $self->projectID;

  }

  # Summary string
  my $head = "Project  Remainder  Checksum\n";
  my $string = "$summary{projectid}\t$summary{remaining}\t$summary{checksum}";

  $summary{summary} = {
		       keys => [qw/projectid remaining checksum/],
		       string => $string,
		       header => $head,
		      };


  if (wantarray()) {
    # Hash required
    return %summary;

  } else {
    # XML version
    my $xml = "<SpMSBSummary ";
    $xml .= "id=\"$summary{id}\"" if exists $summary{id};
    $xml .= ">\n";

    for my $key (keys %summary) {
      # Special case the summary and ID keys
      next if $key eq "summary";
      next if $key eq "id";

      $xml .= "<$key>$summary{$key}</$key>\n";

    }
    $xml .= "</SpMSBSummary>\n";

    return $xml;

  }

}

=item B<hasBeenObserved>

Indicate that this MSB has been observed. This involves decrementing
the C<remaining()> counter by 1 and, if this is part of an SpOR block
and the parent tree is accessible, adjusting the logic.

It is usually combined with an update of the database contents to reflect
the modified state.

If the MSB is within an SpOR the following occurs in addition to
decrementing the remaining counter:

 - Move the MSB (and enclosing SpAND) out of the SpOR into the
   main tree

 - Decrement the counter on the SpOR.

 - Since MSBs are currently located in a science programby name
   without checking for SpOR counter, if the SpOR counter hits zero all
   remaining MSBs are marked with the magic value for remaining() to
   indicate they have been removed by the OMP rather than by
   observation.

This all requires that there are no non-MSB elements in an SpOR
since inheritance breaks if we move just the MSB (that is only
true if the OT ignores IDREF attributes).

=cut

sub hasBeenObserved {
  my $self = shift;

  # This is the easy bit
  $self->remaining( -1 );

  # Now for the hard part... SpOr/SpAND

  # First have to find out if I have a parent that is an SpOR
  my ($SpOR) = $self->_tree->findnodes('ancestor-or-self::SpOR');

  if ($SpOR) {

    # Okay - we are in a logic nightmare

    # First see if we are in an SpAND
    my ($SpAND) = $self->_tree->findnodes('ancestor-or-self::SpAND');

    # Now we need to move the MSB or the enclosing SpAND to
    # just after the SpOR

    # Decide what we are moving
    my $node = ( $SpAND ? $SpAND : $self->_tree );

    # Now find the parent of the SpOR since we have to insert in
    # the parent relative to the SpOR
    my $ORparent = $SpOR->parentNode;

    # Unbind the node we are moving from its parent
    $node->unbindNode;

    # Move it
    $ORparent->insertAfter($node, $SpOR );

    # Now decrement the counter on the SpOR
    my $n = $SpOR->getAttribute("numberOfItems");
    $n--;
    $n = 0 if $n < 0;
    $SpOR->setAttribute("numberOfItems", $n);

    # If the number of remaining items is 0 we need to go
    # and find all the MSBs that are left and fix up their
    # "remaining" attributes so that they will no longer be accepted
    # This code is identical to that in OMP::SciProg so we should
    # be doing this in a cleverer way.
    # For now KLUGE KLUGE KLUGE
    if ($n == 0) {
      print "Attempting to REMOVE remaining MSBs\n";
      my @msbs = $SpOR->findnodes(".//SpMSB");
      print "Located SpMSB...\n";
      push(@msbs, $SpOR->findnodes('.//SpObs[@msb="true"]'));
      print "Located SpObs...\n";

      for (@msbs) {
	# Eek this should be happening on little OMP::MSB objects
	$_->setAttribute("remaining",REMOVED());
      }
    }

  }

}


=item B<stringify>

Convert the MSB object into XML.

  $xml = $msb->stringify;

This method is also invoked via a stringification overload.

  print "$sp";

The XML is fully expanded in the sense that references (IDREFs)
are resolved and included.

=cut

sub stringify {
  my $self = shift;
  $self->_tree->toString;
}


=item B<_get_qualified_children>

Retrieve the parse trees that represent the component
elements of the MSB. This includes resolved references (any 
element that looks like <SpXXXRef idref="blah"> is replaced
with the corresponding <SpXXX id="blah">).

  @children = $msb->_get_qualified_children;

=cut

sub _get_qualified_children {
  my $self = shift;

  # First get the children
  my @children = $self->_tree->findnodes('child::*');

  # Now go through the array replacing refs if required
  for my $child (@children) {

    # Check to see if this has an idref attr
    if ($child->hasAttribute("idref")) {
      my $ref = $child->getAttribute("idref");
      # We have to make sure that we have the key
      if (exists $self->_xmlrefs->{$ref}) {
	# ...and do the replacement if we need to
	# using the implicit aliasing of the loop variable
	$child = $self->_xmlrefs->{$ref};
      } else {
	carp "There is a reference to an element that does not exist\n";
      }
    }


  }

  return @children;

}


=back

=head1 CONSTANTS

The following constants are available from this class:

=over 4

=item B<MSB::REMOVED>

The magic value indicating to C<remaining()> that the MSB
should be removed from further consideration even though it
has not been observed.

=cut

use constant REMOVED => -999;

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;

