# @(#)$Ident: InstallActions.pm 2013-06-25 23:00 pjf ;

package Class::Usul::Build::InstallActions;

use namespace::sweep;
use version; our $VERSION = qv( sprintf '0.22.%d', q$Rev: 2 $ =~ /\d+/gmx );

use Class::Usul::Constants;
use Class::Usul::Functions  qw( class2appdir );
use Class::Usul::Types      qw( ArrayRef Object );
use File::Spec::Functions   qw( catdir );
use Moo;

has 'actions' => is => 'ro', isa => ArrayRef,
   default    => sub { [ qw(create_dirs create_files copy_files edit_files) ] };

has 'builder' => is => 'ro', isa => Object, required => TRUE,
   handles    => [ qw(base_dir cli destdir install_destination
                      cli_info module_name) ];

sub copy_files { # Copy some files without overwriting
   my ($self, $cfg) = @_; my $cli = $self->cli;

   for my $pair (@{ $cfg->{copy_files} }) {
      my $from = $cli->file->absolute( $self->base_dir, $pair->{from} );
      my $to   = $cli->file->absolute( $self->_get_dest_base( $cfg ),
                                       $pair->{to} );

      ($from->is_file and not $to->exists) or next;
      $self->cli_info( "Copying ${from} to ${to}" );
      $from->copy( $to )->chmod( 0640 );
   }

   return;
}

sub create_dirs { # Create some directories that don't ship with the distro
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $base = $self->_get_dest_base( $cfg );

   for my $io (map { $cli->file->absolute( $base, $_ ) }
               @{ $cfg->{create_dirs} }) {
      if ($io->is_dir) { $self->cli_info( "Directory ${io} exists" ) }
      else { $self->cli_info( "Creating ${io}" ); $io->mkpath( oct q(02750) ) }
   }

   return;
}

sub create_files { # Create some empty log files
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $base = $self->_get_dest_base( $cfg );

   for my $io (map { $cli->file->absolute( $base, $_ ) }
               @{ $cfg->{create_files} }){
      unless ($io->is_file) { $self->cli_info( "Creating ${io}" ); $io->touch }
   }

   return;
}

sub edit_files {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $base = $self->_get_dest_base( $cfg );
   # Fix hard coded path in suid program
   my $io   = $cli->io( [ $base, q(bin), $cli->config->prefix.q(_admin) ] );
   my $that = qr( \A use \s+ lib \s+ .* \z )msx;
   my $this = 'use lib q('.catdir( $cfg->{base}, q(lib) ).");\n";

   if ($io->is_file) {
      $self->cli_info( "Editing ${io}" );
      $io->substitute( $that, $this )->chmod( 0555 );
   }

   # Pointer to the application directory in /etc/default/<app dirname>
   $io   = $cli->io( [ $base, qw(var etc etc_default) ] );
   $that = qr( \A APPLDIR= .* \z )msx;
   $this = q(APPLDIR=).$cfg->{base}."\n";

   if ($io->is_file) {
      $self->cli_info( "Editing ${io}" );
      $io->substitute( $that, $this )->chmod( 0644 );
   }

   return;
}

# Private methods
sub _get_dest_base {
   my ($self, $cfg) = @_;

   return $self->destdir ? catdir( $self->destdir, $cfg->{base} )
                         : $cfg->{base};
}

1;

__END__

=pod

=head1 Name

Class::Usul::Build::InstallActions - Things to do after Build install

=head1 Version

Describes Class::Usul::Build::InstallActions version v0.22.$Rev: 2 $

=head1 Synopsis

=head1 Description

Additional actions to perform as part of the application installation

=head1 Configuration and Environment

=over 3

=item C<actions>

=item C<builder>

=back

=head1 Subroutines/Methods

All action methods are passed C<$config>

=head2 copy_files

Copies files as defined in the C<< $config->{copy_files} >> attribute.
Each item in this list is a hash ref containing I<from> and I<to> keys

=head2 create_dirs

Create the directory paths specified in the list
C<< $config->{create_dirs} >> if they do not exist

=head2 create_files

Create the files specified in the list
C<< $config->{create_files} >> if they do not exist

=head2 edit_files

Fix a couple of hard coded paths to point to the current install path

=head2 link_files

Creates some symbolic links

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Moose>

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
