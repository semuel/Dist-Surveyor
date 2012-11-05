
use strict;
use warnings;

use 5.006;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Survey installed modules and determine the specific distribution versions they came from",
  "AUTHOR" => "Tim Bunce <Tim.Bunce\@pobox.com>",
  "BUILD_REQUIRES" => {
    "Test::More" => "0.88"
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Dist-Surveyor",
  "EXE_FILES" => [
    "bin/dist_surveyor"
  ],
  "LICENSE" => "perl",
  "NAME" => "Dist::Surveyor",
  "PREREQ_PM" => {
    "CPAN::DistnameInfo" => 0,
    "Compress::Zlib" => 0,
    "JSON" => 0,
    "LWP::UserAgent" => 0,
    "Module::CoreList" => 0,
    "Module::Metadata" => 0,
    "version" => 0
  },
  "VERSION" => "0.006",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



