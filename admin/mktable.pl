#!/local/perl-5.6/bin/perl5.6.1

# quick program to create a "database" table for testing the OMP

use strict;
use warnings;
use File::Spec;

# Pick up the OMP database
use FindBin;
use lib "$FindBin::RealBin/..";
use OMP::DBbackend;

# Connect
my $db = new OMP::DBbackend;
my $dbh = $db->handle;

my %tables = (
	      ompmsb => {
			 msbid => "INTEGER",
			 projectid=> "VARCHAR(32)",
			 remaining => "INTEGER",
			 checksum => "VARCHAR(64)",
			 taumin => "REAL",
			 taumax => "REAL",
			 seeingmin => "REAL",
			 seeingmax => "REAL",
			 priority => "INTEGER",
			 moon => "INTEGER",
			 timeest => "REAL",
			 title => "VARCHAR(255)",
			 obscount => "INTEGER",
			 datemin => "DATETIME",
			 cloud => "INTEGER",
			 datemax => "DATETIME",
			 telescope => "VARCHAR(16)",
			 _ORDER => [qw/ msbid projectid remaining checksum
				    obscount taumin taumax seeingmin seeingmax
				    priority telescope moon cloud
				    timeest title datemin datemax
				    /],
		       },
	      ompcoiuser => {
			     userid => "VARCHAR(20) NULL",
			     projectid => "VARCHAR(32)",
			     _ORDER => [ qw/ projectid userid /],
			    },
	      ompsupuser => {
			     userid => "VARCHAR(20) NULL",
			     projectid => "VARCHAR(32)",
			     _ORDER => [ qw/ projectid userid /],
			    },
	      ompproj => {
			  projectid => "VARCHAR(32)",
			  pi => "VARCHAR(20)",
			  remaining => "REAL",
			  pending => "REAL",
			  allocated => "REAL",
			  country => "VARCHAR(32)",
			  tagpriority => "INTEGER",
			  semester => "VARCHAR(5)",
			  encrypted => "VARCHAR(20)",
			  title => "VARCHAR(132)",
			  _ORDER => [qw/projectid pi
				     title tagpriority
				     country semester encrypted allocated
				     remaining pending
				     /],
			 },
	      ompobs => {
			 obsid => "INTEGER",
			 msbid => "INTEGER",
			 projectid => "VARCHAR(32)",
			 instrument => "VARCHAR(32)",
			 wavelength => "REAL",
			 disperser => "VARCHAR(32) NULL",
			 coordstype => "VARCHAR(32)",
			 target => "VARCHAR(32)",
			 ra2000 => "REAL NULL",
			 dec2000 => "REAL NULL",
			 el1 => "REAL NULL",
			 el2 => "REAL NULL",
			 el3 => "REAL NULL",
			 el4 => "REAL NULL",
			 el5 => "REAL NULL",
			 el6 => "REAL NULL",
			 el7 => "REAL NULL",
			 el8 => "REAL NULL",
			 pol => "BIT",
			 timeest => "REAL",
			 type => "VARCHAR(32)",
			 _ORDER => [qw/obsid msbid projectid
				    instrument type pol wavelength disperser
				    coordstype target ra2000 dec2000 el1 el2
				    el3 el4 el5 el6 el7 el8 timeest
				    /],
			},
	      ompmsbdone => {
			     commid => "numeric(5,0) IDENTITY",
			     checksum => "VARCHAR(64)",
			     projectid => "VARCHAR(32)",
			     date => "DATETIME",
			     comment => "TEXT",
			     instrument => "VARCHAR(64)",
			     waveband => "VARCHAR(64)",
			     target => "VARCHAR(64)",
			     status => "INTEGER",
			     _ORDER => [qw/
					commid checksum status projectid date
					target instrument waveband
					comment
					/],
			    },
	      ompsciprog => {
			     projectid => "VARCHAR(32)",
			     timestamp => "INTEGER",
			     sciprog   => "TEXT",
			     _ORDER => [qw/
					projectid timestamp sciprog
					/],
			     },
	      ompfeedback => {
			      commid => "numeric(5,0) IDENTITY",
			      entrynum => "numeric(4,0) not null",
			      projectid => "char(32) not null",
			      author => "char(50) not null",
			      date => "datetime not null",
			      subject => "char(128) null",
			      program => "char(50) not null",
			      sourceinfo => "char(60) not null",
			      status => "integer null",
			      text => "text not null",
			      _ORDER => [qw/
					 commid entrynum projectid author date subject
					 program sourceinfo status text
					/],
			     },
	      ompfault => {
			   faultid => "DOUBLE PRECISION", # Required
			   entity => "varchar(64) null",
			   type   => "integer",
			   system => "integer",
			   category => "VARCHAR(32)",
			   timelost => "REAL",
			   faultdate => "datetime null",
			   status => "INTEGER",
			   subject => "VARCHAR(128) null",
			   urgency => "INTEGER",
			   _ORDER => [qw/
				      faultid category subject faultdate type
				      system status urgency timelost entity
				      /],
			  },
	      ompfaultbody => {
			       respid => "numeric(5,0) IDENTITY",
			       faultid => "DOUBLE PRECISION", # Required
			       date => "datetime",
			       isfault => "integer",
			       text => "text",
			       author => "varchar(50)",
			       _ORDER => [qw/
					  respid faultid date author isfault 
					  text
					  /],
			      },
	      ompuser => {
			  userid => "VARCHAR(32)",
			  name => "VARCHAR(255)",
			  email => "VARCHAR(64)",
			  _ORDER => [qw/ userid name email /],
			 },
	     );

for my $table (sort keys %tables) {
  # Comment out as required
  next if $table eq 'ompproj';
  next if $table eq 'ompsciprog';
  next if $table eq 'ompmsb';
  next if $table eq 'ompobs';
  next if $table eq 'ompfeedback';
  next if $table eq 'ompmsbdone';
  next if $table eq 'ompfault';
  next if $table eq 'ompfaultbody';
  next if $table eq 'ompuser';
  next if $table eq 'ompsupuser';
  next if $table eq 'ompcoiuser';


  my $str = join(", ", map {
    "$_ " .$tables{$table}->{$_}
  } @{ $tables{$table}{_ORDER}} );

  # Usually a failure to drop is non fatal since it
  # indicates that the table is not there to drop
  my $sth;
  print "Drop table $table\n";
  $sth = $dbh->prepare("DROP TABLE $table")
    or die "Cannot prepare SQL to drop table";

  $sth->execute();
  $sth->finish();

  print "\n$table: $str\n";
  print "SQL: CREATE TABLE $table ($str)\n";
  $sth = $dbh->prepare("CREATE TABLE $table ($str)")
    or die "Cannot prepare SQL for CREATE table $table: ". $dbh->errstr();

  $sth->execute() or die "Cannot execute: " . $sth->errstr();
  $sth->finish();

  # We can grant permission on this table as well
  $dbh->do("GRANT ALL ON $table TO omp")
    or die "Error1: $DBI::errstr";

}

# Close connection
$dbh->disconnect();
