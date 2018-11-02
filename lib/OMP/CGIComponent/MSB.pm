package OMP::CGIComponent::MSB;

=head1 NAME

OMP::CGIComponent::MSB - Web display of MSB information

=head1 SYNOPSIS

  use OMP::CGIComponent::MSB;

=head1 DESCRIPTION

Helper methods for generating and displaying portions of web
pages that display MSB comments and general MSB information.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Time::Seconds qw(ONE_HOUR);
use CGI qw/ :html *Tr *td /;

use OMP::CGIComponent::Helper;
use OMP::CGIDBHelper;
use OMP::Constants qw(:done);
use OMP::DBServer;
use OMP::Display;
use OMP::Error qw(:try);
use OMP::DateTools;
use OMP::General;
use OMP::Info::Comment;
use OMP::MSBDB;
use OMP::MSBDoneDB;
use OMP::MSBServer;
use OMP::ProjDB;
use OMP::ProjServer;
use OMP::SpServer;
use OMP::UserServer;

$| = 1;

=head1 Routines

=over 4

=item B<fb_msb_active>

Create a table of active MSBs for a given project

  fb_msb_active($cgi, $projectid);

=cut

sub fb_msb_active {
  my $q = shift;
  my ( $projectid, $password ) = @_;

  # Get project's associated telescope
  my $proj = OMP::ProjServer->projectDetailsNoAuth( $projectid,
                                              "object");

  my $active = OMP::CGIDBHelper::safeProgramDetails( $projectid, $password, 'objects' );

  if (defined $active) {

    # First go through the array quickly to make sure we have
    # some valid entries
    my @remaining = grep { $_->remaining > 0 } @$active;
    my $total = @$active;
    my $left = @remaining;
    my $done = $total - $left;
    if ($left == 0) {
      if ($total == 1) {
        print "The MSB present in the science program has been observed.<br>\n";
      } else {
        print "All $total MSBs in the science program have been observed.<br>\n";
      }

    } else {

      # Nice little message letting us know no of msbs present in the table
      # that have not been observed.
      if ($done > 0) {
        if ($done == 1) {
          print "$done out of $total MSBs present in the science program has been observed.<br>\n";
        } else {
          print "$done out of $total MSBs present in the science program have been observed.<br>\n";
        }
      }

      # Now print the table (with an est. time column) if we have content
      msb_table(cgi=>$q, msbs=>$active, est_column=>1, opacity_column=>1, telescope=>$proj->telescope,);

    }
  }
}

=item B<fb_msb_observed>

Create a table of observed MSBs for a given project

  fb_msb_observed($cgi, $projectid);

=cut

sub fb_msb_observed {
  my $q = shift;
  my $projectid = shift;

  # Get observed MSBs
  my $observed = OMP::MSBServer->observedMSBs({projectid => $projectid,
                                               format => 'data'});

  # Get project's associated telescope
  my $proj = OMP::ProjServer->projectDetailsNoAuth( $projectid,
                                              "object");

  # Generate the HTML table
  (@$observed) and msb_table(cgi=>$q, msbs=>$observed, telescope=> $proj->telescope);
}

my ( $NBSP ) = ( '&nbsp;' );

=item B<msb_action>

Working in conjunction with the B<msb_comments> function described elsewhere
in this document this function decides if the form generated by B<msb_comments>
was submitted, and if so, what action to take.

  msb_action($q);

Takes a C<CGI> query object as the only argument.

=cut

