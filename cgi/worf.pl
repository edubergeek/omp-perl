#!/local/perl/bin/perl -XT
#
# WWW Observing Remotely Facility (WORF)
#
# http://www.jach.hawaii.edu/JACpublic/UKIRT/software/worf/
#
# Requirements:
# TBD
#
# Authors: Frossie Economou (f.economou@jach.hawaii.edu)
#          Brad Cavanagh (b.cavanagh@jach.hawaii.edu)
use strict;

# Standard initialisation (not much shorter than the previous
# code but no longer has the module path hard-coded)
BEGIN {
  my $retval = do "./omp-cgi-init.pl";
  unless ($retval) {
    warn "couldn't parse omp-cgi-init.pl: $@" if $@;
    warn "couldn't do omp-cgi-init.pl: $!"    unless defined $retval;
    warn "couldn't run omp-cgi-init.pl"       unless $retval;
    exit;
  }
}

# Set up the environment for PGPLOT
BEGIN {
  $ENV{'PGPLOT_DIR'} = '/star/bin';
  $ENV{'PGPLOT_FONT'} = '/star/bin/grfont.dat';
  $ENV{'PGPLOT_GIF_WIDTH'} = 600;
  $ENV{'PGPLOT_GIF_HEIGHT'} = 450;
  $ENV{'PGPLOT_BACKGROUND'} = 'white';
  $ENV{'PGPLOT_FOREGROUND'} = 'black';
  $ENV{'HDS_SCRATCH'} = "/tmp";
}

# Load OMP modules
use OMP::CGIPage;
use OMP::CGIPage::WORF;

# Set up global variables, system variables, etc.

my $query = new CGI;
my $cgi = new OMP::CGIPage( CGI => $query );
$cgi->html_title("WORF: UKIRT WWW Observing Remotely Facility");

# write the page

$cgi->write_page_noauth( \&display_page, \&display_page );

