package OMP::CGITimeAlloc;

use 5.006;
use strict;
use warnings;
use Carp;
our $VERSION = (qw$ Revision: $ )[1];

use OMP::CGI;
use OMP::TimeAcctDB;
use OMP::FaultStats;
use OMP::Info::ObsGroup;
use OMP::Project::TimeAcct;
#use OMP::ArchiveServer;
use OMP::Error qw(:try);

use Net::Domain qw/ hostfqdn /;
use Data::Dumper;

use vars qw/@ISA %EXPORT_TAGS @EXPORT_OK/;

require Exporter;

$| = 1;

@ISA = qw/Exporter/;

@EXPORT_OK = (qw/timealloc timealloc_output/);

%EXPORT_TAGS = (
                'all' => [ @EXPORT_OK ],
               );

Exporter::export_tags(qw/ all /);

=head1 Routines

=over 4

=item B<timealloc>

Creates a page with a form for filling in time allocations for a night.

  timealloc( $cgi );

Only argument should be the C<CGI> object.

=cut

sub timealloc {
  my $q = shift;
  my %cookie = @_;

  my $qvars = $q->Vars;
  my $params = verify_query( $qvars );

  display_form( $q, $params );

  display_ut_form( $q, $params );

}

=item B<timealloc_output>

Submits time allocations for a night, and creates a page with a form for
filling in time allocations for a night time allocations.

  timealloc_output( $cgi );

Only argument should be the C<CGI> object.

=cut

sub timealloc_output {
  my $q = shift;
  my %cookie = @_;

  my $qvars = $q->Vars;
  my $params = verify_query( $qvars );

  submit_allocations( $params );

  display_form( $q, $params );

  display_ut_form( $q, $params );

}

=item B<display_form>

Display a form for time allocations.

  display_form( $q, $params );

The first parameter is a C<CGI> object, and the second parameter
is a hash containing the verified CGI query parameters.

=cut

sub display_form {
  my $query = shift;
  my $params = shift;

  my $faultproj;
  my $weatherproj;
  my $otherproj;

  my %dbtime;
  my %obstime;

  # Retrieve the projects displayed on the UT date given and for
  # the telescope given.
  my $ut = $params->{'ut'};
  my $telescope = $params->{'telescope'};

  my $dbconnection = new OMP::DBbackend;
  my $db = new OMP::TimeAcctDB( DB => $dbconnection );
  my @accounts = $db->getTimeSpent( utdate => $ut );
  foreach my $account ( @accounts ) {
    $dbtime{$account->projectid} = $account;
  }

  # Retrieve an ObsGroup object for the UT date.

# ************************************************************
# * NOTE                                                     *
# ************************************************************
# This code is currently telescope-specific, in that if we're
# getting information for the JCMT, all we're going to get is
# SCUBA information. If we're at UKIRT, just go through fine,
# but if we're at JCMT, restrict to SCUBA.
  my $obsgroup;
  if( $telescope =~ /jcmt/i ) {
    $obsgroup = new OMP::Info::ObsGroup( instrument => 'scuba',
                                         date => $ut,
                                       );
  } else {
    $obsgroup = new OMP::Info::ObsGroup( telescope => $telescope,
                                         date => $ut,
                                       );
  }

  # Retrieve the TimeAcct objects for the group
  my @obstime = $obsgroup->projectStats;

  # Convert the TimeAcct array into a hash for easier project
  # searching.
  foreach my $obstime ( @obstime ) {
    $obstime{$obstime->projectid} = $obstime;
  }

  # Print a header.
  print "For UT $ut the following projects were observed:<br>\n";
  print $query->startform;
  print $query->hidden( -name => 'ut',
                        -default => $ut,
                      );
  print "<table>";
  print "<tr><th>Project</th><th>Hours</th><th>Status</th></tr>\n";
  # For each TimeAcct object, print a form entry.
  my $i = 1;
  foreach my $projectid (keys %obstime) {

    print "<tr><td>";
    print $projectid;
    print "</td><td>";
    print $query->textfield( -name => 'hour' . $i,
                             -size => '8',
                             -maxlength => '8',
                             -default => ( defined( $dbtime{$projectid} ) ?
                                           sprintf( "%.1f", $dbtime{$projectid}->timespent->hours ) :
                                           sprintf( "%.1f", $obstime{$projectid}->timespent->hours ) ),
                           );
    print "</td><td>";
    if( defined( $dbtime{$projectid} ) ) {
      print "Confirmed";
    } else {
      print "Estimated";
    }
    print $query->hidden( -name => 'project' . $i,
                          -default => $projectid,
                        );
    print "</td></tr>\n";
    print "<tr><td>&nbsp;</td><td colspan=\"2\">";
    my $hours = sprintf("%5.3f",$obstime{$projectid}->timespent->hours);
    print "$hours hours from data headers</td></tr>\n";

    $i++;
  }
  print "</table>";

  # Display miscellaneous time form (faults, weather, other).
  print "Time lost to faults: ";
  print $query->textfield( -name => 'hour' . $i,
                           -size => '8',
                           -maxlength => '16',
                           -default => ( defined( $dbtime{'FAULT'} ) ?
                                         $dbtime{'FAULT'}->timespent->hours :
                                         '0' ),
                         );
  print $query->hidden( -name => 'project' . $i,
                        -default => 'FAULT',
                      );
  print " hours<br>\n";
  my $fdb = new OMP::FaultDB( DB => new OMP::DBbackend );
  my @results = $fdb->getFaultsByDate($ut);
  my $faultstats = new OMP::FaultStats( faults => \@results );
  print $faultstats->summary('html');

  $i++;
  print "Time lost to weather: ";
  print $query->textfield( -name => 'hour' . $i,
                           -size => '8',
                           -maxlength => '16',
                           -default => ( defined( $dbtime{'WEATHER'} ) ?
                                         $dbtime{'WEATHER'}->timespent->hours :
                                         '0' ),
                         );
  print $query->hidden( -name => 'project' . $i,
                        -default => 'WEATHER',
                      );
  print " hours<br>\n";

  $i++;
  print "Other time lost: ";
  print $query->textfield( -name => 'hour' . $i,
                           -size => '8',
                           -maxlength => '16',
                           -default => ( defined( $dbtime{'OTHER'} ) ?
                                         $dbtime{'OTHER'}->timespent->hours :
                                         '0' ),
                         );
  print $query->hidden( -name => 'project' . $i,
                        -default => 'OTHER',
                      );
  print " hours<br><br>\n";

  print $query->hidden( -name => 'ut',
                        -default => $params->{'ut'},
                      );
  print $query->hidden( -name => 'telescope',
                        -default => $params->{'telescope'},
                      );

  print $query->submit( -name => 'CONFIRM APPORTIONING' );
  print $query->endform;

}

