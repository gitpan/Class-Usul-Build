# @(#)$Ident: Questions.pm 2013-06-25 22:59 pjf ;

package Class::Usul::Build::Questions;

use namespace::sweep;
use version; our $VERSION = qv( sprintf '0.23.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Class::Usul::Constants;
use Class::Usul::Functions  qw( class2appdir emit throw );
use Class::Usul::Types      qw( ArrayRef HashRef Object );
use File::Spec::Functions   qw( catdir );
use Moo;

has 'builder'           => is => 'ro', isa => Object, required => TRUE,
   handles              => { cli          => q(cli),
                             dist_version => q(_dist_version),
                             module_name  => q(module_name) };

has 'config_attributes' => is => 'ro', isa => ArrayRef,
   default              => sub {
      [ qw(path_prefix ver phase install post_install built) ] };

has 'paragraph'         => is => 'ro', isa => HashRef,
   default              => sub { { cl => TRUE, fill => TRUE, nl => TRUE } };

sub q_built {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $prefix = $cfg->{path_prefix} or throw 'No path_prefix';

   $cfg->{base} = catdir( $prefix, class2appdir $self->module_name,
                          q(v).$cfg->{ver}.q(p).$cfg->{phase} );
   emit;
   return TRUE;
}

sub q_install {
   my ($self, $cfg) = @_; my $cli = $self->cli; my $text;

   my $install = $cfg->{install} || TRUE;

   $text  = 'Running Module::Build install may require superuser privilege ';
   $text .= 'to create directories. Depends on the path prefix';

   $cli->output( $text, $self->paragraph );

   return $cli->yorn( 'Run Module::Build install', $install, TRUE, 0 );
}

sub q_path_prefix {
   my ($self, $cfg) = @_; my $cli = $self->cli; my $text;

   my $prefix = catdir( @{ $cfg->{path_prefix} || [] } ) || NUL;

   $text  = 'Where in the filesystem should the application install to. ';
   $text .= 'Application name is automatically appended to the prefix';

   $cli->output( $text, $self->paragraph );

   return $cli->get_line( 'Enter install path prefix', $prefix, TRUE, 0 );
}

sub q_phase {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $phase = $cfg->{phase} || PHASE; my $text;

   $text  = 'Phase number determines at run time the purpose of the ';
   $text .= 'application instance, e.g. live(1), test(2), development(3)';
   $cli->output( $text, $self->paragraph );
   $phase = $cli->get_line( 'Enter phase number', $phase, TRUE, 0 );
   $phase =~ m{ \A \d+ \z }mx
      or throw "Phase value ${phase} bad (not an integer)";

   return $phase;
}

sub q_post_install {
   my ($self, $cfg) = @_; my $cli = $self->cli; my $text;

   my $run = defined $cfg->{post_install} ? $cfg->{post_install} : TRUE;

   $text  = 'Execute post installation commands. These may take ';
   $text .= 'several minutes to complete';
   $cli->output( $text, $self->paragraph );

   return $cli->yorn( 'Post install commands', $run, TRUE, 0 );
}

sub q_ver {
   my $self = shift; (my $ver = $self->dist_version) =~ s{ \A v }{}mx;

   my ($major, $minor) = split m{ \. }mx, $ver;

   return "${major}.${minor}";
}

1;

__END__

=pod

=head1 Name

Class::Usul::Build::Questions - Things to ask when Build runs install

=head1 Version

Describes Class::Usul::Build::Questions version v0.23.$Rev: 1 $

=head1 Synopsis

=head1 Description

All question methods are passed C<$config> and return the new value
for one of it's attributes

=head1 Configuration and Environment

Edits and stores config information in the file F<build.json>

Defines the following attributes

=over 3

=item C<builder>

=item C<config_attributes>

=item C<paragraph>

=back

=head1 Subroutines/Methods

=head2 q_built

Always returns true. This dummy question is used to trigger the suppression
of any further questions once the build phase is complete

=head2 q_install

Do we run M::B install?

=head2 q_path_prefix

Prompt for the installation prefix. The application name and version
directory are automatically appended. If the installation style is
B<normal>, the all of the application will be installed to this
path. The default is F</opt>. If the installation style is B<perl>
then only the "var" data will be installed to this path. The default is
F</var/www>

=head2 q_post_install

Do we run the post installation commands?

=head2 q_phase

The phase number represents the reason for the installation. It is
encoded into the name of the application home directory. At runtime
the application will load some configuration data that is dependent
upon this value

=head2 q_ver

Dummy question returns the version part of the installation directory

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
