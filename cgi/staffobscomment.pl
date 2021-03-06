#!/local/perl/bin/perl -XT
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

# Load OMP modules
use OMP::CGIPage;
use OMP::CGIPage::Obslog;
use OMP::NetTools;

my $cquery = new CGI;
my $cgi = new OMP::CGIPage( CGI => $cquery );
$cgi->html_title( "OMP Observation Log" );

# write the page
if (OMP::NetTools->is_host_local) {
  $cgi->write_page_noauth( \&file_comment, \&file_comment_output );
} else {
  $cgi->write_page_staff( \&file_comment, \&file_comment_output, "noauth" );
}

