package OMP::CGIPkgData;

=head1 NAME

OMP::CGIPkgData - Routines to help web serving of data packaging

=head1 SYNOPSIS

  use OMP::CGIPkgData;


=head1 DESCRIPTION

General routines required to create a web page for packaging
OMP data files for the PI.

=cut

use 5.006;
use strict;
use warnings;
our $VERSION = '0.01';

use OMP::PackageData;

=head1 PUBLIC FUNCTIONS

These functions write the web page.

=over 4

=item B<request_data>

Request the UT date of interest and/or package the data
and serve it.

=cut

sub request_data {
  my $q = shift;
  my %cookie = @_;

  # First try and get the fault ID from the URL param list,
  # then try the normal param list.
  my $utdate = $q->url_param('utdate');
  $utdate = $q->param('utdate') unless $utdate;

  my $inccal = $q->url_param('inccal');
  $inccal = $q->param('inccal') unless $utdate;

  # if we have a date, package up the data
  if ($utdate) {
    &_package_data($q, $utdate, $inccal, \%cookie);

  } else {
    &_write_form($q, \%cookie);
  }

}

=back

=head2 Internal functions

=over 4

=item B<_write_form>

Write the form requesting a UT date.

  _write_form( $q, \%cookie );

=cut

sub _write_form {
  my $q = shift;
  my $cookie = shift;

  print $q->h2("Retrieve data for project ". $cookie->{projectid} );
  print "<table border=0><tr><td>";
  print $q->startform;
  print "<b>Enter a UT date: (YYYY-MM-DD)</b></td><td>";
  print $q->textfield(-name=>'utdate',
		      -size=>15,
		      -maxlength=>32);
  print "</td><tr><td>";
  print "Include calibrations:</td><td>";
  print $q->radio_group(-name=>'inccal',
			-values=>['Yes','No'],
			-default=>'Yes');
  print "</td><tr><td colspan=2 align=right>";

  print $q->submit(-name=>'Submit');
  print $q->endform;
  print "</td></table>";

}

=item B<_package_data>

Write output HTML and package up the data.

  _package_data( $q, $utdate_string, $inccal, \%cookie );

=cut

sub _package_data {
  my $q = shift;
  my $utdate = shift;
  my $inccal = shift;
  my $cookie = shift;

  print $q->h2("Retrieving data for project ". $cookie->{projectid} .
    " and UT date $utdate");

  my $pkg = new OMP::PackageData( utdate => $utdate,
				  projectid => $cookie->{projectid},
				  password => $cookie->{password},
				);


  # we use verbose messages
  print "<PRE>\n";
  $pkg->pkgdata;
  print "</PRE>\n";

  my $url = $pkg->ftpurl;
  if (defined $url) {
    print "Retrieve your data from url: <A href=\"$url\">$url</a>";
  } else {
    print "There must have been an untrapped error. Could not obtain a url";
  }


}

=back

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

1;
