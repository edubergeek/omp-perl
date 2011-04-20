package OMP::FileUtils;

=head1 NAME

OMP::FileUtils - File-related utilities for the OMP.

=head1 SYNOPSIS

  use OMP::FileUtils;

  @files =
    OMP::FileUtils->files_on_disk( 'instrument' => $inst, 'date' => $date );

=head1 DESCRIPTION

This class provides general purpose routines that are used for
handling files for the OMP system.

=cut

use 5.006;
use strict;
use warnings::register;

use File::Basename qw[ fileparse ];
use File::Spec;
use List::MoreUtils qw[ any all ];
use Scalar::Util qw[ blessed ];

use OMP::Error qw[ :try ];
use OMP::Config;
# For logging.
use OMP::Constants qw[ :logging ];
use OMP::General;

our $VERSION = (qw$Revision$)[1];
our $DEBUG = 0;

=head1 METHODS

There are no instance methods, only class (static) methods.

=over 4

=item B<files_on_disk>

For a given instrument and UT date, this method returns a list of
observation files.

  my @files =
    OMP::FileUtils->files_on_disk( 'instrument' => 'CGS4',
                                   'date'       => $date,
                                 );

  my $files =
    OMP::FileUtils->files_on_disk( 'instrument' => 'CGS4',
                                   'date'       => $date,
                                   'run'        => $runnr,
                                 );

  @files =
    OMP::FileUtils->files_on_disk( 'instrument' => 'SCUBA-2',
                                   'date'       => $date,
                                   'subarray'   => $subarray,
                                   'recent'     => 2,
                                 );

The   instrument must be  a string.   The date  must be  a Time::Piece
object.  If the date  is  not passed as   a Time::Piece object then an
OMP::Error::BadArgs error  will be thrown.  The run  number must be an
integer. If the run number is not passed or is zero, then no filtering
by run number will be done.

For SCUBA2 files, a subarray must be specified (from '4a' to '4d', or
'8a' to '8d').

Optionally specify number of files older than new ones on second &
later calls to be returned. On first call, all the files will be
returned.

If called in list context, returns a list of array references. Each
array reference points to a list of observation files for a single
observation. If called in scalar context, returns a reference to an
array of array references.

=cut

sub files_on_disk {
  my ( $class, %arg ) = @_;

  my ( $instrument, $utdate, $runnr, $subarray, $old ) =
    @arg{qw[ instrument date run subarry old ]};

  if( ! UNIVERSAL::isa( $utdate, "Time::Piece" ) ) {
    throw OMP::Error::BadArgs( "Date parameter to OMP::General::files_on_disk must be a Time::Piece object" );
  }

  if( ! defined( $runnr ) ||
      $runnr < 0 ) {
    $runnr = 0;
  }

  my $date = $utdate->ymd;
  $date =~ s/-//g;

  my $sys_config = OMP::Config->new;

  # Retrieve information from the configuration system.
  my $tel = $sys_config->inferTelescope( 'instruments', $instrument );

  my %config =
    (
      telescope  => $tel,
      instrument => $instrument,
      utdate     => $utdate,
      runnr      => $runnr,
      subarray   => $subarray,
    );

  my $directory = $sys_config->getData( 'rawdatadir', %config );
  my $flagfileregexp = $sys_config->getData( 'flagfileregexp',
                                              telescope => $tel,
                                            );

  # getData() throws an exception in the case of missing key.  No point in dying
  # then as default value will be used instead from earlier extraction.
  try {

    $directory = $sys_config->getData( "${instrument}.rawdatadir" , %config );

    $flagfileregexp = $sys_config->getData( "${instrument}.flagfileregexp", %config );
  }
  catch OMP::Error::BadCfgKey with {

    my ( $e  ) = @_;
    throw $e unless $e =~ /^Key.+could not be found in OMP config system/i;
  };

  my ( $use_meta, @return );

  if ( $class->use_raw_meta_opt( $sys_config, %config ) ) {

    @return =
      $class->get_raw_files_from_meta( $sys_config, \%config, $flagfileregexp, $old );

    _track_file( 'returning: ' => @return );
  }
  else {

    @return =
      $class->get_raw_files( $directory,
                              $class->get_flag_files( $directory, $flagfileregexp, $runnr, $old ),
                              $old,
                            );
  }

  return wantarray ? @return : \@return ;
}