sub msb_action {
  my $q = shift;

  if ($q->param("submit_msb_comment")) {
    # Submit a comment
    try {

      # Get the user object
      my $user = OMP::UserServer->getUser($q->param('author'));

      # Make sure we got a user object
      if (! $user) {
        print "Must supply a valid OMP user ID in order to submit a comment";

        # Redisplay the comment form and return
        msb_comment_form($q, 1);
        return;
      }

      # Create the comment object
      my $trans = $q->param( 'transaction' );
      my $comment = new OMP::Info::Comment( author => $user,
                                            text => $q->param('comment'),
                                            status => OMP__DONE_COMMENT,
                                            ( $trans ? ( 'tid' => $trans )
                                              : ()
                                            )
                                          );

      # Add the comment
      OMP::MSBServer->addMSBcomment( $q->param('projectid'),
                                     $q->param('msbid'),
                                     $comment );
      print $q->h2("MSB comment successfully submitted");
    } catch OMP::Error::MSBMissing with {
      my $Error = shift;
      print "MSB not found in database:<p>$Error";
    } otherwise {
      my $Error = shift;
      print "An error occurred preventing the comment submission:<p>$Error";
    };

  } elsif ($q->param("Remove")) {
    # Mark msb as 'all done'
    try {
      OMP::MSBServer->alldoneMSB( $q->param('projectid'), $q->param('checksum') );
      print $q->h2("MSB removed from consideration");
    } catch OMP::Error::MSBMissing with {
      my $Error = shift;
      print "MSB not found in database:<p>$Error";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to mark the MSB as Done:<p>$Error";
    };

  } elsif ($q->param("Undo") || $q->param("unRemove")) {
    # Unmark msb as 'done' or unremove a removed MSB
    try {
      OMP::MSBServer->undoMSB( $q->param('projectid'), $q->param('checksum') );
      if ($q->param("Undo")) {
        print $q->h2("MSB done mark removed");
      } else {
        print $q->h2("MSB no longer removed from consideration");
      }

    } catch OMP::Error::MSBMissing with {
      my $Error = shift;
      print "MSB not found in database:<p>$Error";
    } otherwise {
      my $Error = shift;
      print "An error occurred while attempting to remove the MSB Done mark:<p>$Error";
    };
  }
}

=item B<msb_comments>

Creates an HTML table of MSB comments.

  msb_comments($cgi, $msbcomments, $sp);

Takes a reference to an array of C<OMP::Info::MSB> objects as the second argument.
Last argument is an optional Sp object.

=cut

sub msb_comments {
  my $q = shift;
  my $commentref = shift;
  my $sp = shift;

  my @output;
  if ($q->param('show') =~ /observed/) {
    @output = grep {$_->comments->[0]->status != OMP__DONE_FETCH} @$commentref;
  } elsif ($q->param('show') =~ /current/) {
    @output = grep {$sp->existsMSB($_->checksum)} @$commentref if defined $sp;
  } else {
    @output = @$commentref;
  }

  print <<'TABLE';
<table class="infobox" width="100%" cellspacing="0"
  border="0"
  cellpadding="3"
  >
TABLE

  # Colors associated with statuses
  my %colors = (&OMP__DONE_FETCH => '#c9d5ea',
                &OMP__DONE_DONE => '#c6bee0',
                &OMP__DONE_ALLDONE => '#8075a5',
                &OMP__DONE_COMMENT => '#9f93c9',
                &OMP__DONE_UNDONE => '#ffd8a3',
                &OMP__DONE_ABORTED => '#9573a0',
                &OMP__DONE_REJECTED => '#bc5a74',
                &OMP__DONE_SUSPENDED => '#ffb959',);

  my ( $table_cols, $header_rows, $i ) = ( 4, 2, 1 );

  # For CGI+form.
  my %common_hidden =
    ( 'show_output' => 1,
    );

  foreach my $msb (@output) {

    # If the MSB exists in the science program we'll provide a "Remove" button
    # and we'll be able to display the number of remaining observations.
    my $exists = $sp && $sp->existsMSB($msb->checksum) ;

    # this will be the actual science program MSB if it exists
    # We need this so that we can provide the correct button types
    my $spmsb;

    my $remstatus = '';
    if ($exists) {
      $spmsb = $sp->fetchMSB( $msb->checksum );
      my $remaining = $spmsb->remaining;
      if ($spmsb->isRemoved) {
        $remstatus = "REMOVED";
      } elsif ($remaining == 0) {
        $remstatus = "COMPLETE";
      } else {
        $remstatus = "Remaining: $remaining";
      }
    }

    # Get the MSB title
    my $msbtitle = $msb->title;
    (!$msbtitle) and $msbtitle = "[NONE]";

    my @comments = $msb->comments;
    my $comments = _count_unique_tids( @comments );

    _print_msb_header(
      'count' => $i,
      # (2 * $comments -1): number of comments & dividers between two comments.
      'count-rowspan' => $header_rows + ( $comments ? 2 * $comments - 1 : 0 ),
      'title' => $msbtitle,
      # Count goes in the 1st column.
      'title-colspan' => $table_cols - 1,
      'status' => $remstatus,
      'target' => $msb->target,
      'inst' => $msb->instrument,
      'waveband' => $msb->waveband,
    );
    $i++;

    $common_hidden{'projectid'} = $msb->projectid;
    $common_hidden{'checksum'} = $msb->checksum;

    _print_transaction_comments(
      $q,
      { 'comments' => [ @comments ],
        'comment-colspan' => $table_cols - 2,
        'colors' => \%colors,
        'hidden' =>
          [ OMP::Display->make_hidden_fields(
              $q, \%common_hidden,
            )
          ],
      }
    ) ;

    # Make "Remove" and "undo" buttons if the MSB exists in the
    # science program
    if ( $exists ) {

      print
        Tr( td( $NBSP ),
            td( { 'colspan' => , $table_cols - 1 },
              $q->startform,
              # If it has been removed, the only relevant action is to unremove it
              ( $spmsb->isRemoved ? $q->submit('unRemove')
                  : $q->submit('Remove'), $NBSP, $q->submit('Undo')
              ),
              OMP::Display->make_hidden_fields( $q, { %common_hidden } ),
              _make_non_empty_hidden_fields( $q, qw[utdate telescope] ),
              $q->endform
            )
          ) ;
    }

    print
      Tr( { 'bgcolor' => "#d3d3dd" },
          qq[<td colspan="$table_cols"> $NBSP</td>]
        );
  }
  print "</table>";
}

