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

package SrSv::NickReg::Flags;

use strict;

use Exporter 'import';

BEGIN {
	my %constants = (
		# current nickreg.flags definition limits us to 16 of these. or 32768 as last flag
		NRF_HIDEMAIL => 1,
		NRF_NOMEMO => 2,
		NRF_NOACC => 4,
		NRF_NEVEROP => 8,
		NRF_AUTH => 16,
		NRF_HOLD => 32,
		NRF_FREEZE => 64,
		NRF_VACATION => 128,
		NRF_EMAILREG => 256,
		NRF_NOHIGHLIGHT => 512,
		NRF_SENDPASS => 1024,
	);

	our @EXPORT = (qw(nr_set_flag nr_set_flags nr_chk_flag nr_chk_flag_user nr_get_flags), keys(%constants));

	require constant; import constant (\%constants);
}

use SrSv::Process::Init;
use SrSv::MySQL '$dbh';

use SrSv::User qw(get_user_id);

our ($get_flags, $set_flag, $unset_flag, $set_flags, $get_nickreg_flags_user);

proc_init {
	$get_flags = $dbh->prepare("SELECT nickreg.flags FROM nickreg, nickalias WHERE nickalias.nrid=nickreg.id AND nickalias.alias=?");
	$set_flag = $dbh->prepare("UPDATE nickreg, nickalias SET nickreg.flags=(nickreg.flags | (?)) WHERE nickalias.nrid=nickreg.id AND nickalias.alias=?");
	$set_flags = $dbh->prepare("UPDATE nickreg, nickalias SET nickreg.flags=? WHERE nickalias.nrid=nickreg.id AND nickalias.alias=?");
	$unset_flag = $dbh->prepare("UPDATE nickreg, nickalias SET nickreg.flags=(nickreg.flags & ~(?)) WHERE nickalias.nrid=nickreg.id AND nickalias.alias=?");
	$get_nickreg_flags_user = $dbh->prepare("SELECT BIT_OR(nickreg.flags) FROM user
		JOIN nickid ON (user.id=nickid.id)
		JOIN nickreg ON(nickid.nrid=nickreg.id)
		WHERE user.id=? GROUP BY user.id");
};

sub nr_set_flag($$;$) {
	my ($nick, $flag, $sign) = @_;
	$sign = 1 unless defined($sign);

	if($sign) {
		$set_flag->execute($flag, $nick);
	} else {
		$unset_flag->execute($flag, $nick);
	}
}

sub nr_set_flags($$) {
	my ($nick, $flags) = @_;

	$set_flags->execute($flags, $nick);
}

sub nr_chk_flag($$;$) {
	my ($nick, $flag, $sign) = @_;
	$sign = 1 unless defined($sign);

	$get_flags->execute($nick);
	my ($flags) = $get_flags->fetchrow_array;

	return ($sign ? ($flags & $flag) : !($flags & $flag));
}

sub nr_chk_flag_user($$;$) {
	my ($tuser, $flag, $sign) = @_;
	$sign = 1 unless defined($sign);

	my $flags = 0;
	# This needs to have ns_identify, ns_logout and ns_set clear $user->{NICKFLAGS}
	if(exists $tuser->{NICKFLAGS}) {
		$flags = $tuser->{NICKFLAGS};
	}
	else {
		$get_nickreg_flags_user->execute(get_user_id($tuser));
		($flags) = $get_nickreg_flags_user->fetchrow_array();
		$get_nickreg_flags_user->finish();
		$tuser->{NICKFLAGS} = $flags;
	}

	return ($sign ? ($flags & $flag) : !($flags & $flag));
}

sub nr_get_flags($) {
	my ($nick) = @_;

	$get_flags->execute($nick);
	my ($flags) = $get_flags->fetchrow_array(); $get_flags->finish();
	return $flags;
}

1;
