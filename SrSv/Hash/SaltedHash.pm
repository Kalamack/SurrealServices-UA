#########################################################################################
##                                                                                     ##
##      Copyright(c) 2007 M2000, Inc.                                                  ##
##                                                                                     ##
##      File: SaltedHash.pm                                                            ##
##      Author: Adam Schrotenboer                                                      ##
##                                                                                     ##
##                                                                                     ##
##      Description                                                                    ##
##      ===========                                                                    ##
##      Produces salted hashes for various uses.                                       ##
##      This module is licensed under the Lesser GNU Public License version 2.1        ##
##                                                                                     ##
##      Revision History                                                               ##
##      ================                                                               ##
##      11/13/07:       Initial version.                                               ##
##                                                                                     ##
##                                                                                     ##
#########################################################################################
##                                                                                     ##
##      For more details refer to the implementation specification document            ##
##      DRCS-xxxxxx Section x.x                                                        ##
##                                                                                     ##
#########################################################################################
package SrSv::Hash::SaltedHash;

use strict;

=head1 NAME

SaltedHash

=head1 SYNOPSIS

use SaltedHash;

=head1 DESCRIPTION

Produces and verifies salted hashes.

=head2 NOTE

 This module currently only supports SHA256, and requires Digest::SHA.
 If Digest::SHA is not available, it will however fallback to an included copy of Digest::SHA::PurePerl

=cut


BEGIN {
	if(eval { require Digest::SHA; } ) {
		import Digest::SHA qw( sha256_base64 sha256 sha1 );
		print "SrSv::Hash::SaltedHash using Digest::SHA\n";
	} 
	elsif(eval { require Digest::SHA::PurePerl; } ){
		import Digest::SHA::PurePerl qw( sha256_base64 sha256 sha1 );
		print "SrSv::Hash::SaltedHash using Digest::SHA::PurePerl\n";
	} else {
		die "Unable to find a suitable SHA implementation\n";
	}
}
use Digest::MD5;

=item Hash Notes

 SHA512 requires 64bit int operations, and thus will be SLOW on 32bit platforms.
 Current hash string length with SHA256 and 16byte (128bit) salts is 85 characters
 Be aware that SHA512 with 16byte salt would take approximately ~130 characters
 So make sure that your password field can hold strings large enough.
 It is generally considered pointless to make your salt
 longer than your hash, so 32bytes is longest that is useful
 for SHA256 and 64 is longest for SHA512.
 SrSv has a limit of 127 characters for password strings, so don't use SHA512.

=cut
use Exporter 'import';
BEGIN {
	my %constants = (
		HASH_ALGORITHM => 'SHA256',
		HASH_SALT_LEN => 16,
		HASH_ROUNDS => 1,
	);
	my $version = 'v1-'.$constants{HASH_SALT_LEN}.'-r'.$constants{HASH_ROUNDS};
	$constants{HASH_VERSION} = $version;
	our @EXPORT = qw( makeHash verifyHash );
	our @EXPORT_OK = ( @EXPORT, keys(%constants), qw( extractMeta extractSalt padBase64 makeHash_v0 makeHash_v1 ));
	our %EXPORT_TAGS = ( constants => [keys(%constants)] );
	require constant; import constant (\%constants);
}


use MIME::Base64 qw( encode_base64 decode_base64 );
use SrSv::Hash::Random qw( randomBytes randomByte );

=item makeHash($;$$$)

    makeHash($secret, $salt, $algorithm, $version)

    Salt is assumed to be a BINARY STRING.

    Algorithm currently can only be 'SHA256'

=cut

sub makeHash($;$$$) {
	return makeHash_v1(@_);
}

=item makeHash_v1($;$$$)

    makeHash_v1 ($secret, $salt, $algorithm, $version)

    returns a string that can be processed thusly
    my ($algorithm, $version, $salt, $hash) = split(':', $string);

    my ($revision, $saltsize, $rounds) = split('-', $version);

=cut

sub makeHash_v1($;$$$) {
	my ($secret, $salt, $algorithm, $version) = @_;
	$algorithm = HASH_ALGORITHM unless $algorithm;
	$salt = makeBinSalt(HASH_SALT_LEN) unless $salt;
	$version = HASH_VERSION unless $version;
	my $string = "$algorithm:$version:";
	$string .= encode_base64($salt, '').':';
	$string .= padBase64(__makeHash($secret . $salt, $algorithm));
	return $string;
}

sub makeHash_vBulletin($;$$$) {
	my ($secret, $salt, $algorithm, $version) = @_;
	$algorithm = 'md5' unless $algorithm;
	$salt = makeBinSalt(3) unless $salt;
	$version = 2 unless $version;
	my $string = "$algorithm:$version:";
	$string .= encode_base64($salt, '').':';
	$string .= md5_base64(md5_hex($secret) . $salt);
	return $string;
}

sub __makeHash($$) {
	my ($plaintext, $algorithm) = @_;
	$algorithm = 'sha256';
	if($algorithm =~ /^sha256$/i) {
		return sha256_base64($plaintext);
	} else {
		# Other hash algos haven't been implemented yet
		die "Unknown hash algorithm \"$algorithm\" \"$plaintext\"\n";
	}
}

sub makeHash_v0($;$$) {
	my ($secret, $salt, $algorithm) = @_;
	$algorithm = 'SHA256' unless $algorithm;
	$salt = makeBinSalt(4) unless $salt;
	my $string = "{S$algorithm}";
	if($algorithm eq 'SHA256') {
		$string .= encode_base64(sha256($secret . $salt) . $salt, '');
	} elsif ($algorithm eq 'SHA') {
		$string .= encode_base64(sha1($secret . $salt) . $salt, '');
	}
	return $string;
}

sub padBase64($) {
	my ($b64_digest) = @_;
	while (length($b64_digest) % 4) {
		$b64_digest .= '=';
	}
	return $b64_digest;
}

=item makeHash

    verifyHash($hash, $plain)

    Verifies that a given $plain matches $hash

=cut

sub verifyHash($$) {
	my ($hash, $plain) = @_;
	my ($algorithm, $version, $salt) = extractMeta($hash);
	my $hash2;
	if($version eq 'v0') {
		$hash2 = makeHash_v0($plain, $salt, $algorithm);
	} elsif($version eq 'vBulletin') {
		$hash2 = makeHash_vBulletin($plain, $salt, $algorithm);
	} else {
		$hash2 = makeHash_v1($plain, $salt, $algorithm, $version);
	}
	
	return ($hash eq $hash2 ? 1 : 0);
}

sub makeBinSalt(;$) {
	my ($len) = @_;
	$len = HASH_SALT_LEN unless $len;
	return randomBytes($len);
}

=item makeHash

    extractMeta($hash)

    return ($algorithm, $version, $salt) from $hash.

=cut
sub extractMeta($) {
	my ($input) = @_;
	if($input =~ /^\{S(\S+)\}(.*)$/) {
		my $algorithm = $1;
		my $saltedBinHash = decode_base64($2);
		my $salt = substr($saltedBinHash, -4);
		return ($algorithm, 'v0', $salt);
	} else {
		my ($algorithm, $version, $salt, $hash) = split(':', $input);
		return ($algorithm, $version, decode_base64($salt));
	}
}

=item makeHash

    extractSalt($hash)

    return $salt from $hash.

=cut
sub extractSalt($) {
	my ($input) = @_;
	my ($algorithm, $version, $salt) = extractMeta($input);
	return $salt;
}

1;