=item B<msb_comments_by_project>

Show MSB comments sorted by project

  msb_comments_by_project($cgi, $msbcomments);

Takes a reference to a data structure containing MSBs and their comments sorted by project.

=cut

sub msb_comments_by_project {
  my $q = shift;
  my $comments = shift;
  my %sorted;

  # Get the Private and Public cgi-bin URLs
  my $public_url = public_url();
  my $private_url = private_url();

  foreach my $msb (@$comments) {
    my $projectid = $msb->projectid;
    $sorted{$projectid} = [] unless exists $sorted{$projectid};
    push(@{ $sorted{$projectid} }, $msb);
  }

  foreach my $projectid (keys %sorted) {
    print $q->h2("Project: <a href='$public_url/projecthome.pl?urlprojid=$projectid'>$projectid</a>");
    msb_comments($q, \@{$sorted{$projectid}});
    print $q->hr;
  }
}

=item B<msb_comment_form>

Create a form for submitting an MSB comment.  If any of the values the form
takes are available in the query param list they can be used as defaults.

  msb_comment_form($cgi, 1);

The first argument is a C<CGI> query object.  If the second argument is true
any available params are used as defaults.

=cut

sub msb_comment_form {
  my $q = shift;
  my $defaults = shift;

  my %defaults;
  if ($defaults) {
    # Use query param values as defaults
    %defaults = map {$_, $q->param($_)} qw/author comment msbid/;
  } else {
    %defaults = (author => undef,
                 comment => undef,
                 msbid =>$q->param('checksum'),)
  }

  print "<table border=0><tr><td valign=top>User ID: </td><td>";
  print $q->startform;
  print $q->textfield(-name=>'author',
                      -size=>22,
                      -maxlength=>32,
                      -default=>$defaults{author},);
  print "</td><tr><td valign=top>Comment: </td><td>";

  print
    OMP::Display->make_hidden_fields(
      $q,
      { 'show_output' => 1,
        'submit_msb_comment' => 1,
        # This is checksum not transaction id.
        'msbid' => $defaults{'msbid'},
        'transaction' => $q->param( 'transaction' )
      }
    ),
    _make_non_empty_hidden_fields( $q, qw[ projectid utdate telescope ]) ;

  print $q->textarea(-name=>'comment',
                     -rows=>5,
                     -columns=>80,
                     -default=>$defaults{comment},);
  print "</td><tr><td colspan=2 align=right>";
  print $q->submit("Submit");
  print $q->endform;
  print "</td></table>";
}

=item B<msb_sum>

Displays the project details (lists all MSBs)

  msb_sum($cgi, %cookie);

=cut

sub msb_sum {
  my $q = shift;
  my %cookie = @_;

  print $q->h2("MSB summary");
  my $msbsum = OMP::CGIDBHelper::safeProgramDetails( $cookie{projectid},
                                                     $cookie{password},
                                                     'htmlcgi' );
  print $msbsum if defined $msbsum;

}

