# @(#)$Ident: Build.PL 2013-08-08 13:53 pjf ;

use strict;
use warnings;
use inc::Bob; # Module::Build subclass
use version; our $VERSION = qv( sprintf '0.22.%d', q$Rev: 4 $ =~ /\d+/gmx );

Bob->new( {
   module    => q(Class::Usul::Build),
   home_page => q(http://www.roxsoft.co.uk),
   requires  => {
      'perl'             => 5.01,
      'local::lib'       => 1.008004,
      'namespace::sweep' => 0.006,
      'parent'           => 0.224,
      'Class::Usul'      => q(0.23.0),
      'Module::Metadata' => 1.000011,
      'Moo'              => 1.003000,
      'MRO::Compat'      => 0.11,
      'Perl::Version'    => 1.011,
      'Try::Tiny'        => 0.09, },
   recommends            => {
      'App::cpanminus'   => 1.6005, },
   configure_requires    => {
      'version'          => 0.88,
      'Module::Build'    => 0.4004, },
   build_requires        => {
      'version'          => 0.88,
      'Module::Build'    => 0.4004, },
} )->create_build_script; # Goal!

# Local Variables:
# mode: perl
# eval: (load-project-state "class-usul-build")
# tab-title: CU::Build
# tab-width: 3
# End:
