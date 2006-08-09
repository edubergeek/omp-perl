package OMP::SpServer;

=head1 NAME

OMP::SpServer - Science Program Server class

=head1 SYNOPSIS

  $xml = OMP::SpServer->fetchProgram($project, $password);
  $summary = OMP::SpServer->storeProgram($xml, $password, 0);

=head1 DESCRIPTION

This class provides the public server interface for the OMP Science
Program database server. The interface is specified in document
OMP/SN/002.

This class is intended for use as a stateless server. State is
maintained in external databases. All methods are class methods.

=cut

use strict;
use warnings;
use Carp;

# OMP dependencies
use OMP::SciProg;
use OMP::MSBDB;
use OMP::General;
use OMP::Error qw/ :try /;

use Astro::Catalog;
use Compress::Zlib;
use Time::HiRes qw/ tv_interval gettimeofday /;

# Different Science program return types
use constant OMP__SCIPROG_XML => 0;
use constant OMP__SCIPROG_OBJ => 1;
use constant OMP__SCIPROG_GZIP => 2;
use constant OMP__SCIPROG_AUTO => 3;

# GZIP threshold in bytes
use constant GZIP_THRESHOLD => 30_000;

# Inherit server specific class
use base qw/OMP::SOAPServer OMP::DBServer/;

our $VERSION = (qw$Revision$)[1];

=head1 METHODS

=over 4

=item B<storeProgram>

Store an OMP Science Program (as XML) in the database. The password
must match that associated with the project specified in the science
program.

  [$summary, $timestamp] = OMP::SpServer->storeProgram($sciprog, $password);

Returns an array containing the summary of the science program (in
plain text) that can be used to provide feedback to the user as well
as the timestamp attached to the file in the database (for consistency
checking).

An optional third parameter can be used to control the behaviour
if the timestamps do not match. If false an exception will be raised
(of type C<SpChangedOnDisk>) and the store will fail if the timestamp
of the program being stored does not match that already in the database.
If true the timestamp test will be ignored and the program will be
stored. This allows people to force the storing of a science program
and should be used with care.

  [$summary, $timestamp] = OMP::SpServer->storeProgram($sciprog, 
                                                       $password, $force);

This method automatically recognizes whether the science program is 
gzip compressed.

=cut

