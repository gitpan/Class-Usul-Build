# @(#)$Ident: Build.PL 2013-08-13 12:00 pjf ;

use strict;
use warnings;

use Module::Build;

sub whimper { print {*STDOUT} $_[ 0 ]."\n"; exit 0 }

$] >= 5.01 or $ENV{PERL5_CPANPLUS_IS_VERSION}
   or whimper "Minimum required Perl version is 5.01";

my $code = do { local $/; <DATA> };

Module::Build->subclass( code => $code )->new(
  'module_name'   => 'Class::Usul::Build',
  'notes'         => {
     is_reporting => !! ($ENV{AUTOMATED_TESTING} || $ENV{PERL_CR_SMOKER_CURRENT}
                         || ($ENV{PERL5OPT} || q()) =~ m{ CPAN-Reporter }mx),
     version      => 0.18.1 },
  'share_dir'     => -d 'share' ? 'share' : undef,
  'build_requires' => {
    'Module::Build' => '0.4004',
    'version' => '0.88'
  },
  'configure_requires' => {
    'Module::Build' => '0.4004',
    'version' => '0.88'
  },
  'requires' => {
    'Class::Usul' => 'v0.23.0',
    'MRO::Compat' => '0.11',
    'Module::Metadata' => '1.000011',
    'Moo' => '1.003000',
    'Perl::Version' => '1.011',
    'Try::Tiny' => '0.09',
    'local::lib' => '1.008004',
    'namespace::sweep' => '0.006',
    'parent' => '0.224'
  },
)->create_build_script;

exit 0;

__DATA__

sub _normalize_prereqs { # Dynamic config
   my $self = shift; my $p = $self->SUPER::_normalize_prereqs;

   my $osname = lc $^O;

   return $p;
}
