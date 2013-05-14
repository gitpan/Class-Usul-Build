# @(#)$Ident: Build.PL 2013-05-14 22:05 pjf ;

use strict;
use warnings;
use inc::Bob; # Module::Build subclass
use version; our $VERSION = qv( sprintf '0.20.%d', q$Rev: 1 $ =~ /\d+/gmx );

Bob->new( {
   module    => q(Class::Usul::Build),
   home_page => q(http://www.roxsoft.co.uk),
   requires  => {
      'perl'                => 5.01,
      'local::lib'          => 1.008004,
      'parent'              => 0.224,
      'Class::Usul'         => q(0.20.0),
      'Email::Date::Format' => 1.002,
      'Git::Class'          => 0.12,
      'Module::Metadata'    => 1.000011,
      'MRO::Compat'         => 0.11,
      'Perl::Version'       => 1.011,
      'SVN::Class'          => 0.16,
      'Text::Format'        => 0.53,
      'Try::Tiny'           => 0.09, },
   recommends          => {
      'App::cpanminus' => 1.6005,
      'DhMakePerl'     => 0.72 },
   configure_requires  => {
      'version'        => 0.88,
      'Module::Build'  => 0.4004, },
   build_requires      => {
      'version'        => 0.88,
      'Module::Build'  => 0.4004, },
} )->create_build_script; # Goal!

# Local Variables:
# mode: perl
# eval: (load-project-state "class-usul-build")
# tab-title: Class::Usul::Build
# tab-width: 3
# End:
