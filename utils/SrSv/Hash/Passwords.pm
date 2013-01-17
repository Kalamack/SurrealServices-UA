#	This file is part of SurrealServices.
#
#	SurrealServices is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	SurrealServices is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with SurrealServices; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package SrSv::Hash::Passwords;

=head1 NAME

SrSv::Hash::Passwords - Handle passwords, hashing, and verifying the hashes.

=cut

use strict;
use SrSv::Hash::SaltedHash qw( makeHash verifyHash );
use SrSv::Conf qw( main );

use Exporter 'import';
BEGIN { 
	our @EXPORT = qw( hash_pass validate_pass is_hashed );
}

=head2 

  hash_pass($pass)
  	If hashed-passwords is enabled in main.conf, returns a hashed password in a string.
	Otherwise returns $pass unmodified.

=cut

sub hash_pass($) {
	my ($pass) = @_;
	if($main_conf{'hashed-passwords'}) {
		return makeHash($pass);
	}
	else {
		return $pass;
	}
}

=head2

  validate_pass($hashedPass, $pass)
	Decodes the hashedPass.
	- If $hashedPass is a valid SSHA256 hash-string, it and determines whether $pass matches $hashedPass
	- If $hashedPass is not a valid SSHA256 hash-string, it returns ($hashedPass eq $pass)

=cut
sub validate_pass($$) {
	my ($hashedPass, $pass) = @_;
	if (my $hashType = is_hashed($hashedPass)) {
		return verifyHash($hashedPass, $pass);
	} else {
		return $hashedPass eq $pass;
	}
}

sub is_hashed($) {
	my ($in) = @_;
	if ($in =~ /^\{S(.*)\}/ or $in =~ m/^(?:SHA256):v\d+-\d+-r\d+:[A-Za-z0-9+\/=]+:/) {
		return 1;
	} else {
		return undef;
	}
}

1;