sub submit_allocations {
  my $q = shift;

  # Grab the UT date from the query object. If it does not exist,
  # default to the current UT date.
  my $ut;
  if( defined( $q->{'ut'} ) &&
     $q->{'ut'} =~ /(\d{4}-\d\d-\d\d)/ ) {
    $ut = $1; # This removes taint from the UT date given.
  } else {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $ut = ($year + 1900) . "-" . pad($month + 1, "0", 2) . "-" . pad($day, "0", 2);
  }

  # Build a hash with keys of project IDs and values of hours
  # allocated to those project IDs.
  my %timealloc;
  my $i = 1;
  while ( defined( $q->{'project' . $i} ) ) {
    $timealloc{$q->{'project' . $i}} = $q->{'hour' . $i};
    $i++;
  }

  # Create an array of OMP::Project::TimeAcct objects
  my @acct;
  foreach my $projectid (keys %timealloc) {
    my $t = new OMP::Project::TimeAcct( projectid => $projectid,
                                        date => OMP::General->parse_date($ut),
                                        timespent => new Time::Seconds( $timealloc{$projectid} * 3600 ),
                                        confirmed => 1,
                                      );
    push @acct, $t;
  }
  my $dbconnection = new OMP::DBbackend;
  my $db = new OMP::TimeAcctDB( DB => $dbconnection );
  $db->setTimeSpent( @acct );
}

sub display_ut_form {
  my $query = shift;
  my $q = shift;

  print $query->startform;
  print "Enter new UT date (yyyy-mm-dd format): ";
  print $query->textfield( -name => 'ut',
                       -size => '10',
                       -maxlength => '10',
                       -default => $q->{'ut'},
                     );
  print "<br>\n";
  print $query->hidden( -name => 'telescope',
                        -default => $q->{'telescope'},
                      );
  print $query->submit( -name => 'Submit UT date' );
  print $query->endform;
}

sub verify_query {
  my $q = shift;

  my $v;

  if( defined($q->{'ut'}) &&
      $q->{'ut'} =~ /^(\d{4}-\d\d-\d\d)$/ ) {
    $v->{'ut'} = $1;
  } else {
    my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdist) = gmtime(time);
    $v->{'ut'} = ($year + 1900) . "-" . pad($month + 1, "0", 2) . "-" . pad($day, "0", 2);
  }

  if( !defined($q->{'ut'}) ) {
    my $hostname = hostfqdn;
    if($hostname =~ /mauiola/i) {
      $v->{'telescope'} = "ukirt";
    } else {
      $v->{'telescope'} = "jcmt";
    }
  } else {
    my $temptel = $q->{'telescope'};
    $temptel =~ s/[^a-zA-Z0-9]//g;
    $temptel =~ /(.*)/;
    $v->{'telescope'} = $1;
  }

  return $v;

}

sub pad {
  my ($string, $character, $endlength) = @_;
  my $result = ($character x ($endlength - length($string))) . $string;
}

1;