=item B<msb_sum_hidden>

Creates text showing current number of msbs, but not actually display the
program details.

  msb_sum_hidden($cgi, %cookie);

=cut

sub msb_sum_hidden {
  my $q = shift;
  my %cookie = @_;

  my $sp;
  my @msbs;
  my $projectid = $cookie{projectid};
  try {
    my $db = OMP::MSBDB->new(DB=>new OMP::DBbackend,
                             ProjectID => $projectid,
                             Password => $cookie{password},);

    # Our XML query for retrieving all MSBs
    my $xml = "<MSBQuery>"
      ."<projectid full=\"1\">$projectid</projectid>"
        ."<disableconstraint>all</disableconstraint>"
          ."</MSBQuery>";

    my $query = new OMP::MSBQuery( XML => $xml );

    # Run the query
    @msbs = $db->queryMSB($query);

  } catch OMP::Error::UnknownProject with {
    print "Science program for $projectid not present in database";
  } otherwise {
    my $E = shift;
    print "Error obtaining science program details for project $projectid [$E]";
  };


  print $q->h2("Current MSB status");
  if (scalar(@msbs) == 1) {
    print "1 MSB currently stored in the database.";
    print " Click <a href='fbmsb.pl'>here</a> to list its contents.";
  } else {
    print scalar(@msbs) . " MSBs currently stored in the database.";
    print " Click <a href='fbmsb.pl'>here</a> to list them all."
      unless (! @msbs);
  }
  print $q->hr;

}

=item B<msb_table>

Create a table containing information about given MSBs

  msb_table(cgi=>$cgi,
            msbs=>$msbs,
            est_column=>$show_estimated,
            telescope=>$telescope,);


Arguments should be provided in hash form, with the following
keys:

  cgi        - A C<CGI> query object (required).
  msbs       - An array reference containing C<OMP::Info::MSB> objects (required).
  est_column - True if an "Est. time" column, for presenting the estimated
               time in seconds, should be presented.
  opacity_column - True if opacity range column should be presented.
  telescope  - A telescope name.

=cut

sub msb_table {
  my %args = @_;

  # Check for required arguments
  for my $key (qw/cgi msbs telescope/) {
    throw OMP::Error::BadArgs('The argument [$key] is required.')
      unless (defined $args{$key});
  }

  my $q = $args{cgi};
  my $program = $args{msbs};
  my $est_column = $args{est_column};
  my $opacity_column = $args{'opacity_column'};
  my $telescope = $args{telescope};

  # Decide whether to show MSB targets or MSB name
  my $display_msb_name = OMP::Config->getData( 'msbtabdisplayname',
                                               telescope => $telescope,);
  my $alt_msb_column = ($display_msb_name ? 'Name' : 'Target');

  print "<table width=100%>";
  print "<tr bgcolor=#bcbee3><td><b>MSB</b></td>";
  print "<td><b>$alt_msb_column</b></td>";
  print "<td><b>Waveband</b></td>";
  print "<td><b>Instrument</b></td>";

  # Show the estimated time column  if it's been asked for
  print "<td><b>Est. time</b></td>"
    unless (! $est_column);

  print '<td><b>Opacity range</b></td>' if $opacity_column;

  # Only bother with a remaining column if we have remaining
  # information
  print "<td><b>Remaining</b></td>"
    if (defined $program->[0]->remaining);

  # And let's have an N Repeats column if that's available
  print "<td><b>N Repeats</b></td>"
    if (defined $program->[0]->nrepeats);

  # Note that this doesnt really work as code shared for MSB and
  # MSB Done summaries
  my $i;
  foreach my $msb (@$program) {
    # skip if we have a remaining field and it is 0 or less
    # dont skip if the remaining field is simply undefined
    # since that may be a valid case
    next if defined $msb->remaining && $msb->remaining <= 0;

    # Skip if this is only a fetch comment
    next if (scalar @{$msb->comments} &&
             $msb->comments->[0]->status == &OMP__DONE_FETCH);

    # Create a summary table
    $i++;
    print "<tr><td>$i</td>";

    print "<td>" . ($display_msb_name ? $msb->title : $msb->target) . "</td>";
    print "<td>" . $msb->waveband . "</td>";
    print "<td>" . $msb->instrument . "</td>";

    if ($est_column) {
      if ($msb->timeest) {
        # Convert estimated time from seconds to hours
        my $timeest = sprintf "%.2f hours", ($msb->timeest / ONE_HOUR);
        print "<td>$timeest</td>";
      } else {
        print "<td>--</td>";
      }
    }

    if ($opacity_column) {
      my $opacity_range = $msb->tau();
      if ($opacity_range) {
        print '<td>' . $opacity_range . '</td>';
      }
      else {
        print "<td>--</td>";
      }
    }

    print "<td>" . $msb->remaining . "</td>"
      unless (! defined $msb->remaining);
    print "<td>" . $msb->nrepeats . "</td>"
      unless (! defined $msb->nrepeats);
  }

  print "</table>\n";
}

