package OMP::MSBDoneDB;

=head1 NAME

OMP::MSBDoneDB - Manipulate MSB Done table

=head1 SYNOPSIS

  use OMP::MSBDoneDB;

  $db = new OMP::MSBDoneDB( ProjectID => 'm01bu05',
                            DB => new OMP::DBbackend);

  $xml = OMP::MSBServer->historyMSB( $checksum, 'xml');
  $db->addMSBcomment( $checksum, $comment );


=head1 DESCRIPTION

The MSB "done" table exists to allow us to associate user supplied
comments with MSBs that have been observed. It does this by having a
simple logging table where a new row is added each time an MSB is
observed or commented upon.

The existence of this table allows comments for an MSB to be
associated directly with data stored in the data archive (where the
MSB checksum will be stored in the FITS headers). There is no direct
link with the OMP MSB table. This can be thought of as a specialised
MSB Feedback table.

As each MSB comment comes in it is simply added to the table and a
status flag of previous entries is updated (set to false). One wrinkle
is that there is no guarantee that an MSB will still be in the MSB
table (science program) when the trigger to mark the MSB as done is
received (a new science program may have been submitted in the
interim). To overcome this problem a row is added to the table each
time an MSB is retrieved from the system using C<fetchMSB>- this
guarantees that the MSB summary information is available to us since
we simply read the table prior to submitting a new row.

=cut

use 5.006;
use warnings;
use strict;

use Carp;
use OMP::Constants qw/ :done /;
use OMP::Info::MSB;
use OMP::Info::Comment;
use Time::Piece;

use base qw/ OMP::BaseDB /;

our $VERSION = (qw$Revision$)[1];
our $MSBDONETABLE = "ompmsbdone";

=head1 METHODS

=head2 Public Methods

=over 4

=item B<historyMSB>

Retrieve the observation history for the specified MSB (identified
by checksum and project ID) or project.

  $msbinfo = $db->historyMSB( $checksum );
  $arrref  = $db->historyMSB();

The information is retrieved as an C<OMP::Info::MSB> object
(with a checksum supplied) or an array of those objects.

If the checksum is not supplied a full project observation history is
returned (this is simply an array of MSB information objects).

=cut

sub historyMSB {
  my $self = shift;
  my $checksum = shift;

  # Construct the query
  my $projectid = $self->projectid;

  my $xml = "<MSBDoneQuery>" .
    ( $checksum ? "<checksum>$checksum</checksum>" : "" ) .
      ( $projectid ? "<projectid>$projectid</projectid>" : "" ) .
	  "</MSBDoneQuery>";

  my $query = new OMP::MSBDoneQuery( XML => $xml );

  # Assume we have already got all the information
  # so we do not need to do a subsequent query
  return $self->queryMSBdone( $query );

}

=item B<addMSBcomment>

Add a comment to the specified MSB.

 $db->addMSBcomment( $checksum, $comment );

If the MSB has not yet been observed this command will fail.

Optionally, an object of class C<OMP::MSB> can be supplied as the
third argument. This can be used to extract summary information if the
MSB is not currently in the table. The supplied checksum must match
that of the C<OMP::MSB> object (unless the checksum is not defined).

Additionally, a fourth argument can be supplied specifying the status
of the comment. Default is to treat it as OMP__DONE_COMMENT. See 
C<OMP::Constants> for more information on the different comment
status.

 $db->addMSBcomment( $checksum, $comment, undef, OMP__DONE_FETCH );

=cut

sub addMSBcomment {
  my $self = shift;
  my $checksum = shift;
  my $comment = shift;
  my $msb = shift;
  my $status = shift;
  my $skiptrans = shift;

  # Lock the database (since we are writing)
  $self->_db_begin_trans;
  $self->_dblock;

  $self->_store_msb_done_comment( $checksum, $self->projectid, $msb,
				$comment, $status );

  # End transaction
  $self->_dbunlock;
  $self->_db_commit_trans;

}

=item B<observedMSBs>

