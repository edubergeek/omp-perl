package OMP::Translator::ACSIS;

=head1 NAME

OMP::Translator::ACSIS - translate ACSIS heterodyne observations to Configure XML

=head1 SYNOPSIS

  use OMP::Translator::ACSIS;
  $config = OMP::Translator::ACSIS->translate( $sp );

=head1 DESCRIPTION

Convert ACSIS MSB into a form suitable for observing. This means
XML suitable for the OCS CONFIGURE action.

=cut

use 5.006;
use strict;
use warnings;
use Carp;
use Time::HiRes qw/ gettimeofday /;
use Time::Piece qw/ :override /;

use OMP::Error;

use base qw/ OMP::Translator /;

# Unix directory for writing configs
# Should be in config system
our $TRANS_DIR = "/jcmtdata/orac_data/configs";

# Debugging messages
our $DEBUG = 0;

=head1 METHODS

=over 4

=item B<translate>

Convert the science program object (C<OMP::SciProg>) into
a observing sequence understood by the instrument data acquisition
system (Configure XML).

  $xml = OMP::Translate->translate( $sp );
  $data = OMP::Translate->translate( $sp, 1);
  @data = OMP::Translate->translate( $sp, 1);

By default returns the name of a XML file. If the optional second
argument is true, returns the contents of the XML as a single string.

Backup files are also written that are timestamped to prevent
overwriting.  An accuracy of 1 milli second is used in forming the
unique names.

=cut

sub translate {
  my $self = shift;
  my $sp = shift;
  my $asdata = shift;

  # See how many MSBs we have (after pruning)
  my @msbs = $self->PruneMSBs($sp->msb);

  # Project
  my $projectid = $sp->projectID;

  # Now unroll the MSB into constituent observations details
  my @configs;

  # Need to put DTD in here
  my $xml = "<OCS_CONFIG>\n";

  # First, write the TCS_CONFIG
  $xml .= $self->tcs_config();

  # BASE and REFERENCE positions

  # Then obsArea

  # FRONTEND_CONFIG

  # ACSIS_CONFIG

  # HEADER_CONFIG

  # End
  $xml .= "</OCS_CONFIG>\n";

  # Store the completed config
  push(@configs, $xml,$xml);

  # Return or write
  if ($asdata) {
    # Return XML as a string
    return @configs;
  } else {
    # Write the XML configs to disk

    # The interface currently suggests that I write one copy into TRANS_DIR
    # itself and another copy of the XML file into each of the directories
    # found in TRANS_DIR
    opendir my $dh, $TRANS_DIR || 
      throw OMP::Error::FatalError("Error opening translation output directory $TRANS_DIR: $!");

    # Get all the dirs (making sure current dir is first in the list)
    # except hidden dirs [assume unix hidden definition XXX]
    my @dirs = (File::Spec->curdir, 
		grep { -d File::Spec->catdir($TRANS_DIR,$_) && $_ !~ /^\./ } readdir($dh));

    # Format is acsis_YYYYMMDD_HHMMSSmmm
    #  where mmm is milliseconds
    my @filenames;
    for (@configs) {
      my ($sec, $mic_sec) = gettimeofday();
      my $ut = gmtime( $sec );

      # Rather than worry that the computer is so fast in looping that we might
      # reuse milli-seconds (and therefore have to check that we are not opening
      # a file that has previously been created) micro-seconds in the filename
      my $cname = "acsis_". $ut->strftime("%Y%m%d_%H%M%S") .
	"_".sprintf("%06d",$mic_sec) .
	  ".xml";

      my $storename;
      for my $dir (@dirs) {

	my $fullname = File::Spec->catdir( $TRANS_DIR, $dir, $cname );
	print "Writing config to $fullname\n";

	# First time round, store the filename for later return
	$storename = $fullname unless defined $storename;

	# Open it [without checking to see if we are clobbering a pre-existing file]
	open my $fh, "> $fullname" || 
	  throw OMP::Error::FatalError("Error opening config output file $fullname: $!");
	print $fh $xml;
	close ($fh) ||
	  throw OMP::Error::FatalError("Error closing config output file $fullname: $!");

      }

      # Note that we currently store full path to the file in TRANS_DIR and not
      # the files in subdirs
      push(@filenames, $storename);
    }
    return @filenames;
  }

}

=item B<debug>

Method to enable and disable global debugging state.

  OMP::Translator::DAS->debug( 1 );

=cut

sub debug {
  my $class = shift;
  my $state = shift;

  $DEBUG = ($state ? 1 : 0 );
}

=item B<transdir>

Override the translation directory.

  OMP::Translator::DAS->transdir( $dir );

=cut

sub transdir {
  my $class = shift;
  if (@_) {
    my $dir = shift;
    $TRANS_DIR = $dir;
  }
  return $TRANS_DIR;
}

=back

=head1 CONFIG GENERATORS

These routines generate the XML for individual config sections of the global configure.

=over 4

=item B<tcs_config>

TCS configuration XML.

  $tcsxml = $TRANS->tcs_config( %info );

=cut

sub tcs_config {
  my $class = shift;
  my %info = @_;

  return "<TCS_CONFIG></TCS_CONFIG>\n";

}



=back

=head1 NOTES

Usually called indirectly from L<OMP::Translator|OMP::Translator>.

=head1 CONFIGURATION XML

The format of the configuration XML is outlined in JAC document
OCS/ICD/001.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright 2003-2004 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=head1 TODO

The following infrastructure needs to be written for the ACSIS translator:

TCS_CONFIG

 - Need to be able to write TOML::TCS data as well as read it.
   Essentially should become a way of stringifying a Astro::Coords
   object rather than attempting to fudge the pre-existing XML.
   TOML::TCS will consist of hash of Astro::Coords indexed by
   the TAG name. The XML will no longer be retained but will
   be generated on demand.

   This therefore requires that an Astro::Coords object can represent
   the contents of the <BASE> element. This means offsets and also
   things like parallax, epoch, proper motion. For the offsets in
   particular, we could compromise and store them in the TOML::TCS
   object itself but that seems a bit odd since the API would then
   have to include a method for fetching offsets by tag name.

     + The OT does not allow offsets in BASE positions.
       but it does allow offsets in REFERENCE positions.

   Velocity is the great unknown here since the implication is that
   we need an Astro::RadialVelocity object that represents a radial
   velocity to be associated with our Astro::Coords object. Does the
   Astro::RadialVelocity object also need a Astro::Telescope object or
   can it get away with using the one associated with Astro::Coords?

   Step 1:

    - Write simple Astro::RadialVelocity

           $v = new Astro::RadialVelocity( frame => 'LSR',
                                           vdefn => 'radio',
                                           velocity => 55, # km/s
                                         #  redshift => 3.4,
                                         );

    - Support EPOCH, PARALLAX, PM1,PM2  in Astro::Coords   [DONE]

    - Include offsets somewhere (at least in TOML::TCS but that has
      API bloat consequences)

   Step 2:

    Need to construct the obsArea section. This should be fairly
    straightforward and will have to be constructed using a combination
    of SpIterRasterObs (etc) and SpIterOffset. Will probably need
    to have a lookup table of position angles that are valid for
    each instrument when scanning.

FE_CONFIG

    - This all comes from SpInstHeterodyne

ACSIS_CONFIG

    - This will need to create the spectral window

=cut

1;
