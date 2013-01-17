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

package SrSv::ChanReg::Flags;

=head1 NAME

SrSv::ChanReg::Flags - Manage flags of registered channels.

=cut

use strict;

use Exporter 'import';

BEGIN {
	my %constants = (
		#current chanreg.flags definition limits us to 16 of these. or 32768 as last flag
		CRF_OPGUARD => 1,
		CRF_LEAVEOP => 2,
		CRF_VERBOSE => 4,
		CRF_HOLD => 8,
		CRF_FREEZE => 16,
		CRF_BOTSTAY => 32,
		CRF_CLOSE => 64,
		CRF_DRONE => 128,
		CRF_SPLITOPS => 256,
		CRF_LOG => 512,
		CRF_AUTOVOICE => 1024,
		CRF_WELCOMEINCHAN => 2048,
		CRF_NEVEROP => 4096,
		CRF_NOCLONES => 8192,
	);

	our @EXPORT = (qw(cr_chk_flag cr_set_flag), keys(%constants));

	require constant; import constant (\%constants);
}

use SrSv::MySQL '$dbh';
use SrSv::Process::Init;

our ($set_flags, $get_flags, $set_flag, $unset_flag);

proc_init {
	$set_flags = $dbh->prepare("UPDATE chanreg SET flags=? WHERE chan=?");
	$get_flags = $dbh->prepare("SELECT flags FROM chanreg WHERE chan=?");
	$set_flag = $dbh->prepare("UPDATE chanreg SET flags=(flags | (?)) WHERE chan=?");
	$unset_flag = $dbh->prepare("UPDATE chanreg SET flags=(flags & ~(?)) WHERE chan=?");

};

sub cr_set_flag($$$) {
	my ($chan, $flag, $sign) = @_;
	my $cn = $chan->{CHAN};

	if($sign >= 1) {
		$chan->{FLAGS} = ( ( defined $chan->{FLAGS} ? $chan->{FLAGS} : 0 ) | $flag );
		$set_flag->execute($flag, $cn);
	} else {
		$chan->{FLAGS} = ( ( defined $chan->{FLAGS} ? $chan->{FLAGS} : 0 ) & ~($flag) );
		$unset_flag->execute($flag, $cn);
	}
}

sub cr_chk_flag($$;$) {
	my ($chan, $flag, $sign) = @_;
	my $cn = $chan->{CHAN};
	$sign = 1 unless defined($sign);

	my $flags;
	unless (exists($chan->{FLAGS})) {
		$get_flags->execute($cn);
		($chan->{FLAGS}) = $get_flags->fetchrow_array;
		$get_flags->finish();
	}
	$flags = $chan->{FLAGS};

	return ($sign ? ($flags & $flag) : !($flags & $flag));
}

1;