=item B<observed_form>

Create a form with a textfield for inputting a UT date and submitting it.

  observed_form($cgi);

=cut

sub observed_form {
  my $q = shift;

  # Match case of telescope type value as present in database so that it would
  # be already selected in selection list.
  my %tel = OMP::General->find_in_post_or_get( $q, 'telescope' );
  for ( $tel{'telescope'} ) {

    defined $_ and $q->param( 'telescope', uc $_ );
  }


  my $db = new OMP::ProjDB( DB => OMP::DBServer->dbConnection, );

  # Get today's date and use that ase the default
  my $utdate = OMP::DateTools->today;

  # Get the telescopes for our popup menu
  my @tel = $db->listTelescopes;
  my %tel_labels = map {$_, $_} @tel;
  unshift @tel, 0;
  $tel_labels{0} = "Please select";

  print "<table><td align='right'><b>";
  print $q->startform;
  print $q->hidden(-name=>'show_output',
                   -default=>1,);
  print "UT Date: </b><td>";
  print $q->textfield(-name=>'utdate',
                      -size=>15,
                      -maxlength=>75,
                      -default=>$utdate,);
  print "</td><td></td><tr><td align='right'><b>Telescope: </b></td><td>";
  print $q->popup_menu(-name=>'telescope',
                       -values=>\@tel,
                       -labels=>\%tel_labels,
                       -default=>0,);
  print "</td><td colspan=2>";
  print $q->submit("View Comments");
  print $q->endform;
  print "</td></table>";

}

=pod

=item B<_print_msb_header>

Given a hash with information about MSB, print MSB header as (HTML)
table rows and columns.

  _print_msb_header(
    'title' => <MSB title>,
    'title-colspan' => <column-span for the title>,
    'count' => <current number of the MSB>,
    'count-rowspan' => <row-span for current number of the MSB>,
    'status' => <MSB status>,
    'inst' => <instrument>
    'target' => <target>,
    'waveband' => <frequency in Hz>,
  );

MSB count and title are printed in one row; status, target, waveband,
and instrument in the second.  The MSB count table cell spans the rows
as long as title rows plus the number of comments with distinct
transaction ids.

=cut

sub _print_msb_header {

  my ( %info ) = @_;

  return unless %info;

  my $text_pos = { 'valign' => 'top', 'align' => 'left' };
  print
    Tr( $text_pos,
        th( { 'align' => 'right',
              'rowspan' => $info{'count-rowspan'} || 1
            },
            $info{'count'} . '.'
          ),
        th( { 'colspan' => $info{'title-colspan'} },
            $info{'title'} || $NBSP ,
          ),
      ),
    Tr( $text_pos,
        td( { 'align' => 'center',
              'rowspan' => $info{'count-rowspan'} - 1
            },
            $info{'status'} || $NBSP
          ),
        td( { 'colspan' =>  $info{'title-colspan'} - 1 },
            join +( $NBSP ) x 2,
              map
                { my $label = $_->[0];
                  join $NBSP, ( $label ? b( $label . ':' ) : '' ), $_->[1];
                }
                [ 'Target'     , $info{'target'} ],
                [ 'Waveband'   , OMP::General::frequency_in_xhz( $info{'waveband'} ) ],
                [ 'Instrument' , $info{'inst'} ]
          )
      ) ;

  return;
}

=pod

=item B<_print_transaction_comments>