Return all the MSBs observed (ie "marked as done") on the specified
date. If a project ID has been set only those MSBs observed on the
date for the specified project will be returned.

  $output = $db->observedMSBs( $date, $allcomments );

The C<allcomments> parameter governs whether all the comments
associated with the observed MSBs are returned (regardless of when
they were added) or only those added for the specified night. If the
value is false only the comments for the night are returned.

If no date is defined the current UT date is used.

=cut

sub observedMSBs {
  my $self = shift;
  my $date = shift;
  my $allcomment = shift;
  my $style = shift;

  # Construct the query
  $date ||= OMP::General->today;
  my $projectid = $self->projectid;

  my $xml = "<MSBDoneQuery>" .
    "<status>". OMP__DONE_DONE ."</status>" .
      "<date delta=\"1\">$date</date>" .
	( $projectid ? "<projectid>$projectid</projectid>" : "" ) .
	    "</MSBDoneQuery>";

  my $query = new OMP::MSBDoneQuery( XML => $xml );

  return $self->queryMSBdone( $query, $allcomment );
}


=item B<queryMSBdone>

Query the MSB done table. Query must be supplied as an
C<OMP::MSBDoneQuery> object.

  @results = $db->queryMSBdone( $query, $allcomments );

The C<allcomments> parameter governs whether all the comments
associated with the observed MSBs are returned (regardless of when
they were added) or only those matching the specific query. If the
value is false only the comments matched by the query are returned.

The output format matches that returned by C<historyMSB>.

=cut

sub queryMSBdone {
  my $self = shift;
  my $query = shift;
  my $allcomment = shift;

  # First read the rows from the database table
  # and get the array ref
  my @rows = $self->_fetch_msb_done_info( $query );

  # Now reorganize the data structure to better match
  # our output format
  my $msbs = $self->_reorganize_msb_done( \@rows );

  # If all the comments are required then we now need
  # to loop through this hash and refetch the data
  # using a different query. 
  # The query should tell us whether this is required.
  # Note that there is a possibility of infinite looping
  # since historyMSB calls this routine
  if ($allcomment) {
    foreach my $checksum (keys %$msbs) {
      # over write the previous entry
      $msbs->{$checksum} = $self->historyMSB($checksum,  'data');
    }
  }

  # Now reformat the data structure to the required output
  # format. Pass in the query object so that this routine
  # can determine whether we are only asking for a checksum.
  return $self->_format_output_info( $msbs, $query, $style);

}


=back

=head2 Internal Methods

=over 4

=item B<_fetch_msb_done_info>

Retrieve the information from the MSB done table using the supplied
query.  Can retrieve the most recent information or all information
associated with the MSB.

  @allmsbinfo = $db->_fetch_msb_done_info( $query );

In scalar context returns the first match via a reference to a hash.

  $msbinfo = $db->_fetch_msb_done_info( $query );


=cut

# This should probably be done using a DBQuery class

sub _fetch_msb_done_info {
  my $self = shift;
  my $query = shift;

  # Generate the SQL
  my $sql = $query->sql( $MSBDONETABLE );

  # Run the query
  my $ref = $self->_db_retrieve_data_ashash( $sql );

#  use Data::Dumper;
#  print Dumper( $ref );
#  print "\nFrom $sql\n";
#  exit;

  # If they want all the info just return the ref
  # else return the first entry
  if ($ref) {
    if (wantarray) {
      return @$ref;
    } else {
      my $hashref = (defined $ref->[0] ? $ref->[0] : {});
      return %{ $hashref };
    }
  } else {
    return (wantarray ? () : {} );
  }

}

=item B<_add_msb_done_info>

Add the supplied information to the MSB done table and mark all previous
entries as old (status = false).

 $db->_add_msb_done_info( %msbinfo );

where the relevant keys in C<%msbinfo> are:

  checksum - the MSB checksum
  projectid - the project associated with the MSB
  comment   - a comment associated with this action
  instrument,target,waveband - msb summary information

The datestamp is added automatically.