sub storeProgram {
  my $class = shift;

  my $xml = shift;
  my $password = shift;
  my $force = shift;

  my $t0 = [gettimeofday];
  OMP::General->log_message( "storeProgram: Begin.\nForce=" .
			   ( defined $force ? $force : 0 ). "\n");

  my ($string, $timestamp);
  my $E;
  try {

    # Attempt to gunzip it if it looks like a gzip stream
    if (substr($xml,0,2) eq chr(0x1f).chr(0x8b)) {
      # GZIP magic number verifies
      $xml = Compress::Zlib::memGunzip( $xml );
      throw OMP::Error::SpStoreFail("Science program looked like a gzip byte stream but did not uncompress correctly")
        unless defined $xml;
    }

    # Create a science program object
    my $sp = new OMP::SciProg( XML => $xml );
    OMP::General->log_message( "storeProgram: Project " .
			     $sp->projectID . "\n");

    # Check the version number and abort if it is too old
    my $minver = '20060401';
    my $otver = $sp->ot_version;
    if (!defined $otver || $otver < $minver) {
      $otver = "0" unless defined $otver;
      throw OMP::Error::SpStoreFail("This science program was generated by a version of the OT (ver. $otver)\n" .
				    "that is too old for submitting programmes for this semester.\n Please upgrade to at least version $minver, available from\n http://www.jach.hawaii.edu/JAC/software/jcmtot/download.html\n");
    }


    # Create a new DB object
    my $db = new OMP::MSBDB( Password => $password,
			     ProjectID => $sp->projectID,
			     DB => $class->dbConnection,
			   );

    # Store the science program
    my @warnings = $db->storeSciProg( SciProg => $sp, Force => $force );

    # Create a summary of the science program
    $string = join("\n",$sp->summary) . "\n";

    # Add warnings from the store
    $string = join("\n", @warnings) ."\n" . $string if @warnings;

    # Verify the science program and attach that to the string
    # we are not expecting any fatal errors here
    my ($spstat, $spreason) = $sp->verifyMSBs;
    if ($spstat == 1) {
      $string = $spreason . "\n" . $string;
    } elsif ($spstat == 2) {
      # Fatal error
      throw OMP::Error::FatalError("Error verifying science program: $spreason");
    }


    # Retrieve the timestamp
    $timestamp = $sp->timestamp;

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;
  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;

  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  OMP::General->log_message( "storeProgram: Complete in ".
			     tv_interval($t0)."seconds. Stored with timestamp $timestamp\n");
  return [$string, $timestamp];
}

=item B<fetchProgram>

Retrieve a science program from the database.

  $xml = OMP::SpServer->fetchProgram( $project, $password );

The return argument is an XML representation of the science
program (encoded in base64 for speed over SOAP if we are using
SOAP).

A third argument controls whether the request should be gzip compressed
prior to Base64 encoding.

A third argument controls what form the returned science program should
take.

  $gzip = OMP::SpServer->fetchProgram( $project, $password, "GZIP" );

The following values can be used to specify different return
types:

  "XML"    OMP__SCIPROG_XML   (default)  Plain text XML
  "OBJECT" OMP__SCIPROG_OBJ   Perl OMP::SciProg object
  "GZIP"   OMP__SCIPROG_GZIP  Gzipped XML
  "AUTO"   OMP__SCIPROG_AUTO  plain text or gzip depending on size

These are not exported and are defined in the OMP::SpServer namespace.

Note that for cases XML and GZIP, these will be Base64 encoded if returned
via a SOAP request.

=cut

sub fetchProgram {
  my $class = shift;
  my $projectid = shift;
  my $password = shift;
  my $rettype = shift;

  $rettype = OMP__SCIPROG_XML unless defined $rettype;
  $rettype = uc($rettype);

  # Translate input strings to constants
  if ($rettype !~ /^\d$/) {
    $rettype = OMP__SCIPROG_XML  if $rettype eq 'XML';
    $rettype = OMP__SCIPROG_OBJ  if $rettype eq 'OBJECT';
    $rettype = OMP__SCIPROG_GZIP if $rettype eq 'GZIP';
    $rettype = OMP__SCIPROG_AUTO if $rettype eq 'AUTO';
  }

  my $t0 = [gettimeofday];
  OMP::General->log_message( "fetchProgram: Begin.\nProject=$projectid\nFormat=$rettype\n");

  my $sp;
  my $E;
  try {

    # Create new DB object
    my $db = new OMP::MSBDB( Password => $password,
			     ProjectID => $projectid,
			     DB => $class->dbConnection, );

    # Retrieve the Science Program object
    $sp = $db->fetchSciProg;

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;
  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;


  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;


  if ($rettype == OMP__SCIPROG_OBJ) {
    # return the object
    return $sp;
  } else {

    # Return the stringified form, compressed
    my $string;
    if ($rettype == OMP__SCIPROG_GZIP || $rettype == OMP__SCIPROG_AUTO) {
      $string = "$sp";

      # Force gzip if requested
      if ($rettype == OMP__SCIPROG_GZIP || length($string) > GZIP_THRESHOLD) {
	# Compress the string if its length is greater than the 
	# threshold value
	$string = Compress::Zlib::memGzip( "$sp" );
      }

      throw OMP::Error::FatalError("Unable to gzip compress science program")
	unless defined $string;

    } else {
      $string = "$sp";
    };

    OMP::General->log_message("fetchProgram: Complete in ".tv_interval($t0)." seconds\n");

    return (exists $ENV{HTTP_SOAPACTION} ? SOAP::Data->type(base64 => $string)
	    : $string );
  }

}

=item B<programDetails>

Return a detailed summary of the science program. The summary is
returned as either pre-formatted text or as a data structure (array of
hashes for each MSB with each hash containing an array of hashes for
each observation).

  $text = OMP::SpServer->programDetails($project,$password,'ascii' );
  $array = OMP::SpServer->programDetails($project,$password,'data' );

Note that this may cause problems for a strongly typed language.

The project password is required.

=cut

sub programDetails {
  my $class = shift;
  my $projectid = shift;
  my $password = shift;
  my $mode = lc(shift);
  $mode ||= 'ascii';

  OMP::General->log_message( "programDetails: $projectid and $mode\n");

  my $E;
  my $summary;
  try {

    # Create new DB object
    my $db = new OMP::MSBDB( 
			    ProjectID => $projectid,
			    Password => $password,
			    DB => $class->dbConnection, );

    # Retrieve the Science Program object
    # without sending explicit notification
    my $sp = $db->fetchSciProg(1);

    # Create a summary of the science program
    $summary = $sp->summary($mode);

    # Clean the data structure if we are in 'data'
    if ($mode eq 'data') {
      for my $msb (@{$summary}) {
	delete $msb->{_obssum};
	delete $msb->{summary};
	$msb->{datemax} = ''.$msb->{datemax}; # unbless
	$msb->{datemin} = ''.$msb->{datemin}; # unbless
	for my $obs (@{$msb->{obs}}) {
	  $obs->{waveband} = ''.$obs->{waveband}; # unbless
	  $obs->{coords} = [$obs->{coords}->array];
	}
      }
    }

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;
  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;


  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  # Return the stringified form
  return $summary;
}

=item B<programInstruments>

Return a reference to an array of all the instruments associated with
the specified science program.

  $array = OMP::SpServer->programInstruments( $project );

No password required.

=cut

sub programInstruments {
  my $class = shift;
  my $projectid = shift;

  OMP::General->log_message( "programInstruments: $projectid\n");

  my $E;
  my @inst;
  try {

    # Create new DB object
    my $db = new OMP::MSBDB( 
			    ProjectID => $projectid,
			    DB => $class->dbConnection, );

    @inst = $db->getInstruments();

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;
  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;


  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  # Return the stringified form
  return \@inst;
}

=item B<SpInsertCat>

Given a science program and a JCMT-format source catalogue, clone
any blank MSBs inserting the catalogue information and return the
result.

  [$xml, $info] = OMP::SpServer->SpInsertCat( $xml, $catalogue );

Returns a reference to an array containing the modified science
program XML and a string containing any informational messages
(separated by newlines).

The catalogue is supplied as a text string including new lines.

=cut

sub SpInsertCat {
  my $class = shift;
  my $xml = shift;
  my $catstr = shift;

  OMP::General->log_message( "SpInsertCat: processing catalog");

  my $E;
  my ($sp, @info);
  try {

    # Create a science program from the string
    $sp = new OMP::SciProg( XML => $xml );
    my $proj = $sp->projectID;
    $proj = "<UNKNOWN>" unless defined $proj;
    OMP::General->log_message("SpInsertCat: ProjectID: $proj");

    # Extract target information from catalogue
    my $cat = new Astro::Catalog(Format => 'JCMT',
				 Data => $catstr );
    my @coords = map { $_->coords } $cat->allstars;

    # Clone the template MSBs
    @info = $sp->cloneMSBs( @coords );

  } catch OMP::Error with {
    # Just catch OMP::Error exceptions
    # Server infrastructure should catch everything else
    $E = shift;
  } otherwise {
    # This is "normal" errors. At the moment treat them like any other
    $E = shift;


  };
  # This has to be outside the catch block else we get
  # a problem where we cant use die (it becomes throw)
  $class->throwException( $E ) if defined $E;

  my $infostr = join("\n", @info) . "\n";
  my $spstr = "$sp";

  # Return the result
  return [ $spstr, $infostr];
}

sub returnStruct {
  my $self = shift;

  return {  summary => "hello", timestamp => 52 };

}

sub returnArray {
  my $self = shift;

  return [ "hello", 52 ];

}

sub returnList {
  my $self = shift;
  return ("hello", 52);
}


=back

=head1 SEE ALSO

OMP document OMP/SN/002.

=head1 COPYRIGHT

Copyright (C) 2001-2002 Particle Physics and Astronomy Research Council.
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
along with this program (see SLA_CONDITIONS); if not, write to the 
Free Software Foundation, Inc., 59 Temple Place, Suite 330, 
Boston, MA  02111-1307  USA


=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=cut

1;