Given array reference of OMP::Info::Comment objects associated with a
transaction id, print the comments in <p>, with dividers (<hr>) if
appropriate.

  _print_transaction_comments(
    $cgi,
    { 'comments' => <array ref of OMP::Info::Comment objects>,
      'comment-colspan' => <column-span for comment table cells>,
      'colors' =>
        <hash ref of keys as OMP__DONE* status, colors as values>',
      'hidden' =>
        <array ref of hidden field HTML code strings
          to pass to "Add comment to MSB" form>
    }
  );

See also L<OMP::Constants/MSB Done constants>.

=cut

sub _print_transaction_comments {

  my ( $query, $args ) = @_;

  return
    unless $query
    && $args && OMP::General->hashref_keys_size( $args )
    ;

  my %prop = ( 'valign' => 'top', 'align' => 'left' );

  my $count = scalar @{ $args->{'comments'} };

  my $all = $args->{'comments'};
  my ( $prev );
  for my $i ( 0 .. $count - 1 ) {

    my $c = $all->[ $i ];

    my $cur = $c->tid;
    #  Consider each comment with empty|undef transaction id as
    #  unique.
    my $diff = ! ( $cur && $prev && $cur eq $prev );
    $prev = $cur ;

    unless ( $diff ) {

      # Divider between two comments with the same transaction ids.
      $i and print hr ;
    }
    else {

      # Divider(Blank row) between comments with different transaction ids.
      $i and
        print
          Tr( td( { 'align' => 'center', 'valign' => 'middle', 'colspan' => 2 },
                  hr
                )
            ) ;

      # End of comments.
      $i + 1 == $count and print end_td, end_Tr ;

      # Start of comments.
      my @comment_form = (defined $cur)
        ? ( $query->startform, "\n",
            $query->submit('Add Comment'), "\n",
            @{ $args->{'hidden' } }, "\n",
            $query->hidden(-name => 'transaction', -default => $cur),
            $query->endform, "\n", )
        : ( '&nbsp;' );

      print
        start_Tr( { %prop, 'bgcolor' => $args->{'colors'}->{ $c->status } } ),
        td(@comment_form),
        start_td( { 'colspan' => $args->{'comment-colspan'} } ) ;
    }

    # The actual comment.  Finally!
    my $author = $c->author;
    print
      div( { 'class' => 'black' },
            join( ', ', i( $c->date . ' UT' ),
                  $author ? $author->html : ()
                  #, $cur ? '( ' . $cur . ' )' : '--'
                ),
            '<br>', $c->text
          ) ;
  }

  return;
}

=pod

=item B<_make_non_empty_hidden_fields>

Given C<CGI> object and the parameter names associated with the
object, returns an array of HTML strings of hidden fields for those
parameters which have non empty values.

  print
    _make_non_empty_hidden_fields( $cgi, qw[ telescope utdate ] );

=cut

sub _make_non_empty_hidden_fields {

  my ( $cgi, @fields ) = @_;

  return
    OMP::Display->make_hidden_fields(
      $cgi,
      { map
          { length $cgi->param( $_ ) ? ( $_ => $cgi->param( $_ ) )
              : ()
          }
          @fields
      }
    ) ;
}

=pod

=item B<_count_unique_tids>

Given an array of OMP::Info::Comment objects, returns the count of comments with
unique transaction ids, where each comment with missing transaction id is also
considered to be unique for the purpose of HTML table code generation.

  my $count = _count_unique_tids( @comments );

=cut

sub _count_unique_tids {

  my ( @comments ) = @_;

  my %uniq;
  # C<OMP::Info::Comment::tid> method produces a string =~
  # m/^[A-Z]+[_0-9]+$/ if a transaction id is present, so no need to
  # be concerned about it being 0-but-valid id.
  $uniq{ $_->tid ? $_->tid : 'empty' }++ for @comments;

  return
    # keys() already accounts for 1 of the empty values.
    ( $uniq{'empty'} ? $uniq{'empty'} - 1 : 0 )
    + scalar keys %uniq
    ;
}

=back

=head1 SEE ALSO

C<OMP::CGI::MSBPage>

=head1 AUTHOR

Kynan Delorey E<lt>k.delorey@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place, Suite 330,
Boston, MA  02111-1307  USA

=cut

1;
