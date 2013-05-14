# @(#)$Ident: VCS.pm 2013-05-14 21:50 pjf ;

package Class::Usul::Build::VCS;

use version; our $VERSION = qv( sprintf '0.20.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Class::Usul::Moose;
use Class::Usul::Constants;
use File::Spec::Functions qw(catdir);
use IPC::Cmd              qw(can_run);

has 'type' => is => 'ro', isa => 'Str';
has 'vcs'  => is => 'ro', isa => 'Object';

around 'BUILDARGS' => sub {
   my ($next, $self, @args) = @_; my $attr = $self->$next( @args );

   my $dir = $attr->{project_dir};

   if (-d catdir( $dir, q(.svn) )) {
      can_run( q(svn) ) or return $attr; # Be nice to CPAN testing

      require SVN::Class;

      $attr->{vcs } = SVN::Class::svn_dir( $dir );
      $attr->{type} = q(svn);
      return $attr;
   }

   if (-d catdir( $dir, q(.git) )) {
      can_run( q(git) ) or return $attr; # Be nice to CPAN testing

      require Git::Class::Worktree;

      $attr->{vcs } = Git::Class::Worktree->new( path => $dir );
      $attr->{type} = q(git);
      return $attr;
   }

   return $attr;
};

sub commit {
   my ($self, $msg) = @_;

   $self->type eq q(git)
      and return $self->vcs->commit( { all => TRUE, message => $msg } );

   return $self->vcs->commit( $msg );
}

sub error {
   my $self = shift; $self->vcs or return 'No VCS';

   $self->type eq q(git) and return $self->vcs->_error;

   return $self->vcs->error;
}

sub repository {
   my $self = shift; $self->vcs or return;

   $self->type eq q(git) and return $self->vcs->git( q(remote) );

   my $info = $self->vcs->info or return;

   return $info->root;
}

sub tag {
   my ($self, $tag) = @_; my $vtag = q(v).$tag; $self->vcs or return;

   $self->type eq q(git) and return $self->vcs->tag( { tag => $vtag } );

   my $repo = $self->repository or return;
   my $from = $repo.SEP.q(trunk);
   my $to   = $repo.SEP.q(tags).SEP.$vtag;
   my $msg  = "Tagging ${vtag}";

   return $self->vcs->svn_run( q(copy), [ q(-m), $msg ], "${from} ${to}" );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 Name

Class::Usul::Build::VCS - Version control system

=head1 Version

This document describes Class::Usul::Build::VCS version v0.20.$Rev: 1 $

=head1 Synopsis

   use Class::Usul::Build::VCS;

   $vcs_object = Class::Usul::Build::VCS->new;

=head1 Description

Proxies methods for either L<SVN::Class> or L<Git::Class::Worktree>
depending on which is being used by the application

=head1 Subroutines/Methods

=head2 commit

   $result = $self->commit( $message );

Commits all outstanding updates with the supplied message

=head2 error

   $error = $self->error;

Returns the last VCS error

=head2 repository

   $uri = $self->repository;

Returns the URI of the VCS repository

=head2 tag

   $self->tag( $tag )

Creates a tagged copy of trunk

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Git::Class::Worktree>

=item L<IPC::Cmd>

=item L<SVN::Class>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Author

Peter Flanigan, C<< <Support at RoxSoft.co.uk> >>

=head1 License and Copyright

Copyright (c) 2013 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