All entries with status OMP__DONE_FETCH and the same
checksum are removed prior to uploading this information. This
is because the FETCH information is really just a placeholder
to guarantee that the information is available and is not
the main purpose of the table.

=cut

sub _add_msb_done_info {
  my $self = shift;
  my %msbinfo = @_;

  # Get the projectid
  $msbinfo{projectid} = $self->projectid
    if (!exists $msbinfo{projectid} and defined $msbinfo{projectid});

  throw OMP::Error::BadArgs("No projectid supplied for add_msb_done_info")
    unless exists $msbinfo{projectid};

  # Must force upcase of project ID for now
  $msbinfo{projectid} = uc( $msbinfo{projectid} );

  # First remove any placeholder observations
  $self->_db_delete_data( $MSBDONETABLE,
			  " checksum = '$msbinfo{checksum}' AND " .
			  " projectid = '$msbinfo{projectid}' AND " .
			  " status = " . OMP__DONE_FETCH
			);

  # Now insert the information into the table

  # First get the timestamp
  my $t = gmtime;
  my $date = $t->strftime("%b %e %Y %T");

  # insert rows into table
  $self->_db_insert_data( $MSBDONETABLE,
			  $msbinfo{checksum}, $msbinfo{status}, 
			  $msbinfo{projectid}, "$date", # Force stringify
			  $msbinfo{target}, $msbinfo{instrument}, 
			  $msbinfo{waveband},
			  {
			   TEXT => $msbinfo{comment},
			   COLUMN => 'comment',
			  }
			);

}

=item B<_store_msb_done_comment>

Given a checksum, project ID, (optional) MSB object and a comment,
update the MSB done table to contain this information.

If the MSB object is defined the table information will be retrieved
from the object. If it is not defined the information will be
retrieved from the done table (we cannot read it from the MSB table
because that would involve reading the msb and obs table in order to
reconstruct the target and instrument info). An exception is triggered
if the information for the table is not available (this is the reason
why the checksum and project ID are supplied even though, in
principal, this information could be obtained from the MSB object).

  $db->_store_msb_done_comment( $checksum, $proj, $msb, $text );

An optional fifth argument can be used to specify the status of the
message. Default is for the message to be treated as a comment.
This allows you to specify that the comment is associated with
an MSB fetch or a "msb done" action. The OMP__DONE_FETCH is
treated as a special case. If that status is used a row is added
to the table only if no previous information exists for that MSB.
(this prevents lots of entries associated with repeat fetches
but no action).

=cut

sub _store_msb_done_comment {
  my $self = shift;
  my ($checksum, $project, $msb, $comment, $status ) = @_;

  # default to a normal comment
  $status = ( defined $status ? $status : OMP__DONE_COMMENT );

  # check first before writing if required
  # I realise this leads to the possibility of two fetches from
  # the database....
  # If status is OMP__DONE_FETCH then we only want one entry
  # ever so only write it if nothing previously exists
  return if $status == OMP__DONE_FETCH and $self->_fetch_msb_done_info(
								       checksum => $checksum,
								       projectid => $project,
								      );

  # If the MSB is defined we do not need to read from the database
  my %msbinfo;
  if (defined $msb) {

    %msbinfo = $msb->summary;
    $msbinfo{target} = $msbinfo{_obssum}{target};
    $msbinfo{instrument} = $msbinfo{_obssum}{instrument};
    $msbinfo{waveband} = $msbinfo{_obssum}{waveband};

    $checksum = $msb->checksum unless defined $checksum;

    # Compare checksums
    throw OMP::Error::FatalError("Checksum mismatch!")
      if $checksum ne $msb->checksum;

  } else {
    %msbinfo = $self->_fetch_msb_done_info(
					   checksum => $checksum,
					   projectid => $project,
					  );

  }

  # throw an exception if we dont have anything yet
  throw OMP::Error::MSBMissing("Unable to associate any information with the checksum $checksum in project $project") 
    unless %msbinfo;

  # provide a status
  $msbinfo{status} = $status;

  # Add the comment into the mix
  $msbinfo{comment} = ( defined $comment ? $comment : '' );

  # Add this information to the table
  $self->_add_msb_done_info( %msbinfo );


}