sub use_raw_meta_opt {

  my ( $class, $omp_config, %config ) = @_;

  my $meta;
  try {

    $meta = $omp_config
            ->getData( qq[$config{'instrument'}.raw_meta_opt], %config );
  }
  # "raw_meta_opt" may be missing entirely, considered same as a false value.
  catch OMP::Error::BadCfgKey with {

    my ( $e  ) = @_;

    throw $e
      unless $e =~ /^Key.+could not be found in OMP config system/i;
  };

  return !!$meta;
}

sub get_raw_files_from_meta {

  my ( $class, $sys_config, $config, $flag_re, $old ) = @_;

  $old ||=  2 * 4;
  my $old_raw = 2 * $old;

  my $inst = $config->{'instrument'};
  my $meta_dir
    = $sys_config->getData( "${inst}.metafiledir", %{ $config } );

  my @meta = get_meta_files( $sys_config, $config, $flag_re );

  my ( @flag );
  for my $file ( @meta ) {

    # Get flag file list by reading meta files.
    my $flags =
      OMP::General->get_file_contents(  'file'   => $file,
                                        'filter' => $flag_re,
                                      );

    next unless $flags && scalar @{ $flags };

    _track_file( 'flag files: ', @{ $flags } );

    push @flag,
      _get_updated_files( [ map
                            { File::Spec->catfile( $meta_dir, $_ ) }
                            @{ $flags }
                          ]
                        );
  }

  return
    $class->get_raw_files( $meta_dir, [ @flag ], $old, );
}

