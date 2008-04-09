package OMP::Translator::SCUBA2;

=head1 NAME

OMP::Translator::SCUBA2 - translate SCUBA2 observations to configure XML

=head1 SYNOPSIS

  use OMP::Translator::SCUBA2;
  $config = OMP::Translator::SCUBA2->translate( $sp );

=head1 DESCRIPTION

Convert SCUBA-2 MSB into a form suitable for observing. This means
XML suitable for the OCS CONFIGURE action.

=cut

use 5.006;
use strict;
use warnings;
use Carp;

use Data::Dumper;

use File::Spec;
use JAC::OCS::Config;
use JAC::OCS::Config::Error qw/ :try /;

use OMP::Config;
use OMP::Error;

use base qw/ OMP::Translator::JCMT /;

=head1 METHODS

=over 4

=item B<wiredir>

Returns the wiring directory that should be used for ACSIS.

  $trans->wiredir();

=cut

{
  my $wiredir;
  sub wiredir {
    $wiredir = OMP::Config->getData( 'scuba2_translator.wiredir' )
      unless defined $wiredir;
    return $wiredir;
  }
}

=item B<handle_special_modes>

Special modes such as POINTING or FOCUS are normal observations that
are modified to do something in addition to normal behaviour. For a
pointing this simply means fitting an offset.

  $cfg->handle_special_modes( \%obs );

Since the Observing Tool is setup such that pointing and focus
observations do not necessarily inherit observing parameters from the
enclosing observation and they definitely do not include a
specification on chopping scheme.

=cut

sub handle_special_modes {
  my $self = shift;
  my $info = shift;

  # The trick is to fill in the blanks

  return;
}

=back

=head1 CONFIG GENERATORS

These routine configure the specific C<JAC::OCS::Config> objects.

=over 4

=item B<frontend_backend_config>

Configure the SCUBA-2 specific instrument XML.

  $trans->frontend_backend_config( $cfg, %$obs );

=cut

sub frontend_backend_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  my $sc = JAC::OCS::Config::SCUBA2->new();

  # start with just a mask
  my %mask = $self->calc_receptor_or_subarray_mask( $cfg, %info );
  $sc->mask(%mask);
  $cfg->scuba2( $sc );
}

=item B<jos_config>

The JOS configurations for SCUBA-2 have little in common with the
ACSIS versions so this is an independent implementation.

  $trans->jos_config( $cfg, %info );

=cut

sub jos_config {
  my $self = shift;
  my $cfg = shift;
  my %info = @_;

  my $jos = new JAC::OCS::Config::JOS();

  # Allowed JOS recipes seem to be
  #   scuba2_scan
  #   scuba2_dream
  #   scuba2_stare
  #   scuba2_skyDip
  #   scuba2_flatField
  #   scuba2_noise

  # Non science observing types
  if ($info{obs_type} =~ /focus/ ) {
    $jos->num_focus_steps( $info{focusPoints} );
    $jos->focus_step( $info{focusStep} );
    $jos->focus_axis( $info{focusAxis} );
  }

  # store it
  $cfg->jos( $jos );

}

=item B<need_offset_tracking>

Returns true if we need to use a particular sub array for this
observation.

  $need = $trans->need_offset_tracking( $cfg, %info );

=cut

sub need_offset_tracking {
  # with only 2 subarrays we can be sure that we are meant to
  # use them
  return 1;
}

=item B<step_time>

Step time for SCUBA-2 is fixed at 200 Hz.

 $rts = $trans->step_time( $cfg, %info );

=cut

sub step_time {
  return 0.005;
}

=item B<velOverride>

SCUBA-2 has no requirement for velocity information so return
empty list.

=cut

sub velOverride {
  return ();
}

=item B<backend>

Returns the backend name. The name is suitable for use in
filenames that are targetted for a specific translator.
SCUBA2 in this case.

=cut

sub backend {
  return "SCUBA2";
}

=back

=head1 CONFIGURATION XML

The format of the configuration XML is outlined in JAC document
OCS/ICD/001.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

Copyright (C) 2007-2008 Science and Technology Facilities Council.
Copyright (C) 2003-2007 Particle Physics and Astronomy Research Council.
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

=cut

1;
