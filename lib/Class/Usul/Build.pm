# @(#)$Ident: Build.pm 2013-05-21 12:24 pjf ;

package Class::Usul::Build;

use 5.01;
use strict;
use warnings;
use feature                 qw(state);
use version; our $VERSION = qv( sprintf '0.21.%d', q$Rev: 1 $ =~ /\d+/gmx );
use parent                  qw(Module::Build);
use lib;

use Class::Usul::Build::InstallActions;
use Class::Usul::Build::Questions;
use Class::Usul::Constants;
use Class::Usul::Functions  qw(classdir env_prefix emit throw);
use Class::Usul::Programs;
use Class::Usul::Time       qw(time2str);
use Config;
use English                 qw(-no_match_vars);
use File::Basename          qw(dirname);
use File::Copy              qw(copy);
use File::Find              qw(find);
use File::Spec::Functions   qw(catdir catfile updir);
use Module::Metadata;
use MRO::Compat;
use Perl::Version;
use Scalar::Util            qw(blessed);
use Try::Tiny;

if ($ENV{AUTOMATED_TESTING}) {
   # Some CPAN testers set these. Breaks dependencies
   $ENV{AUTHOR_TESTING  } = FALSE;
   $ENV{PERL_TEST_CRITIC} = FALSE; $ENV{PERL_TEST_POD} = FALSE;
   $ENV{TEST_CRITIC     } = FALSE; $ENV{TEST_POD     } = FALSE;
}

