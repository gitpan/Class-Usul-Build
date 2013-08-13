# @(#)Ident: 10test_script.t 2013-08-13 12:20 pjf ;

use strict;
use warnings;
use version; our $VERSION = qv( sprintf '0.23.%d', q$Rev: 1 $ =~ /\d+/gmx );
use File::Spec::Functions   qw( catdir updir );
use FindBin                 qw( $Bin );
use lib                 catdir( $Bin, updir, 'lib' );

use Module::Build;
use Test::More;

my $notes = {};

BEGIN {
   my $builder = eval { Module::Build->current };

   $builder and $notes = $builder->notes;
}

use_ok 'Class::Usul::Build';

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
