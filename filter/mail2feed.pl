#!/local/perl/bin/perl -XT

BEGIN { $ENV{LANG} = "C" }

BEGIN { $ENV{SYBASE} = "/local/progs/sybase"
	  if $^O eq "solaris"; }

BEGIN { $ENV{PATH} = "/bin:/usr/bin:/usr/local/bin"; }

use strict;
use lib "/jac_sw/omp/msbserver";
use Mail::Audit;

my $mail = new Mail::Audit(
			   loglevel => 4,
			   log => "/tmp/omp-mailaudit.log",
			  );

# Look for project ID
# Note that the act of searching for the projectid forces the
# project ID to become a header itself.
$mail->reject("Sorry. Could not discern project ID from the subject line.")
  unless $mail->projectid;

# Look for spam
$mail->reject("Sorry. This email looks like spam. Rejecting.")
  if $mail->get("X-Spam-Status") =~ /^Yes/;


# looks like we can accept this
$mail->accept_feedback;


exit;

# Simply have to place new routines in the Mail::Audit package since
# we are not able to subclass.
package Mail::Audit;

# Process OMP feedback mail messages
use base qw/ Mail::Audit/;
use OMP::FBServer;
use OMP::General;
use OMP::User;
use OMP::UserServer;

# Accept a message and send it to the feedback system
sub accept_feedback {
  my $self = shift;

  Mail::Audit::_log(1,"Accepting");

  # Get the information we need
  my $from = $self->get("from");
  my $srcip = (  $from =~ /@(.*)\b/ ? $1 : $from );
  my $subject = $self->get("subject");
  my $text = join('',@{ $self->body });
  my $project = $self->get("projectid");
  chomp($project); # header includes newline

  # Try to guess the author
  my $author_guess = OMP::User->extract_user_from_email( $from );

  my $author;
  if ($author_guess) {
    my $userid = $author_guess->userid;
    my $email = $author_guess->email;

    # Attempt to retrive user object from the user DB.
    # Try the inferred user ID first, then the email address.

    $author = OMP::UserServer->getUser($userid);

    if (! $author) {
      my $query = "<UserQuery><email>$email</email></UserQuery>";
      my $users = OMP::UserServer->queryUsers($query, 'object');

      if ($users->[0]) {
	$author = $users->[0];
	Mail::Audit::_log(1,"Determined OMP user by email address: [EMAIL=".
			  $author->email."]");
      }
    }
  }

  if ($author) {
    Mail::Audit::_log(1,"Determined OMP user: $author [ID=".
		      $author->userid."]");
  } else {
    Mail::Audit::_log(1,"Unable to determine OMP user from From address");
  }

  # Need to translate the from address to a valid OMP user id
  # if possible. For now we have to just use undef
  Mail::Audit::_log(1,"Sending to feedback system with Project $project");

  # Contact the feedback system
  OMP::FBServer->addComment( $project, {
					author => $author,
					program => $0,
					subject => $subject,
					sourceinfo => $srcip,
					text => $text,
				       });

  Mail::Audit::_log(1, "Sent to feedback system with Project $project");

  # Exit after delivery if required
  if (!$self->{noexit}) {
    Mail::Audit::_log(2,"Exiting with status ".Mail::Audit::DELIVERED);
    exit Mail::Audit::DELIVERED;
  }

}

# Determine the project ID from the subject and
# store it in the mail header
# Return 1 if subject found, else false
sub projectid {
  my $self = shift;
  my $subject = $self->get("subject");

  # Attempt to match
  my $pid = OMP::General->extract_projectid( $subject );
  if (defined $pid) {
    $self->put_header("projectid", $pid);
    Mail::Audit::_log(1, "Project from subject: $pid");
    return 1;
  } else {
    Mail::Audit::_log(1, "Could not determine project from subject line");
    return 0;
  }

}


__END__
=head1 NAME

mail2feedback.pl - Forward mail message to OMP feedback system

=head1 SYNOPSIS

  cat mailmessage | mail2feedback.pl

=head1 DESCRIPTION

This program reads in mail messages from standard input, determines
the project ID from the subject line and forwards the message to
the OMP feedback system.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2002-2005 Particle Physics and Astronomy Research Council.
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