my %CONFIG =
   ( changes_file  => q(Changes),
     change_token  => q({{ $NEXT }}),
     cpan_authors  => q(http://search.cpan.org/CPAN/authors/id),
     cpan_dists    => q(http://search.cpan.org/dist),
     config_attrs  => { storage_class => q(JSON) },
     config_file   => [ qw(var etc build.json) ],
     create_ugrps  => TRUE,
     edit_files    => TRUE,
     install       => TRUE,
     line_format   => q(%-9s %s),
     local_lib     => q(local),
     path_prefix   => [ NUL, qw(opt) ],
     phase         => 1,
     pwidth        => 50,
     time_format   => q(%Y-%m-%d %T %Z), );

# Around these M::B actions
sub ACTION_distmeta {
   my $self = shift;

   try   {
      $self->_update_changelog( $self->_get_config, $self->_dist_version );
   }
   catch { $self->cli->fatal( $_ ) };

   $self->next::method();
   return;
}

sub ACTION_install {
   my $self = shift; my $cfg;

   try {
      $cfg = $self->_get_config;
      $self->_ask_questions( $cfg );
      $self->_set_install_paths( $cfg );
   }
   catch { $self->cli->fatal( $_ ) };

   $cfg->{install} and $self->next::method();

   try {
      my $install = $self->_install_actions_class->new( builder => $self );

      # Call each of the defined installation actions
      $install->$_( $cfg ) for (grep { $cfg->{ $_ } } @{ $install->actions });

      $self->cli_info( 'Installation complete' );
      $self->_post_install( $cfg );
   }
   catch { $self->cli->fatal( $_ ) };

   return;
}

# New M::B actions
sub ACTION_install_local_cpanm {
   my $self = shift;

   $self->depends_on( q(install_local_lib) );

   try   { $self->_install_local_cpanm( $self->_get_local_config ) }
   catch { $self->cli->fatal( $_ ) };

   return;
}

sub ACTION_install_local_deps {
   my $self = shift;

   $self->depends_on( q(install_local_cpanm) );

   try {
      my $cfg = $self->_get_local_config;

      $ENV{DEVEL_COVER_NO_COVERAGE} = TRUE;     # Devel::Cover
      $ENV{SITEPREFIX} = $cfg->{perlbrew_root}; # XML::DTD
      $self->_install_local_deps( $cfg );
   }
   catch { $self->cli->fatal( $_ ) };

   return;
}

sub ACTION_install_local_lib {
   my $self = shift;

   try {
      my $cfg = $self->_get_local_config;

      $self->_install_local_lib( $cfg );
      $self->_import_local_env ( $cfg );
   }
   catch { $self->cli->fatal( $_ ) };

   return;
}

sub ACTION_install_local_perl {
   my $self = shift;

   $self->depends_on( q(install_local_perlbrew) );

   try   { $self->_install_local_perl( $self->_get_local_config ) }
   catch { $self->cli->fatal( $_ ) };

   return;
}

sub ACTION_install_local_perlbrew {
   my $self = shift;

   $self->depends_on( q(install_local_lib) );

   try   { $self->_install_local_perlbrew( $self->_get_local_config ) }
   catch { $self->cli->fatal( $_ ) };

   return;
}

sub ACTION_local_archive {
   my $self = shift;

   try {
      my $dir = $self->_get_config->{local_lib};

      $self->make_tarball( $dir, $self->_get_archive_names( $dir )->[ 0 ] );
   }
   catch { $self->cli->fatal( $_ ) };

   return;
}

sub ACTION_restore_local_archive {
   my $self = shift;

   try {
      my $dir = $self->_get_config->{local_lib};

      $self->_extract_tarball( $self->_get_archive_names( $dir ) );
   }
   catch { $self->cli->fatal( $_ ) };

   return;
}

sub ACTION_standalone {
   my $self = shift;

   $self->depends_on( q(install_local_deps) );
   $self->depends_on( q(manifest) );
   $self->depends_on( q(dist) );
   return;
}

# Public object methods in the M::B namespace
sub class_path {
   return catfile( q(lib), split m{ :: }mx, $_[ 1 ].q(.pm) );
}

sub cli { # Self initialising accessor for the command line interface object
   state $cache; return $cache //= Class::Usul::Programs->new
      ( appclass => $_[ 0 ]->module_name, nodebug => TRUE );
}

sub cli_info {
   return shift->cli->info( map { chomp; "${_}\n" } @{ [ @_ ] } );
}

sub dispatch { # Now we can have M::B plugins
   my $self = shift; $self->_setup_plugins; return $self->next::method( @_ );
}

sub distname {
   my $distname = $_[ 1 ]; $distname =~ s{ :: }{-}gmx; return $distname;
}

sub make_tarball {
   # I want my tarballs in the parent of the project directory
   my ($self, $dir, $archive) = @_; $archive ||= $dir;

   return $self->next::method( $dir, $self->_archive_file( $archive ) );
}

sub patch_file { # Will apply a patch to a file only once
   my ($self, $path, $patch) = @_; my $cli = $self->cli;

   (not $path->is_file or -f $path.q(.orig)) and return;

   $self->cli_info( "Patching ${path}" ); $path->copy( $path.q(.orig) );

   my $cmd = [ qw(patch -p0), $path->pathname, $patch->pathname ];

   $self->cli_info( $cli->run_cmd( $cmd, { err => q(out) } )->out );
   return;
}

sub process_files {
   # Find and copy files and directories from source tree to destination tree
   my ($self, $src, $dest) = @_; $src or return; $dest ||= q(blib);

   if    (-f $src) { $self->_copy_file( $src, $dest ) }
   elsif (-d $src) {
      my $prefix = $self->base_dir;

      find( { no_chdir => TRUE, wanted => sub {
         (my $path = $File::Find::name) =~ s{ \A $prefix }{}mx;
         return $self->_copy_file( $path, $dest );
      }, }, $src );
   }

   return;
}

sub process_local_files { # Will copy the local lib into the blib
   my $self = shift; return $self->process_files( q(local) );
}

sub skip_pattern {
   # Accessor/mutator for the regular expression of paths not to process
   my ($self, $re) = @_;

   defined $re and $self->{_skip_pattern} = $re;

   return $self->{_skip_pattern};
}

# Private methods
sub _archive_dir {
   return updir();
}

sub _archive_file {
   return catfile( $_[ 0 ]->_archive_dir, $_[ 1 ] );
}

sub _ask_questions {
   my ($self, $cfg) = @_; $cfg->{built} and return;

   my $cli  = $self->cli; $cli->pwidth( $cfg->{pwidth} );

   my $quiz = $self->_question_class->new( builder => $self );

   # Update the config by looping through the questions
   for my $attr (@{ $quiz->config_attributes }) {
      my $question = q(q_).$attr; $cfg->{ $attr } = $quiz->$question( $cfg );
   }

   # Save the updated config for the install action to use
   my $args = { data => $cfg, path => $self->_get_config_path( $cfg ) };

   $self->cli_info( 'Saving post install config to '.$args->{path} );
   $cli->file->dataclass_schema( $cfg->{config_attrs} )->dump( $args );
   return;
}

sub _copy_file {
   my ($self, $src, $dest) = @_; my $cli = $self->cli;

   my $pattern = $self->skip_pattern;

   ($src and -f $src and (not $pattern or $src !~ $pattern)) or return;

   # Rebase the directory path
   my $dir = catdir( $dest, dirname( $src ) );

   # Ensure target directory exists
   -d $dir or $cli->io( $dir )->mkpath( oct q(02750) );

   copy( $src, $dir );
   return;
}

sub _dist_version {
   my $self = shift;
   my $info = Module::Metadata->new_from_file( $self->dist_version_from );

   return Perl::Version->new( $info->version );
}

sub _extract_tarball {
   my ($self, $archives) = @_; my $cli = $self->cli;

   for my $file (map { $self->_archive_file( $_.q(.tar.gz) ) } @{ $archives }) {
      unless (-f $file) { $cli->info( "Archive ${file} not found\n" ) }
      else {
         $cli->run_cmd( [ qw(tar -xzf), $file ] );
         $cli->info   ( "Extracted ${file}\n"   );
         return;
      }
   }

   return;
}

sub _get_archive_names {
   my ($self, $original_dir) = @_;

   my $name     = $self->dist_name;
   my $arch     = $Config{myarchname};
   my @archives = ( join q(-), $name, $original_dir,
                    $self->args->{ARGV}->[ 0 ] || $self->_dist_version, $arch );
   my $pattern  = "${name} - ${original_dir} - (.+) - ${arch}";
   my $latest   = ( map  { $_->[ 1 ] }               # Returning filename
                    sort { $a->[ 0 ] <=> $b->[ 0 ] } # By version object
                    map  { __to_version_and_filename( $pattern, $_ ) }
                    $self->cli->io    ( $self->_archive_dir      )
                              ->filter( sub { m{ $pattern }msx } )
                              ->all_files )[ -1 ];

   $latest and push @archives, $latest;
   return \@archives;
}

sub _get_config {
   my ($self, $passed_cfg) = @_; state $cache; $cache and return $cache;

   my $cfg = { %CONFIG, %{ $passed_cfg || {} }, %{ $self->notes } }; my $path;

   if ($path = $self->_get_config_path( $cfg ) and -f $path) {
      my $file = $self->cli->file;

      $cache = $cfg
             = $file->dataclass_schema( $cfg->{config_attrs} )->load( $path );
   }
   # TODO: Is this more trouble than its worth?
   #else { $self->cli->warning( 'Path [_1] not found', { args => [ $path ] } ) }

   $cfg->{version} .= NUL;
   return $cfg;
}

sub _get_config_path {
   my ($self, $cfg) = @_;

   return catfile( $self->base_dir, $self->blib, @{ $cfg->{config_file} } );
}

sub _get_local_config {
   my $self = shift; state $cache; $cache and return $cache;

   my $cli  = $self->cli; (my $perl_ver = $PERL_VERSION) =~ s{ \A v }{perl-}mx;

   my $argv = $self->args->{ARGV}; my $cfg = $self->_get_config;

   $cfg->{perl_ver     } = $argv->[ 0 ] || $perl_ver;
   $cfg->{appldir      } = $argv->[ 1 ] || NUL.$cli->config->appldir;
   $cfg->{perlbrew_root} = catdir ( $cfg->{appldir}, $cfg->{local_lib} );
   $cfg->{local_etc    } = catdir ( $cfg->{perlbrew_root}, q(etc) );
   $cfg->{local_libperl} = catdir ( $cfg->{perlbrew_root}, qw(lib perl5));
   $cfg->{perlbrew_bin } = catdir ( $cfg->{perlbrew_root}, q(bin) );
   $cfg->{perlbrew_cmnd} = catfile( $cfg->{perlbrew_bin }, q(perlbrew) );
   $cfg->{local_lib_uri} = join SEP, $cfg->{cpan_authors}, $cfg->{ll_author},
                                     $cfg->{ll_ver_dir}.q(.tar.gz);

   return $cache = $cfg;
}

sub _import_local_env {
   my ($self, $cfg) = @_;

   lib->import( $cfg->{local_libperl} );

   require local::lib; local::lib->import( $cfg->{perlbrew_root} );

   return;
}

sub _install_actions_class {
   return __PACKAGE__.q(::InstallActions);
}

sub _install_local_cpanm {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $cmd  = q(curl -s -L http://cpanmin.us | perl - App::cpanminus -L );
   my $path = catfile( $cfg->{perlbrew_bin}, q(cpanm) );

   -f $path and return;

   $self->cli_info( 'Installing local copy of App::cpanminus...' );
   $cli->run_cmd( $cmd.$cfg->{perlbrew_root} );
   not -f $path and throw "Failed to install App::cpanminus to ${path}";
   return;
}

sub _install_local_deps {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $local_lib = $cfg->{perlbrew_root} or throw 'Local lib not set';

   $self->cli_info( "Installing dependencies to ${local_lib}..." );

   my $cmd = [ qw(cpanm -L), $local_lib, qw(--installdeps .) ];

   $cli->run_cmd( $cmd, { err => q(stderr), out => q(stdout) } );

   my $ref; $ref = $self->can( q(hook_local_deps) ) and $self->$ref( $cfg );

   return;
}

sub _install_local_lib {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   my $dir = $cfg->{ll_ver_dir}; -d $cfg->{local_lib} and return;

   chdir $cfg->{appldir};
   $self->cli_info( 'Installing local::lib to '.$cfg->{perlbrew_root} );
   $cli->run_cmd( q(curl -s -L ).$cfg->{local_lib_uri}.q( | tar -xzf -) );

   (-d $dir and chdir $dir) or throw "Directory ${dir} cannot access";

   my $cmd = q(perl Makefile.PL --bootstrap=).$cfg->{perlbrew_root};

   $cli->run_cmd( $cmd.q( --no-manpages) );
   $cli->run_cmd( q(make test) );
   $cli->run_cmd( q(make install) );

   chdir $cfg->{appldir}; $cli->io( $cfg->{ll_ver_dir} )->rmtree;
   return;
}

sub _install_local_perl {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   unless (__perlbrew_mirror_is_set( $cfg )) {
      my $cmd = "echo 'm\n".$cfg->{perl_mirror}."' | perlbrew mirror";

      $self->cli_info( 'Setting perlbrew mirror' );
      __run_perlbrew( $cli, $cfg, $cmd );
   }

   unless (__perl_version_is_installed( $cli, $cfg )) {
      $self->cli_info( 'Installing '.$cfg->{perl_ver}.'...' );
      __run_perlbrew( $cli, $cfg, q(perlbrew install ).$cfg->{perl_ver} );
   }

   __run_perlbrew( $cli, $cfg, q(perlbrew switch ).$cfg->{perl_ver} );
   return;
}

sub _install_local_perlbrew {
   my ($self, $cfg) = @_; my $cli = $self->cli;

   -f $cfg->{perlbrew_cmnd} and return;

   $self->cli_info( 'Installing local perlbrew...' );
   $cli->run_cmd ( q(cpanm -L ).$cfg->{perlbrew_root}.q( App::perlbrew) );
   __run_perlbrew( $cli, $cfg, q(perlbrew init) );
   $cli->io      ( [ $cfg->{local_etc}, q(kshrc) ] )
       ->print   ( __local_kshrc_content( $cfg ) );

   my $ref; $ref = $self->can( q(hook_local_perlbrew) ) and $self->$ref( $cfg );

   return;
}

sub _post_install {
   my ($self, $cfg) = @_; my $appclass = $self->module_name;

   $ENV{ (env_prefix $appclass).q(_HOME) }
      = catdir( $cfg->{base}, q(lib), classdir $appclass );

   $cfg->{post_install} and $self->_run_bin_cmd( $cfg, q(post_install) )
      and $self->cli_info( 'Post install complete' );

   return;
}

sub _question_class {
   return __PACKAGE__.q(::Questions);
}

sub _run_bin_cmd {
   my ($self, $cfg, $key) = @_; my $cli = $self->cli; my $cmd;

   $cfg and ref $cfg eq HASH and $key and $cmd = $cfg->{ $key.q(_cmd) }
         or throw "Command ${key} not found";

   my ($prog, @args) = split SPC, $cmd;
   my $bind = $self->install_destination( q(bin) );
   my $path = $cli->file->absolute( $bind, $prog );

   -f $path or throw "Path ${path} not found";

   $cmd = join SPC, $path, @args;
   $self->cli_info( "Running ${cmd}" );
   $cli->run_cmd( $cmd, { err => q(stderr), out => q(stdout) } );

   my $ref; $ref = $self->can( "hook_${key}" ) and $self->$ref( $cfg );

   return TRUE;
}

sub _set_install_paths {
   my ($self, $cfg) = @_; $cfg->{base} or throw 'Config base path not set';

   $self->cli_info( 'Base path '.$cfg->{base} );
   $self->install_base( $cfg->{base} );
   $self->install_path( bin   => catdir( $cfg->{base}, q(bin)   ) );
   $self->install_path( lib   => catdir( $cfg->{base}, q(lib)   ) );
   $self->install_path( var   => catdir( $cfg->{base}, q(var)   ) );
   $self->install_path( local => catdir( $cfg->{base}, q(local) ) );
   return;
}

sub _setup_plugins {
   # Load CX::U::Plugin::Build::* plugins. Can haz plugins for M::B!
   state $cache; return $cache ||= $_[ 0 ]->cli->setup_plugins
      ( { child_class  => blessed $_[ 0 ],
          search_paths => [ q(::Build::Plugin) ], } );
}

sub _update_changelog {
   my ($self, $cfg, $ver) = @_;

   my $io   = $self->cli->io( $cfg->{changes_file} );
   my $tok  = $cfg->{change_token};
   my $time = time2str( $cfg->{time_format} || NUL );
   my $line = sprintf $cfg->{line_format}, $ver->normal, $time;
   my $tag  = q(v).__tag_from_version( $ver );
   my $text = $io->all;

   if (   $text =~ m{ ^   \Q$tag\E }mx)    {
          $text =~ s{ ^ ( \Q$tag\E .* ) $ }{$line}mx   }
   else { $text =~ s{   ( \Q$tok\E    )   }{$1\n\n$line}mx }

   emit 'Updating '.$cfg->{changes_file};
   $io->print( $text );
   return;
}

# Private functions
sub __local_kshrc_content {
   my $cfg = shift; my $content;

   $content  = '#!/usr/bin/env ksh'."\n";
   $content .= q(export LOCAL_LIB=).$cfg->{local_libperl}."\n";
   $content .= q(export PERLBREW_ROOT=).$cfg->{perlbrew_root}."\n";
   $content .= q(export PERLBREW_PERL=).$cfg->{perl_ver}."\n";
   $content .= q(export PERLBREW_BIN=).$cfg->{perlbrew_bin}."\n";
   $content .= q(export PERLBREW_CMND=).$cfg->{perlbrew_cmnd}."\n";
   $content .= <<'RC';

perlbrew_set_path() {
   alias -d perl 1>/dev/null
   path_without_perlbrew=$(perl -e \
      'print join ":", grep   { index $_, $ENV{PERLBREW_ROOT} }
                       split m{ : }mx, $ENV{PATH};')
   export PATH=${PERLBREW_BIN}:${path_without_perlbrew}
}

perlbrew() {
   local rc ; export SHELL ; short_option=""

   if [ $(echo ${1} | cut -c1) = '-' ]; then
      short_option=${1} ; shift
   fi

   case "${1}" in
   (use)
      if [ -z "${2}" ]; then
         print "Using ${PERLBREW_PERL} version"
      elif [ -x ${PERLBREW_ROOT}/perls/${2}/bin/perl -o ${2} = system ]; then
         unset PERLBREW_PERL
         eval $(${PERLBREW_CMND} ${short_option} env ${2})
         perlbrew_set_path
      else
         print "${2} is not installed" >&2 ; rc=1
      fi
      ;;

   (switch)
      ${PERLBREW_CMND} ${short_option} ${*} ; rc=${?}
      test -n "$2" && perlbrew_set_path
      ;;

   (off)
      unset PERLBREW_PERL
      ${PERLBREW_CMND} ${short_option} off
      perlbrew_set_path
      ;;

   (*)
      ${PERLBREW_CMND} ${short_option} ${*} ; rc=${?}
      ;;
   esac
   alias -t -r
   return ${rc:-0}
}

eval $(perl -I${LOCAL_LIB} -Mlocal::lib=${PERLBREW_ROOT})

perlbrew_set_path

RC

   return $content;
}

sub __perl_version_is_installed {
   my ($cli, $cfg) = @_; my $perl_ver = $cfg->{perl_ver};

   my $installed = __run_perlbrew( $cli, $cfg, q(perlbrew list) )->out;

   return (grep { m{ $perl_ver }mx } split "\n", $installed)[0] ? TRUE : FALSE;
}

sub __perlbrew_mirror_is_set {
   return -f catfile( $_[ 0 ]->{perlbrew_root}, q(Conf.pm) );
}

sub __run_perlbrew {
   my ($cli, $cfg, $cmd) = @_;

   my $path_sep = $Config::Config{path_sep};
   my $path     = join     $path_sep,
                  grep   { index $_, $cfg->{perlbrew_root} }
                  split m{ $path_sep }mx, $ENV{PATH};

   $ENV{PATH         } = $cfg->{perlbrew_bin }.$path_sep.$path;
   $ENV{PERLBREW_ROOT} = $cfg->{perlbrew_root};
   $ENV{PERLBREW_PERL} = $cfg->{perl_ver     };

   return $cli->run_cmd( $cmd );
}

sub __tag_from_version {
   my $ver = shift; return $ver->component( 0 ).q(.).$ver->component( 1 );
}

sub __to_version_and_filename {
   my ($pattern, $io) = @_;

  (my $file  = $io->filename) =~ s{ [.]tar[.]gz \z }{}msx;
   my ($ver) = $file =~ m{ $pattern }msx;

   return [ qv( $ver ), $file ];
}

1;

__END__

=pod

=head1 Name

Class::Usul::Build - M::B utility methods

=head1 Version

This document describes Class::Usul::Build version v0.21.$Rev: 1 $

=head1 Synopsis

   use Class::Usul::Build;
   use MRO::Compat;

   my $builder = q(Class::Usul::Build);
   my $class   = $builder->subclass( class => 'Bob', code  => <<'EOB' );

   sub ACTION_instal { # Spelling mistake intentional
      my $self = shift;

      $self->next::method();

      # Your application specific post installation code goes here

      return;
   }
   EOB

=head1 Description

Subclasses L<Module::Build>. Ask questions during the install
phase. The answers to the questions determine where the application
will be installed and which additional actions will take place. Should
be generic enough for any web application

=head1 ACTIONS

=head2 ACTION_distmeta

=head2 distmeta

Updates license file and changelog

=head2 ACTION_install

=head2 install

When called from it's subclass this method performs the sequence of
actions required to install the application. Configuration options are
written from the file F<build.json>. The L</actions> method returns the
list of steps required to install the application

=head2 ACTION_install_local_cpanm

=head2 install_local_cpanm

Install L<App::Cpanminus> to the local lib

=head2 ACTION_install_local_deps

=head2 install_local_deps

Installs dependencies to the local lib

=head2 ACTION_install_local_lib

=head2 install_local_lib

Install L<local::lib> locally

=head2 ACTION_install_local_perl

=head2 install_local_perl

Install a specific Perl version to the local Perlbrew area

=head2 ACTION_install_local_perlbrew

=head2 install_local_perlbrew

Installs L<Perlbrew> locally

=head2 ACTION_installdeps

=head2 installdeps

Iterates over the I<requires> attributes calling L<CPAN> each time to
install the dependent module

=head2 ACTION_local_archive

=head2 local_archive

Creates a tarball of the local lib directory

=head2 ACTION_restore_local_archive

=head2 restore_local_archive

Unpacks an archive tarball of the local lib directory

=head2 ACTION_standalone

=head2 standalone

Locally installs local lib and all dependencies

=head1 Subroutines/Methods

=head2 class_path

   $path = $builder->class_path( $class_name );

Returns the relative path to the specified class

=head2 cli

   $cli = $builder->cli;

Returns an instance of L<Class::Usul::Programs>, the command line
interface object

=head2 cli_info

   $builder->cli_info( @list_of_messages );

Calls L<info|Class::Usul::Programs/info> on the L<client object|/cli>

=head2 dispatch

Overloads the M::B method. Calls L</_setup_plugins> then the parent method

=head2 distname

Turns a class name into a distribution name

=head2 install_actions_class

Returns the class name of the class which contains the additional actions
that are performed when the application is installed

=head2 make_tarball

Overloads the M::B method. Changes the directory which will contain the
distribution tarball then calls the parent method

=head2 patch_file

Runs the I<patch> utility on the specified source file

=head2 post_install

   $builder->post_install( $config );

Executes the custom post installation commands

=head2 process_files

   $builder->process_files( $source, $destination );

Handles the processing of files other than library modules and
programs.  Uses the I<Bob::skip_pattern> defined in the subclass to
select only those files that should be processed.  Copies files from
source to destination, creating the destination directories as
required. Source can be a single file or a directory. The destination
is optional and defaults to B<blib>

=head2 process_local_files

Calls L</process_file> setting the source to I<local>

=head2 question_class

Returns the class name of the class which contains the questions that are
asked when the application is installed

=head2 set_base_path

   $base = $builder->set_base_path( $config );

Uses the C<< $config->{style} >> attribute to set the L<Module::Build>
I<install_base> attribute to the base directory for this installation.
Returns that path. Also sets; F<bin>, F<lib>, and F<var> directory paths
as appropriate. Called from L<ACTION_install>

=head2 skip_pattern

   $regexp = $builder->skip_pattern( $new_regexp );

Accessor/mutator method. Used by L</_copy_file> to skip processing files
that match this pattern. Set to false to not have a skip list

=head2 update_changelog

Update the version number and date/time stamp in the F<Changes> file

=head1 Private Methods

=head2 _copy_file

   $builder->_copy_file( $source, $destination );

Called by L</process_files>. Copies the C<$source> file to the
C<$destination> directory

=head1 Diagnostics

None

=head1 Configuration and Environment

Edits and stores config information in the file F<build.json>

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Module::Build>

=item L<Module::Metadata>

=item L<MRO::Compat>

=item L<Perl::Version>

=item L<Try::Tiny>

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
