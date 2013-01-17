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

package SrSv::Time;

use strict;
use integer;
use Time::Local;

use Exporter 'import';
BEGIN { our @EXPORT = qw( @months @days
			gmtime2 tz_time gmt_date local_date
			time_ago time_rel time_rel_long_all
			parse_time split_time
			get_nextday get_nextday_time get_monthdays
			get_nexthour get_nexthour_time
			)
}

our @months = ( 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' );
our @days = ( 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' );

sub _time_text($) {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime(shift);
	return $mday.'/'.$months[$mon].'/'. substr($year, -2, 2).' '.
		sprintf("%02d:%02d", $hour, $min);
}

sub gmtime2(;$) {
	my ($time) = @_;
	$time = time() unless $time;
	return _time_text($time) . ' GMT';
}

sub tz_time($;$) {
	my ($tzoffset, $time) = @_;
	return _time_text(($time ? $time : time()) + tz_to_offset($tzoffset));
}

sub tz_to_offset($) {
	my ($offset) = @_;
	# offset is a signed integer corresponding to 1/4 hr increments
	# or 900 seconds (15 minutes)
	return ($offset * 900); 
}

sub _date_text($) {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime(shift);
	return (!wantarray ? ($year+1900).' '.$months[$mon].' '.$mday : ($year + 1900, $mon+1, $months[$mon], $mday));
}

sub gmt_date(;$) {
	my ($time) = @_;
	$time = time() unless $time;
	return _date_text($time);
}

sub local_date($;$) {
	my ($tzoffset, $time) = @_;
	return _date_text(($time ? $time : time()) + tz_to_offset($tzoffset));
}

sub parse_time($) {
	my ($str) = @_;
	my $out;
	$str =~ s/^\+//;
	$str = lc($str);

	my @vals = split(/(?<!\d)(?=\d+\w)/, $str);

	foreach my $val (@vals) {
		$val =~ /(\d+)(\w)/;
		my ($num, $pos) = ($1, $2);

		if($pos eq 'w') { $num *= (86400*7) }
		elsif($pos eq 'd') { $num *= 86400 }
		elsif($pos eq 'h') { $num *= 3600 }
		elsif($pos eq 'm') { $num *= 60 }
		elsif($pos ne 's') { return undef }

		$out += $num;
	}

	return $out;
}

sub split_time($) {
	no integer; # We might want to pass in a float value for $difference
	my ($difference) = @_;
	my ($weeks, $days, $hours, $minutes, $seconds);
	$seconds 	=  $difference % 60 + ($difference - int($difference));
	$difference 	= ($difference - $seconds) / 60;
	$minutes    	=  $difference % 60;
	$difference 	= ($difference - $minutes) / 60;
	$hours 		=  $difference % 24;
	$difference 	= ($difference - $hours)   / 24;
	$days 		=  $difference % 7;
	$weeks		= ($difference - $days)    /  7;

	return ($weeks, $days, $hours, $minutes, $seconds);
}

sub time_ago($;$) {
	return time_rel(time() - $_[0], $_[1]);
}

sub time_rel($;$) {
	my ($time, $all) = @_;

	if ($time >= 2419200) { # 86400 * 7 * 4
		my ($years, $months, $weeks, $days) = __time_rel_long(time() - $time);
		if($years or $months or $weeks or $days) {
			my $text = '';
			if($years) {
				$text = "$years year".($years !=1 ? 's' : '');
			}
			if($months) {
				$text .= (length($text) ? ' ' : '')."$months month".($months !=1 ? 's' : '');
				if ($years && !$all) {
					return $text;
				}
			}
			if($weeks) {
				$text .= (length($text) ? ' ' : '')."$weeks week".($weeks !=1 ? 's' : '');
				if ($months && !$all) {
					return $text;
				}
			}
			if($days) {
				$text .= (length($text) ? ' ' : '')."$days day".($days !=1 ? 's' : '');
=cut
				if ($weeks && !$all) {
					return $text;
				}
=cut
			}
			return $text;
=cut
			return ( $years ? "$years year".($years !=1 ? 's' : '') : '' ).
				( $months ? ($years ? ', ' : '')."$months month".( $months!=1 ? 's' : '' ) : '').
				( $weeks ? (($years or $months) ? ', ' : '')."$weeks week".( $weeks!=1 ? 's' : '' ) : '').
				( $days ? (($months or $years or $weeks) ? ', ' : '')."$days day".($days!=1 ? 's' : '') : '' )
				;
=cut
		}
	}

	my ($weeks, $days, $hours, $minutes, $seconds) = split_time($time);

	my $text;
#	if($time >= 604800) { # 86400 * 7 }
	if($weeks) {
		$text = "$weeks week".($weeks!=1 ? 's' : '');
=cut
		return "$weeks week".
			($weeks!=1 ? 's' : '').
			", $days day".
			($days!=1 ? 's' : '');
=cut
	}
	if($days) {
		$text .= (length($text) ? ' ' : '')."$days day".($days!=1 ? 's' : '');
		return $text if $weeks && !$all;
=cut
		return "$days day".
			($days!=1 ? 's' : '').
			", $hours hour".
			($hours!=1 ? 's' : '');
=cut
	}
	if($hours) {
		$text .= (length($text) ? ' ' : '')."$hours hour".($hours!=1 ? 's' : '');
		return $text if $days && !$all;
=cut
		return "$hours hour".
			($hours!=1 ? 's' : '').
			", $minutes minute".
			($minutes!=1 ? 's' : '');
=cut
	}
	if($minutes) {
		$text .= (length($text) ? ' ' : '')."$minutes minute".($minutes!=1 ? 's' : '');
		return $text if $hours && !$all;
=cut		return "$minutes minute".
		($minutes!=1 ? 's' : '').
		", $seconds second".
		($seconds!=1 ? 's' : '');
=cut
	}
	if($seconds) {
		$text .= (length($text) ? ' ' : '')."$seconds second".($seconds!=1 ? 's' : '');
=cut
		return "$seconds second".
		($seconds!=1 ? 's' : '');
=cut
	}
	if(!($weeks || $days || $hours || $minutes || $seconds) ) {
		return '0 seconds';
	}
	return $text;
}

# This is for cases over 4 weeks, when we need years, months, weeks, and days
sub __time_rel_long($;$) {
	my ($lesser_time, $greater_time) = @_;
	$greater_time = time() unless $greater_time;

	my ($sec1, $min1, $hour1, $mday1, $month1, $year1, undef, undef, undef) = gmtime($lesser_time);
	my ($sec2, $min2, $hour2, $mday2, $month2, $year2, undef, undef, undef) = gmtime($greater_time);

	my ($result_years, $result_months, $result_weeks, $result_days,
		$result_hours, $result_mins, $result_secs);
	$result_secs = $sec2 - $sec1; 
	$result_mins = $min2 - $min1;
	if($result_secs < 0) {
		$result_secs += 60; $result_mins--;
	}
	$result_hours = $hour2 - $hour1;
	if($result_mins < 0) {
		$result_mins += 60; $result_hours--;
	}
	$result_days = $mday2 - $mday1;
	if($result_hours < 0) {
		$result_hours += 24; $result_days--;
	}
	$result_months = $month2 - $month1;
	if($result_days < 0) {
		$result_days += get_monthdays(
			($month2 == 0 ? 11 : $month2 - 1),
			($month2 == 0 ? $year2 - 1: $year2));
		$result_months--;
	}
	# The following division relies on integer division, as 'use integer' is decl'd above.
	$result_weeks = $result_days / 7;
	$result_days = $result_days % 7;
	$result_years = $year2 - $year1;
	if($result_months < 0) {
		$result_months += 12; $result_years--
	}
	return ($result_years, $result_months, $result_weeks, $result_days, $result_hours, $result_mins, $result_secs);
}

# Apologize about the unreadability, but the alternative is about 4 times as long
# This is for use when we want as precise a time-difference as possible.
sub time_rel_long_all($;$) {
	my ($lesser_time, $greater_time) = @_;
	$greater_time = time() unless $greater_time;
	my ($years, $months, $weeks, $days, $hours, $minutes, $seconds) = __time_rel_long($lesser_time);
	return ( $years ? "$years year".($years !=1 ? 's' : '') : '' ).
		( $months ? ($years ? ', ' : '')."$months month".( $months!=1 ? 's' : '' ) : '').
		( $weeks ? (($years or $months) ? ', ' : '')."$weeks week".( $weeks!=1 ? 's' : '' ) : '').
		( $days ? (($months or $years or $weeks) ? ', ' : '')."$days day".($days!=1 ? 's' : '') : '' ).
		( $hours ? (($days or $months or $years or $weeks) ? ', ' : '')."$hours hour".($hours!=1 ? 's' : '') : '' ).
		( $minutes ? (($hours or $days or $months or $years or $weeks) ? ', ' : '')."$minutes minute".($minutes!=1 ? 's' : '') : '' ).
		( $seconds ? (($minutes or $days or $months or $years or $weeks) ? ', ' : '')."$seconds second".($seconds!=1 ? 's' : '') : '' )
		;

}

sub get_nextday($$$) {
	my ($mday, $mon, $year) = @_;
	$year += 1900 if $year < 1582; #Gregorian calendar was somewhere around here...

	my $monthdays = get_monthdays($mon, $year);
	$mday++;
	if($mday > $monthdays) {
		$mday %= $monthdays;
		$mon++;
	}
	if($mon >= 12) {
		$mon %= 12;
		$year++;
	}
	return ($mday, $mon, $year);
}
sub get_nextday_time(;$) {
	my ($time) = @_;
	$time = time() unless $time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
	return Time::Local::timegm(0,0,0,get_nextday($mday, $mon, $year));
}

sub get_nexthour($$$$) {
	my ($hour, $mday, $mon, $year) = @_;
#	$minute++;
#	if($minute >= 60) {
#		$minute %= 60;
#		$hour++;
#	}
	$hour++;
	if($hour >= 24) {
		$hour %= 24;
		($mday, $mon, $year) = get_nextday($mday, $mon, $year)
	}
	return ($hour, $mday, $mon, $year);
}
sub get_nexthour_time(;$) {
	my ($time) = @_;
	$time = time() unless $time;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
	return Time::Local::timegm(0,0,get_nexthour($hour, $mday, $mon, $year));
}

# This function is only correct/valid for Gregorian dates.
# Not IVLIAN dates.
sub get_monthdays {
# $month is 0-11 not 1-12
	my ($month, $year) = @_;
	sub m30($) { return 30; }
	sub m31($) { return 31; }
	sub mFeb($) {
		my ($year) = @_;
		if(($year % 100 and !($year % 4)) or !($year % 400)) {
			return 29;
		} else {
			return 28;
		}
	}
	# this is the common table, but note +1 below
	# as gmtime() and friends return months from 0-11 not 1-12
	my %months = (
		1 => \&m31,
		3 => \&m31,
		5 => \&m31,
		7 => \&m31,
		8 => \&m31,
		10 => \&m31,
		12 => \&m31,

		4 => \&m30,
		6 => \&m30,
		9 => \&m30,
		11 => \&m30,

		2 => \&mFeb,
	);

	$year += 1900 if $year < 1582; #Gregorian calendar was somewhere around here...
	return $months{$month+1}($year);
}

1;
