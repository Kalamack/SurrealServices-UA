#!/usr/bin/perl

sub say(@) {
	print map({ "$_\n" } @_);
}
use strict;
BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename qw( dirname );
	use constant { PREFIX => abs_path(dirname(abs_path($0)).'/../') }
}
use lib PREFIX;

#use Digest::SHA::PurePerl;
use SrSv::Hash::SaltedHash qw( makeHash_v0 makeHash verifyHash extractMeta extractSalt );

#say makeHash_v0('fumafuma', 'fufu', 'SHA256');
#exit;

my ($algorithm, $version, $salt) = extractMeta('{SSHA}zIdhML+axPWmpSymzKlTciJ5asoryacr');
my $hash = makeHash_v0('choice81', $salt, $algorithm);
say $hash;
exit;
my $check = verifyHash($hash, 'fumafuma');
print (($check ? 'true' : 'false')."\n");

#my $hash = makeHash_v0('fumafuma');
#my ($algo, $version, $salt) = extractMeta($hash);
#say "$algo $version $salt";
#say length(makeHash_v0('fumafuma', 'fufu', 'SHA256'));
