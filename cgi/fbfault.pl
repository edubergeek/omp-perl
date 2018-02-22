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
use OMP::CGIPage::Project;

my $arg = shift @ARGV;

my $q = new CGI;

my $cgi = new OMP::CGIPage( CGI => $q );

my $title = $cgi->html_title;
$cgi->html_title("$title: View Faults");
$cgi->write_page( \&OMP::CGIPage::Project::fb_fault_content,
                  \&OMP::CGIPage::Project::fb_fault_content, );
