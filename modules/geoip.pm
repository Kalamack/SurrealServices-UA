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
#       Copyright tabris@surrealchat.net (C) 2005, 2008
package geoip;

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

our ($get_ip_location, $get_ip_location_aton, $get_user_location);

proc_init {
	my $baseSQL = "SELECT geolocation.country, geolocation.region,
		geocountry.country, georegion.name, geolocation.city, geolocation.postalcode,metrocode.metro
		FROM geolocation
		JOIN geoip ON (geolocation.id=geoip.location)
		LEFT JOIN geocountry ON (geolocation.country=geocountry.code)
		LEFT JOIN georegion ON (geolocation.country=georegion.country AND geolocation.region=georegion.region)
		LEFT JOIN metrocode ON (metrocode.id=geolocation.metrocode) ";
	#"WHERE MBRCONTAINS(ip_poly, POINTFROMWKB(POINT(INET_ATON( ? ), 0)))";
	$get_ip_location = $dbh->prepare_cached("$baseSQL
		WHERE MBRCONTAINS(ip_poly, POINTFROMWKB(POINT( ?, 0)))");
	$get_ip_location_aton = $dbh->prepare_cached("$baseSQL
		WHERE MBRCONTAINS(ip_poly, POINTFROMWKB(POINT(INET_ATON( ? ), 0)))");
	$get_user_location = $dbh->prepare_cached("$baseSQL
		JOIN user
		WHERE MBRCONTAINS(ip_poly, POINTFROMWKB(POINT(user.ip, 0)))
		AND user.id=?");
};

sub get_ip_location($) {
	my ($ip) = @_;

	$get_ip_location->execute($ip);
	my ($countryCode, $regionCode, $countryName, $regionName, $city, $postalCode, $metro) =
		$get_ip_location->fetchrow_array();
	$get_ip_location->finish();
	if(!defined($countryCode)) {
		$countryCode = '-';
		$countryName = 'Unknown';
	}

	if(wantarray) {
		return ($countryCode, $regionCode, $countryName, $regionName, $city, $postalCode, $metro);
	} else {
		return $countryCode;
	}
}

sub get_ip_location_aton($) {
# IP is expected to be a dotted quad string!
	my ($ip) = @_;

	$get_ip_location_aton->execute($ip);
	my ($countryCode, $regionCode, $countryName, $regionName, $city, $postalCode, $metro) =
		$get_ip_location_aton->fetchrow_array();
	$get_ip_location_aton->finish();
	#my ($country)= $dbh->selectrow_array(
	#	"SELECT `country` FROM `country` WHERE `low` < INET_ATON('$ip') AND `high` > INET_ATON('$ip')");
	#$dbh->finish();
	if(!defined($countryCode)) {
		$countryCode = '-';
		$countryName = 'Unknown';
	}

	if(wantarray) {
		return ($countryCode, $regionCode, $countryName, $regionName, $city, $postalCode, $metro);
	} else {
		return $countryCode;
	}
}

sub get_user_location($) {
# Preferred to use this if you have a $user hash and you've set the IP.
# it should return undef in the case of user.ip == 0
# do check this case in the caller before assuming the return value is valid.
	my ($user) = @_;

	$get_user_location->execute(get_user_id($user));
	my ($countryCode, $regionCode, $countryName, $regionName, $city, $postalCode, $metro) =
		$get_user_location->fetchrow_array();
	$get_user_location->finish();
	if(!defined($countryCode)) {
		$countryCode = '-';
		$countryName = 'Unknown';
	}

	if(wantarray) {
		return ($countryCode, $regionCode, $countryName, $regionName, $city, $postalCode, $metro);
	} else {
		return $countryCode;
	}
}

sub stringify_location(@) {
	my ($countryCode, $regionCode, $countryName, $regionName, $city, $postalCode, $metro) = @_;
	my $location;
	if(!defined($countryCode) || $countryCode eq '-') {
		$location = "Unknown";
	} else {
		$location = "$countryName";
		if(defined($city) && length($city)) {
			$location .= " ($city";
		}
		if(defined($regionName)) {
			if($regionName =~ /, /) {
				#normalize stuff like "London, City of"
				$regionName = join(' ', reverse(split(', ', $regionName)));
			}
			$location .= (defined($city) && length($city)) ? ', ' : '(';
			$location .= "$regionName)";
		} elsif(defined($city) && length($city)) {
			$location .= ')';
		}
		if(defined($metro)) {
			$location .= " [$metro]";
		}
	}
	return $location;
}

sub nickconn {
	my ($rnick, $time, $ident, $host, $vhost, $server, $modes, $gecos, $ip, $svsstamp) = @_[0,2..4,8,5,7,9,10,6];
	if(initial_synced() && !$svsstamp) {
		if ($ip) {
			wlog($main::rsnick, LOG_INFO(), "\002$rnick\002 is connecting from ".
				stringify_location(get_ip_location_aton($ip)));
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

	
		;
	wlog($main::rsnick, LOG_INFO(), "\002$nick\002 is connecting from ".
		stringify_location(get_ip_location_aton($ip)));
	delete $unwhois{lc $nick};
}

sub init() { }
sub begin() { }
sub end() { %unwhois = undef(); }
sub unload() { }

1;