sub get_meta_files {

  my ( $sys_config, $config, $flag_re ) = @_;

  $flag_re = qr{$flag_re};

  # Get meta file list.
  my $inst = $config->{'instrument'};
  my ( $meta_re, $meta_date_re, $meta_dir )
    = map { $sys_config->getData( "${inst}.${_}", %{ $config } ) }
          qw[ metafileregexp
              metafiledateregexp
              metafiledir
            ];

  my $metas;
  try {

    $metas =
      OMP::General->get_directory_contents( 'dir' => $meta_dir,
                                            'filter' => qr/$meta_date_re/,
                                            'sort' => 1
                                            );
  }
  catch OMP::Error::FatalError with {

    my ( $err ) = @_;
    return
      if $err =~ /n[o']t open directory/i;
  };

  _track_file( 'meta files: ', $metas && ref $metas ? @{ $metas } : () );

  return unless $metas;
  return @{ $metas };
}

sub get_flag_files {

  my ( $class, $dir, $filter, $runnr, $old ) = @_;

  my $flags;
  try {

    $flags =
      OMP::General->get_directory_contents( 'dir' => $dir,
                                            'filter' => $filter
                                          );
  }
  catch OMP::Error::FatalError with {

    my ( $err ) = @_;
    return
      if $err =~ /n[o']t open directory/i;
  };

  # Purge the list if runnr is not zero.
  if ( $runnr && $runnr != 0 ) {

    foreach my $f ( @{ $flags } ) {

      $f =~ /$filter/;
      if( int($1) == $runnr ) {

        $flags = [ $f ];
        last;
      }
    }
  }

  my @updated = _get_updated_files( $flags );

  return [] unless scalar @updated;
  return [ @updated ];
}

{
  my ( %file_time );
  sub _get_updated_files {

    my ( $list ) = @_;

    return unless $list && scalar @{ $list };

    my @send;
    my %mod = _get_mod_epoch( $list );

    while ( my ( $f, $t ) = each %mod ) {

      next
        if exists $file_time{ $f }
        &&        $file_time{ $f }
        && $t <=  $file_time{ $f };

      $file_time{ $f } = $t;
      push @send, $f;
    }

    return unless scalar @send;
    return
      # Sort files by ascending modification times.
      map  { $_->[0] }
      sort { $a->[1] <=> $b->[1] }
      map  { [ $_ , $mod{ $_ } ] }
      @send;
  }
}

# Go through each flag file, open it, and retrieve the list of files within it.
{
  my ( %raw );
  sub get_raw_files {

    my ( $class, $dir, $flags, $old ) = @_;

    return
      unless $flags && scalar @{ $flags };

    my @raw;

    foreach my $file ( @{ $flags } ) {

      # If the flag file size is 0 bytes, then we assume that the observation file
      # associated with that flag file is of the same naming convention, removing
      # the dot from the front and replacing the .ok on the end with .sdf.
      if ( -z $file ) {

        my $raw = $class->make_raw_name_from_flag( $file );

        next unless _sanity_check_file( $raw );

        push @raw, [ $raw ];
        next;
      }

      my ( $lines, $err );
      try {

        $lines = OMP::General->get_file_contents( 'file' => $file );
      }
      catch OMP::Error::FatalError with {

        ( $err ) = @_;
        throw $err
          unless $err =~ /^Cannot open file/i;
      };

      my @checked;
      for my $file ( @{ $lines } ) {

        my $f = File::Spec->catfile( $dir, $file );

        next if exists $raw{ $f };
        next unless _sanity_check_file( $f );

        undef $raw{ $f };
        push @checked, $f;
      }
      push @raw, [ @checked ];
    }

    return @raw;
  }
}

sub make_raw_name_from_flag {

  my ( $class, $flag ) = @_;

  my $suffix = '.sdf';

  my ( $raw, $dir ) = fileparse( $flag, '.ok' );
  $raw =~ s/^[.]//;

  return File::Spec->catfile( $dir, $raw . $suffix );
}


=item B<merge_dupes>

Given an array of hashes containing header object, filename and
frameset, merge into a hash indexed by OBSID where headers have been
merged and filenames have been combined into arrays.

  $merged = OMP::FileUtils->merge_dupes( @unmerged );

In the returned merged version, header hash item will contain an
Astro::FITS::Header object if the supplied entry in @unmerged was a
simple hash reference.

Input keys:

   header - reference to hash or an Astro::FITS::Header object
   filename - single filename (optional)
   frameset - optional Starlink::AST frameset

If the 'filename' is not supplied yet a header translation reports
that FILENAME is available, the value will be stored from the
translation into the filename slot.

Output keys

   header - Astro::FITS::Header object
   filenames - reference to array of filenames
   frameset - optional Starlink::AST frameset (from first in list)
   obsidss_files - hash of files indexed by obsidss

=cut

sub merge_dupes {

  my $self = shift;

  # Take local copies so that we can add information without affecting caller
  my @unmerged = map { {%$_} } @_;

  my %unique;
  for my $info ( @unmerged ) {

    # First need to work out which item corresponds to the unique observation ID
    # We do this via header translation. Since we can in principal have multiple
    # instruments we have to redetermine the class each time round the loop.

    # Convert fits header to hash if required
    my $hdr = $info->{header};
    if (blessed($hdr)) {
      tie my %header, ref($hdr), $hdr;
      $hdr = \%header;
    } else {
      # convert the header hash to a Astro::FITS::Header object so that we can easily
      # merge it later
      $info->{header} = Astro::FITS::Header->new( Hash => $hdr );
    }
    my $class;

    eval {
      $class = Astro::FITS::HdrTrans::determine_class( $hdr, undef, 1);
    };
    if ( $@ ) {

      warn sprintf "Skipped '%s' due to: %s\n",
        $info->{'filename'},
        $@;
    }

    next unless $class;

    my $obsid = $class->to_OBSERVATION_ID( $hdr, $info->{frameset} );

    # check for translated filename
    if (!exists $info->{filename}) {
      my $filename = $class->to_FILENAME( $hdr );
      if (defined $filename) {
        $info->{filename} = $filename;
      }
    }

    # Keep the obsidss around (assume only a single one from a row)
    if ($class->can("to_OBSERVATION_ID_SUBSYSTEM")) {
      my $obsidss = $class->to_OBSERVATION_ID_SUBSYSTEM( $hdr );
      $info->{obsidss} = $obsidss->[0]
	if defined $obsidss && ref($obsidss) && @$obsidss;
    }

    # store it on hash indexed by obsid
    $unique{$obsid} = [] unless exists $unique{$obsid};
    push(@{$unique{$obsid}}, $info);
  }

  # Now go through again and merge the headers and filename information for multiple files
  # but identical obsid.
  for my $obsid (keys %unique) {
    # To simplify syntax get array of headers and filenames
    my (@fits, @files, $frameset, %obsidss_files);
    for my $f (@{$unique{$obsid}}) {
      push(@fits, $f->{header});
      push(@files, $f->{filename});
      if (exists $f->{obsidss}) {
	my $key = $f->{obsidss};
	$obsidss_files{$key} = [] unless exists $obsidss_files{$key};
	push(@{$obsidss_files{$key}}, $f->{filename});
      }
      $frameset = $f->{frameset} if defined $f->{frameset};
    }

    # Merge if necessary (shift off the primary)
    my $fitshdr = shift(@fits);
    #    use Data::Dumper; print Dumper($fitshdr);
    if (@fits) {
      # need to merge
      #      print "FITS:$_\n" for @fits;
      my ( $merged, @different ) = $fitshdr->merge_primary( { merge_unique => 1 }, @fits );
      #      print Dumper(\@different);

      $merged->subhdrs( @different );
      #      print Dumper({merged => $merged, different => \@different});
      $fitshdr = $merged;
    }

    # Some queries result in duplicate rows for filename so uniqify
    # Do not use a hash directly to get the list because that would scramble
    # the original order and we get upset when the OBSIDSS does not match the filename.
    my %files_uniq;
    my @compressed;
    for my $f (@files) {
      if (!exists $files_uniq{$f}) {
        $files_uniq{$f}++;
        push(@compressed, $f);
      }
    }
    @files = @compressed;

    $unique{$obsid} = {
                       header => $fitshdr,
                       filenames => \@files,
		       obsidss_files => \%obsidss_files,
                       frameset => $frameset,
                      };
  }

  return unless scalar %unique;
  return { %unique };
}


=item B<merge_dupes_no_fits>

Merges given list of hash references of database rows into a hash
with OBSIDs as keys.  Filenames are put in its own key-value pair
('filenames' is the key & value is an array reference).

  $merged = OMP::FileUtils->merge_dupes_no_fits( @unmerged );

Input keys:

   header - header hash reference

Output keys

   header - header hash reference
   filenames - reference to array of filenames

=cut

sub merge_dupes_no_fits {

  my $self = shift;

  # Take local copies so that we can add information without affecting caller
  my @unmerged = map { { %$_ } } @_;

my $t_merge_nofits = [ Time::HiRes::gettimeofday() ];

  my %unique;
  for my $info ( @unmerged ) {

    next
      unless $info
      && keys %{ $info } ;

    # Need to get a unique key via header translation
    my $hdr = $info->{header};
    my $class;
    eval {
      $class = Astro::FITS::HdrTrans::determine_class( $hdr, undef, 1);
    };
    if ( $@ ) {

      warn sprintf "Skipped '%s' due to: %s\n",
        $info->{'filename'},
        $@;
    }

    next unless $class;

    my $obsid = $class->to_OBSERVATION_ID( $hdr, $info->{frameset} );

    # Keep the obsidss around (assume only a single one from a row)
    if ($class->can("to_OBSERVATION_ID_SUBSYSTEM")) {
      my $obsidss = $class->to_OBSERVATION_ID_SUBSYSTEM( $hdr );
      $info->{obsidss} = $obsidss->[0]
	if defined $obsidss && ref($obsidss) && @$obsidss;
    }

    push @{ $unique{ $obsid } }, $info;
  }

  # Merge the headers and filename information for multiple files but identical
  # sorting key.
  for my $key ( keys %unique ) {

    my $headers = $unique{ $key };

    # Collect ordered, unique file names.
    my ( @file, %seen, %obsidss_files );
    for my $h ( @{ $headers } ) {

      next
        unless exists $h->{'header'}{'FILE_ID'}
            && $h->{'header'}{'FILE_ID'};

      my $thisfile = delete $h->{header}->{FILE_ID};
      my @newfiles = (ref $thisfile ? @$thisfile : $thisfile);
      push @file, @newfiles;
      if (exists $h->{obsidss}) {
	my $key = $h->{obsidss};
	$obsidss_files{$key} = [] unless exists $obsidss_files{$key};
	push(@{$obsidss_files{$key}}, @newfiles);
      }
    }

    @file = grep { ! $seen{ $_ }++ } @file;

    # Merege rest of headers.

    $unique{ $key } =
      { 'header'    => _merge_header_hashes( $headers ),
        'filenames' => [ @file ],
	'obsidss_files' => \%obsidss_files,
      };
  }

  return unless scalar %unique;
  return { %unique };
}


=item B<_merge_header_hashes>

Given a array reference of hash references (with "header" as the key),
merges them into a hash reference.  If any of the values differ for a
given key (database table column), all of the values appear in
"SUBHEADERS" array reference of hash references.

  $merged =
    _merge_header_hashes( [ { 'header' => { ... } },
                            { 'header' => { ... } },
                          ]
                        );

=cut

sub _merge_header_hashes {

  my ( $list ) = @_;

  return
    unless $list && scalar @{ $list };

  my @list = @{ $list };

  my %common;
  # Special case of a single hash reference.
  my $first = $list[0];
  %common  = %{ $first } if $first && ref $first;

  return delete $common{'header'}
    if 1 == scalar @list;

  # Rebuild.
  my %collect = _value_to_aref( @list );

  for my $k ( keys %collect ) {

    next if 'subheaders' eq lc $k;

    my @val   = @{ $collect{ $k } };
    my $first = ( grep{ defined $_ && length $_ } @val )[0];
    my $isnum = Scalar::Util::looks_like_number( $first );

    if (     ( all { ! defined $_ } @val )
          || ( $isnum && all { $first == $_ } @val )
          || ( defined $first && all { $first eq $_ } @val )
        ) {

      $common{'header'}->{ $k } = $first;
      next;
    }

    delete $common{'header'}->{ $k };
    for my $i ( 0 .. scalar @val - 1 ) {

      $common{'header'}->{'SUBHEADERS'}->[ $i ]->{ $k } = $val[ $i ];
    }
  }

  return delete $common{'header'};
}

sub _value_to_aref {

  my ( @list ) = @_;

  my %hash;
  for my $href ( @list ) {

    while ( my ( $k, $v ) = each %{ $href->{'header'} } ) {

      push @{ $hash{ $k } }, $v;
    }
  }
  return %hash;
}

sub _sanity_check_file {

  my ( $file, $no_warn ) = @_;

  my $read      = -r $file;
  my $exist     = -e _;
  my $non_empty = -s _;

  return 1 if $read && $non_empty;

  return if $no_warn;

  my $text =
    ! $exist
    ? 'does not exist'
    : ! $read
      ? 'is not readable'
      : ! $non_empty
        ? 'is empty'
        : 'has some UNCLASSIFIED PROBLEM'
        ;

  OMP::General->log_message( qq[$file $text (listed in flag file), skipped\n],
                              OMP__LOG_WARNING
                            );

  return;
}

# Given a hash of array reference of file paths and the number of old
# files to return in addition to new ones, returns a list of files
# filerted by recent modification time.
#
{
  my ( %called );

  # It stores time when it was last called; returns only those files which have
  # modification time greater or equal to last called time.  On the first call,
  # it returns all the files.
  sub _get_recent {

    my ( %arg ) = @_;

    my ( $files, $old, $type ) = @arg{qw[files old type]};
    $type ||= '<default>';

    _track_file( 'type: ' => $type );

    return $files unless $old && $old > 0;

    # On first run, every file is a recently updated file.
    unless ( $called{ $type } ) {

      $called{ $type } = time();
      return $files;
    }

    my $last = $called{ $type };

    _track_file( 'time, last: ' => $last );

    # For future calls.
    $called{ $type } = time();

    my %time = _get_mod_epoch( [ map { ref $_ ? @{ $_ } : $_ } @{ $files } ] )
      or return [];

    #_track_file( 'file time: ',
    #              map { $_ . ' : ' . $time{ $_ } } sort keys %time
    #            );

    my ( @keep, @old );
    for my $time ( sort { $a <=> $b } values %time ) {

      if ( $time >= $last ) {

        push @keep, $time;
        next;
      }
      push @old, $time;
    }

    # Merge older file list.
    if ( scalar @old && $type =~ m/\b(?:flag|raw)/i )  {

      $old = 1 if ! $old || $old < 0;

      @keep = ( reverse( ( reverse @old )[ 0 .. $old - 1 ] ), @keep );
    }

    return [] unless scalar @keep;

    my @out;
    while ( my ( $file, $mod ) = each %time ) {

      push @out, $file
        if any { $mod == $_ } @keep;
    }

    _track_file( 'returning recent: ' => @out );

    return [ @out ] if scalar @out;
    return [];
  }
}

sub _get_mod_epoch {

  my ( $files ) = @_;

  my %time;
  for my $f ( map { ref $_ ? @{ $_ } : $_ }  @{ $files } ) {

    my ( $mod ) = ( stat $f )[9]
      or do {
              warn "Could not get modification time of '$f': $!\n";
              next;
            };

    $time{ $f } = $mod;
  }
  return %time;
}

sub _track_file {

  return unless $DEBUG;

  my ( $label, @descr ) = @_;

  require Log::Log4perl;

  my $log = Log::Log4perl->get_logger( '' );
  $log->debug( $label, scalar @descr ? join( "\n  ", @descr ) : '<none>' );
  return;
}

=back

=head1 AUTHORS

=over 4

=item *

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=item *

Anubhav E<lt>a.agarwal@jach.hawaii.eduE<gt>

=back

=head1 COPYRIGHT

Copyright (C) 2006-2009 Science and Technology Facilities Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
USA

=cut

1;
