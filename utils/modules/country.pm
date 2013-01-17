#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#       Copyright tabris@surrealchat.net (C) 2005
package country;

use strict;

use SrSv::MySQL '$dbh';
use SrSv::Process::Init;
use SrSv::IRCd::Event 'addhandler';
use SrSv::IRCd::State 'initial_synced';

use SrSv::Log;

use SrSv::Shared qw(%unwhois);

use SrSv::User qw(get_user_id);

addhandler('USERIP', undef, undef, 'userip');
addhandler('NICKCONN', undef, undef, 'nickconn');

our ($get_ip_country, $get_ip_country_aton, $get_user_country);

proc_init {
	$get_ip_country = $dbh->prepare_cached("SELECT country FROM country WHERE
		? BETWEEN low AND high");
	$get_ip_country_aton = $dbh->prepare_cached("SELECT country FROM country WHERE
		INET_ATON(?) BETWEEN low AND high");
	$get_user_country = $dbh->prepare_cached("SELECT country FROM country, user WHERE
		user.ip BETWEEN low AND high and user.id=?");
};

sub get_ip_country($) {
	my ($ip) = @_;

	$get_ip_country->execute($ip);
	my ($country) = $get_ip_country->fetchrow_array();
	$get_ip_country->finish();

	return $country;
}

sub get_ip_country_aton($) {
# IP is expected to be a dotted quad string!
	my ($ip) = @_;

	$get_ip_country_aton->execute($ip);
	my ($country) = $get_ip_country_aton->fetchrow_array();
	$get_ip_country_aton->finish();
	#my ($country)= $dbh->selectrow_array(
	#	"SELECT `country` FROM `country` WHERE `low` < INET_ATON('$ip') AND `high` > INET_ATON('$ip')");
	#$dbh->finish();

	return $country;
}

sub get_user_country($) {
# Preferred to use this if you have a $user hash and you've set the IP.
# it should return undef in the case of user.ip == 0
# do check this case in the caller before assuming the return value is valid.
	my ($user) = @_;

	$get_user_country->execute(get_user_id($user));
	my ($country) = $get_user_country->fetchrow_array();
	$get_user_country->finish();

	return $country;
}

sub get_country_long($) {
# I'd prefer that this be used by the callers of get_user_country()
# If they need the long country name, 
# they can use country::get_country_long(country::get_user_country($user))
# that way the get_{user,ip}_country functions get back an easily parsed value.
	my ($country) = @_;
	$country = uc $country;

	my $cname = $core::ccode{$country};
	$country .= " ($cname)" if $cname;

	return $country if $cname;
	return 'Unknown';
}

sub get_user_country_long($) {
	my ($user) = @_;
	return get_country_long(get_user_country($user));
}

sub nickconn {
	my ($rnick, $time, $ident, $host, $vhost, $server, $modes, $gecos, $ip, $svsstamp) = @_[0,2..4,8,5,7,9,10,6];
	if(initial_synced() && !$svsstamp) {
		if ($ip) {
			wlog($main::rsnick, LOG_INFO(), "\002$rnick\002 is connecting from ".
				get_country_long(get_ip_country_aton($ip)));
		}
		else {
			$unwhois{lc $rnick} = 1;
		}
	}
	# we already depend on services being up for our SQL,
	# thus we know a USERIP will be sent.
	# However this IS avoidable if we make our own SQL connection
	# but would then require an additional %config and configfile
	return;
}

sub userip($$$) {
	my($src, $nick, $ip) = @_;

	return unless($unwhois{lc $nick});
	return unless($ip =~ /^\d{1,3}(\.\d{1,3}){3}$/);

	wlog($main::rsnick, LOG_INFO(), "\002$nick\002 is connecting from ".
		get_country_long(get_ip_country_aton($ip)));
	delete $unwhois{lc $nick};
}

sub init() { }
sub begin() { }
sub end() { %unwhois = undef(); }
sub unload() { }

1;