=item B<_organize_msb_done>

Given the results from the query (returned as a row per comment)
convert this output to a hash containing one entry per MSB.

  $hashref = $db->_reorganize_msb_done( $query_output );

The resultant data structure is a hash (keyed by checksum)
each pointing to a hash with keys:

  checksum - the MSB checksum (a repeat of the key)
  projectid - the MSB project id
  target
  waveband
  instrument
  comment

C<comment> is a reference to an array containing a reference to a hash
for each comment associated with the MSB. The hash contains the
comment itself (C<text>), the C<date> and the C<status> associated
with that comment.

=cut

sub _reorganize_msb_done {
  my $self = shift;
  my $rows = shift;

  # Now need to go through all the rows forming the
  # data structure (need to organize the data structure
  # before forming the (optional) xml output)
  my %msbs;
  for my $row (@$rows) {

    # see if we've met this msb already
    if (exists $msbs{ $row->{checksum} } ) {

      # Add the new comment
      push(@{ $msbs{ $row->{checksum} }->{comment} }, {
						       text => $row->{comment},
						       date => $row->{date},
						       status => $row->{status},
						      });


    } else {
      # populate a new entry
      $msbs{ $row->{checksum} } = {
				   checksum => $row->{checksum},
				   target => $row->{target},
				   waveband => $row->{waveband},
				   instrument => $row->{instrument},
				   projectid => $row->{projectid},
				   comment => [
					       {
						text => $row->{comment},
						date => $row->{date},
						status => $row->{status},
					       }
					      ],
				  };
    }


  }

  return \%msbs;

}


=item B<_format_output_info>

Format the data structure generated by C<_reorganize_msb_done>
to the format required by the particular user. Options are
"data" (return the data structure with minimal modification) and
"xml" (return an XML string representing the data structure).

  $output = $db->_format_output_info( $hashref, $checksum, $style);

The checksum is provided in case a subset of the data structure
is required. The style governs the output format.

=cut

sub _format_output_info {
  my $self = shift;
  my %msbs = %{ shift() };
  my $query = shift;
  my $style = shift;

  my $checksum = ( scalar($query->checksums()) ? ($query->checksums)[0] : undef );

  # Now form the XML if required
  if ( defined $style && $style eq 'xml' ) {

    # Wrapper element
    my $xml = "<msbHistories>\n";

    # loop through each MSB
    for my $msb (keys %msbs) {

      # If an explicit msb has been mentioned we only want to
      # include that MSB
      if ($checksum) {
	next unless $msb eq $checksum;
      }

      # Start writing the wrapper element
      $xml .= " <msbHistory checksum=\"$msb\" projectid=\"" . $msbs{$msb}->{projectid} 
	. "\">\n";

      # normal keys
      foreach my $key (qw/ instrument waveband target /) {
	$xml .= "  <$key>" . $msbs{$msb}->{$key} . "</$key>\n";
      }

      # Comments
      for my $comment ( @{ $msbs{$msb}->{comment} } ) {
	$xml .= "  <comment>\n";
	for my $key ( qw/ text date status / ) {
	  $xml .= "    <$key>" . $comment->{$key} . "</$key>\n";
	}
	$xml .= "  </comment>\n";
      }

      $xml .= " </msbHistory>\n";

    }

    $xml .= "</msbHistories>\n";

    return $xml;

  } else {
    # The data structure returned is actually an array  when checksum
    # was not defined or a hash ref if it was

    if ($checksum) {

      return $msbs{$checksum};

    } else {

      my @all = map { $msbs{$_} }
	sort { $msbs{$a}{projectid} cmp $msbs{$b}{projectid} } keys %msbs;

      return \@all;


    }

  }
}

=back

=head1 SEE ALSO

This class inherits from C<OMP::BaseDB>.

For related classes see C<OMP::ProjDB> and C<OMP::FeedbackDB>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
