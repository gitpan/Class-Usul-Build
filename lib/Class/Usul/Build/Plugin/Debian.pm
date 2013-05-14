# @(#)$Ident: Debian.pm 2013-05-14 21:49 pjf ;

package Class::Usul::Build::Plugin::Debian;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.20.%d', q$Rev: 1 $ =~ /\d+/gmx );

use Class::Usul::Constants;
use Class::Usul::Functions qw(throw);
use Debian::Control;
use Debian::Control::Stanza::Binary;
use Debian::Dependency;
use Debian::Rules;
use Email::Date::Format    qw(email_date);
use English                qw(-no_match_vars);
use File::Basename         qw(basename dirname);
use File::Spec::Functions  qw(catdir catfile);
use MRO::Compat;
use Text::Format;
use Try::Tiny;

my %CONFIG =
   ( dh_clean_files => [ qw(build-stamp install-stamp debian) ],
     dh_format_spec => q(Format-Specification: http://svn.debian.org/wsvn/dep/web/deps/dep5.mdwn?op=file&rev=135),
     dh_share_dir   => [ NUL, qw(usr share dh-make-perl) ],
     dh_stdversion  => q(3.9.1),
     dh_ver         => 7,
     dh_ver_extn    => q(-1),
     post_install   => FALSE, );

# Around these M::B actions

sub ACTION_distclean {
   my $self = shift;

   $self->depends_on( q(debianclean) ); $self->next::method();

   return;
}

# New M::B actions

sub ACTION_debian  {
   my $self = shift;

   $ENV{BUILDING_DEBIAN} = TRUE;
   $ENV{DEB_BUILD_OPTIONS} = q(nocheck);

   $self->depends_on( q(debianclean) );
   $self->depends_on( q(install_local_deps) );
   $self->depends_on( q(manifest) );
   $self->depends_on( q(build) );

   try {
      my $cfg = $self->_get_config;

      $self->_ask_questions( $cfg );
      $self->_create_debian_package( $cfg );
   }
   catch { $self->cli->fatal( $_ ) };

   return;
}

sub ACTION_debianclean {
   my $self = shift;

   try   { $self->_debianclean( $self->_get_config ) }
   catch { $self->cli->fatal( $_ ) };

   return;
}

# Private action methods

sub _create_debian_package {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $control = Debian::Control->new;

   $cli->io( $self->_debian_dir )->mkdir( 0755 );
   $cli->io( $self->_debian_file( q(compat) ) )->println( $cfg->{dh_ver} );
   $self->_set_debian_package_defaults( $cfg, $control );
   $self->_add_debian_depends         ( $cfg, $control );
   $self->_create_debian_changelog    ( $cfg, $control );
   $self->_create_debian_copyright    ( $cfg, $control );
   $self->_create_debian_watch        ( $cfg );
   $self->_create_debian_maintainers  ( $cfg );

   my $rules = $self->_create_debian_rules( $cfg );

   # Now that rules are there, see if we need some dependency for them
   $self->_discover_debian_utility_deps( $cfg, $control, $rules );
   $control->write( $self->_debian_file( q(control) ) );

   my $docs = [ $cli->io( [ $self->_main_dir, q(README) ] ) ];

   $self->_update_debian_file_list( $cfg, $control, docs => $docs );

   my $cmd  = "fakeroot dh binary";

   $self->cli_info( $cli->run_cmd( $cmd, { err => q(out) } )->out );
   return;
}

sub _debianclean {
   my ($self, $cfg) = @_;

#  $self->_backup_path( $self->_debian_dir );

   $self->delete_filetree( $_ ) for (@{ $cfg->{dh_clean_files} });

   return;
}

# Private methods

sub _abs_prog_path {
   my ($self, $cfg, $cmd) = @_; my ($prog, @args) = split SPC, $cmd || NUL;

   return join SPC, $self->_bin_file( $cfg, $prog ), @args;
}

sub _add_debian_depends {
   my ($self, $cfg, $control) = @_;

   my $src = $control->source; my $bin = $control->binary->Values( 0 );

   exists $cfg->{debian_depends}
      and $bin->Depends->add( @{ $cfg->{debian_depends} } );

   exists $cfg->{debian_build_depends}
      and $src->Build_Depends->add( @{ $cfg->{debian_build_depends} } );

   exists $cfg->{debian_build_depends_indep}
      and $src->Build_Depends_Indep->add( @{ $cfg->{debian_build_depends_indep} } );

   return;
}

sub _backup_path {
   my ($self, $path) = @_; (defined $path and -e $path) or return;

   my $cli = $self->cli; my $bak = $cli->io( $path.q(.bak) );

   $self->cli_info( "Path exists moving to ${bak}" );

   if ($bak->exists) {
      $self->cli_info( "Overwriting existing ${bak}" );
      $bak->is_dir ? $bak->rmtree : $bak->unlink;
   }

   rename $path, $bak->pathname or throw $ERRNO;
   return;
}

sub _bin_file {
   return $_[ 0 ]->cli->file->absolute( __bin_dir( $_[ 1 ] ), $_[ 2 ] );
}

sub _create_debian_changelog {
   my ($self, $cfg, $control) = @_; my $src = $control->source;

   my $io = $self->cli->io( $self->_debian_file( q(changelog) ) );

   $io->print( sprintf "%s (%s) unstable; urgency=low\n\n",
               $src->Source, $self->dist_version.$cfg->{dh_ver_extn} );
   $io->print( "  * Initial Release.\n\n" );
   $io->print( sprintf " -- %s  %s\n", $src->Maintainer, email_date( time ) );
   return;
}

sub _create_debian_copyright {
   my ($self, $cfg, $control) = @_; my (@res, %licenses);

   my $cli        = $self->cli;
   my $year       = 1900 + (localtime)[ 5 ];
   my $maintainer = $control->source->Maintainer;
   my $license    = $cfg->{meta_keys}->{ $cli->get_meta->license->[ 0 ] }
      or throw 'Unknown copyright license';
   my %fields     = ( Name       => $self->dist_name,
                      Maintainer => $maintainer,
                      Source     => $self->_get_cpan_url( $cfg ) );

   push @res, $cfg->{dh_format_spec};

   for (grep { defined $fields{ $_ } } keys %fields) {
      push @res, "$_: ".$fields{ $_ };
   }

   push @res, NUL, 'Files: *', "Copyright: ${maintainer}";

   ref $license and $license = $license->[ -1 ];

   if ($license ne q(Perl_5)) { $licenses{ $license } = 1 }
   else { $licenses{'Artistic_1_0'} = $licenses{'GPL_1'} = 1 }

   push @res, 'License: '.(join ' or ', keys %licenses);

   # debian/* files information - We default to the module being
   # licensed as the super-set of the module and Perl itself.
   $licenses{'Artistic_1_0'} = $licenses{'GPL_1'} = 1;

   push @res, NUL, 'Files: debian/*', "Copyright: ${year}, ${maintainer}";
   push @res, 'License: '.(join ' or ', keys %licenses);
   push @res, @{ $self->_license_content( \%licenses, $maintainer ) };

   $cli->io( $self->_debian_file( q(copyright) ) )->println( @res );
   return;
}

sub _create_debian_maintainers {
   my ($self, $cfg) = @_; my $cli = $self->cli; $cfg ||= {};

   $cfg->{base} or throw 'Config base directory not set';

   $cli->io     ( $self->_debian_file ( q(postinst) ), q(w) )
       ->println( $self->_shell_script( $cfg, $cfg->{post_install_cmd} ) )
       ->chmod  ( 0755 );


   $cli->io     ( $self->_debian_file ( q(postrm) ), q(w) )
       ->println( $self->_shell_script( $cfg, $self->_postrm_content( $cfg ) ) )
       ->chmod  ( 0755 );
   return;
}

sub _create_debian_rules {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $source = catfile( @{ $cfg->{dh_share_dir} }, q(rules.dh7.tiny) );
   my $path   = $self->_debian_file( q(rules) );
   my $rules  = Debian::Rules->new( $path );

   -e $source or throw "Path ${source} does not exist";
   $self->cli_info( "Using rules ${source}" );
   $rules->read( $source );

   my @lines = @{ $rules->lines }; my $line1 = shift @lines;

   # Stop dh from re-running perl Build.PL and ./Build
   unshift @lines, "\n", "override_dh_auto_configure:\n", "\n",
      "override_dh_auto_build:\n", "\n", $line1;
   $rules->lines( \@lines ); $rules->write;
   chmod 0755, $path or throw $ERRNO;
   return $rules;
}

sub _create_debian_watch {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $io         = $cli->io( $self->_debian_file( q(watch) ) );
   my $version_re = 'v?(\d[\d.-]+)\.(?:tar(?:\.gz|\.bz2)?|tgz|zip)';

   $io->println( sprintf "version=3\n%s   .*/%s-%s\$",
                 $self->_get_cpan_url( $cfg ), $self->dist_name, $version_re );
   return;
}

sub _debian_dir {
   return catdir( $_[ 0 ]->_main_dir, q(debian) );
}

sub _debian_file {
   return catfile( $_[ 0 ]->_debian_dir, $_[ 1 ] );
}

sub _discover_debian_utility_deps {
   my ($self, $cfg, $control, $rules) = @_;

   my $deps = $control->source->Build_Depends;
   my $bin  = $control->binary->Values( 0 );

   $deps->remove( q(quilt), q(debhelper) );

   # Start with the minimum
   $deps->add( Debian::Dependency->new( q(debhelper), $cfg->{dh_ver} ) );

   if ($control->is_arch_dep) { $deps->add( q(perl) ) }
   else { $control->source->Build_Depends_Indep->add( q(perl) ) }

   # Some mandatory dependencies
   my $bin_deps = $bin->Depends;

   not $control->is_arch_dep and $bin_deps += '${shlibs:Depends}';

   $bin_deps += '${misc:Depends}, ${perl:Depends}';
   return;
}

sub _get_config {
   return $_[ 0 ]->next::method( { %CONFIG, %{ $_[ 1 ] || {} } } );
}

sub _get_cpan_url {
    return sprintf "%s/%s/", $_[ 1 ]->{cpan_dists}, $_[ 0 ]->dist_name;
}

sub _get_debian_author {
   # Set author name and email for the debian package.
   my $self = shift; my ($author_name, $author_mail);

   my $dist_author = $self->dist_author->[ 0 ] or throw 'No dist author';

   if ($dist_author =~ m{ \s* (.+?) (?:(?: \s* , \s* C<<)?) \s* < (.+?) > }msx){
      $author_name = defined $1 ? $1 : $dist_author;
      $author_mail = defined $2 ? $2 : NUL;
   }

   return "${author_name} <${author_mail}>";
}

sub _license_content {
   my ($self, $licenses, $maintainer) = @_; my $cli = $self->cli;

   my $formatter = Text::Format->new; my @res = ();

   $formatter->leftMargin( 2 );

   for my $license (keys %{ $licenses }) {
      my $class = q(Software::License::).$license;

      $cli->ensure_class_loaded( $class );

      my $swl  = $class->new( { holder => $maintainer } );
      my $text = $formatter->format( $swl->fulltext );

      $text =~ s{ \A \z }{ .}gmx;
      push @res, NUL, "License: ${license}", $text;
   }

   return \@res;
}

sub _main_dir {
   return ref $_[ 0 ] ? $_[ 0 ]->cli->config->appldir : File::Spec->curdir;
}

sub _postrm_content {
   my ($self, $cfg) = @_;

   # TODO: Add the triggering of the reinstallation of the previous version
   my $cmd  = $self->_abs_prog_path( $cfg, $cfg->{uninstall_cmd} );
   my $subd = basename( $cfg->{base} );
   my $appd = dirname ( $cfg->{base} );
   my $papd = dirname ( $appd        );

   length $appd < 2 and throw "Insane uninstall directory: ${appd}";
   $subd !~ m{ v \d+ \. \d+ p \d+ }mx
      and throw "Path ${subd} does not match v\\d+\\.\\d+p\\d+";

   return [ "${cmd} && \\",
            "   cd ${appd} && \\",
            "   test -d \"${subd}\" && rm -fr ${subd} ; rc=\${?}",
            "[ \${rc} -eq 0 ] && cd ${papd} && test -d \"${appd}\" && \\",
            "   rmdir ${appd} 2>/dev/null", ];
}

sub _set_debian_binary_data {
   my ($self, $control, $pkgname, $arch) = @_; my $bin = $control->binary;

   $bin->FETCH( $pkgname )
      or $bin->Push( $pkgname => Debian::Control::Stanza::Binary->new( {
         Package => $pkgname } ) );

   my $binval = $bin->Values( 0 );

   $binval->Architecture( $arch );

   my $abstract = $self->dist_abstract or throw 'No dist abstract';

   $binval->short_description( $abstract );

   # Only available if we have patched M::B::PodParser
   my $ref  = $self->can( q(dist_description) );
   my $desc = $ref ? $self->$ref() : [];

   $desc = join "\n", grep { not m{ \s+ }msx }
                      map  { s{ [A-Z] [<] ([^>]*) [>] }{$1}gmx; $_ } @{ $desc };
   $desc and $binval->long_description( $desc );
   return $binval;
}

sub _set_debian_package_defaults {
   my ($self, $cfg, $control) = @_;

   my $src = $control->source; my $pkgname = lc $self->dist_name.q(-perl);

#  $pkgname =~ m{ \A lib }mx or $pkgname = "lib${pkgname}";
   $pkgname =~ s{ [^-.+a-zA-Z0-9]+ }{-}gmx;

   $src->Source           ( $pkgname    );
   $src->Section          ( q(perl)     );
   $src->Priority         ( q(optional) );
   $src->Homepage         ( $self->_get_cpan_url( $cfg ) );
   $src->Maintainer       ( $self->_get_debian_author );
   $src->Standards_Version( $cfg->{dh_stdversion} );

   my $binval = $self->_set_debian_binary_data( $control, $pkgname, q(any) );

   $self->cli_info( sprintf "Found %s %s (%s arch=%s)\n",
                     $self->dist_name, $self->dist_version,
                     $pkgname, $binval->Architecture );
   $self->cli_info( sprintf "Maintainer %s\n", $src->Maintainer );
   return;
}

sub _shell_script {
   my ($self, $cfg, $cdr) = @_; $cdr ||= NUL;

   ref $cdr ne ARRAY
      and $cdr = [ $self->_abs_prog_path( $cfg, $cdr ).q(; rc=${?}) ];

   return ('#!/bin/sh', @{ $cdr || [] }, q(exit ${rc:-1}));
}

sub _update_debian_file_list {
   my ($self, $cfg, $control, %p) = @_; my $cli = $self->cli;

   my $src = $control->source; my $pkgname = $src->Source;

   while (my ($file, $new_content) = each %p) {
      @{ $new_content } or next; my (@existing_content, %uniq_content);

      my $pkg_file = $self->_debian_file( $pkgname.q(.).$file );

      if (-r $pkg_file) {
         @existing_content = $cli->io( $pkg_file )->chomp->getlines;

         $uniq_content{ $_ } = 1 for (@existing_content);
      }

      $uniq_content{ $_ } = 1 for (@{ $new_content });

      my $io = $cli->io( $pkg_file );

      for (@existing_content, @{ $new_content }) {
         exists $uniq_content{ $_ } or next;
         delete $uniq_content{ $_ };
         $io->println( $_ );
      }
   }

   return;
}

# Private functions

sub __bin_dir {
   return catdir( $_[ 0 ]->{base}, q(bin) );
}


1;

__END__

=pod

=head1 Name

Class::Usul::Build::Debian - Create a Debian package from a standalone application

=head1 Version

This documents version v0.20.$Rev: 1 $

=head1 Synopsis

   # In your Build.PL file
   use Class::Usul::Build::Debian;

   my $builder = Class::Usul::Build::Debian->new;

   $builder->create_build_script;

   # Then you can type
   perl Build.PL
   ./Build debian

=head1 Description

Builds a Debian package from a Perl application. Most of the code was
robbed from L<DhMakePerl>

=head1 Subroutines/Methods

=head2 ACTION_distclean

=head2 ACTION_debian

=head2 _debian

=head2 ACTION_debianclean

=head2 _debianclean

=head1 Configuration and Environment

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Build>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module.
Please report problems to the address below.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

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
