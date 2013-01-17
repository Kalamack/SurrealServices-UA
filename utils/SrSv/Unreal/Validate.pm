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

package SrSv::IRCd::Validate;

use SrSv::HostMask qw( normalize_hostmask );
use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(valid_server valid_nick validate_chmodej validate_chmodef validate_chmodes validate_ban); }

our $valid_nick_re = qr/^[][a-zA-Z`\\\|{}_^][][a-zA-Z0-9`\\\|{}_^-]*$/;

our $s_chars = qr/[a-zA-Z0-9_.-]/;
our $valid_server_re = qr/^[a-zA-Z]$s_chars*\.$s_chars*$/;

sub valid_server($) {
	return $_[0] =~ $valid_server_re;
}

sub valid_nick($) {
	return $_[0] =~ $valid_nick_re;
}

sub validate_chmodej($) {
	my ($joins, $seconds) = split(/:/, @_);
	return 1 unless (defined $joins and ($joins <= 255 and $joins >=1));
	return 1 unless (defined $seconds and ($seconds <= 999 and $seconds >=1));
	return 0;
}

my %chmodef_types = (
	c => [{'m' => 1, 'M' => 1}, 0, 60],
	j => [{'R' => 1}, 0, 60],
	k => [{'K' => 1}, 0, 60],
	m => [{'M' => 1}, 0, 60],
	n => [{'N' => 1}, 0, 60],
	t => [{'b' => 1}, -1],
);

sub validate_chmodef($) {
	my ($block, $seconds) = split(/:/, $_[0]);
	# [4j#i5,3k#K7,15m#M10,5n#N5,6t#b]:5
	
	return 0 unless (defined($seconds) and ($seconds <= 999 and $seconds > 0));

	$block =~ s/(\[|\])//g;

	foreach my $tuple (split(',', $block)) {
		my ($limit, $action) = split('#', $tuple);
		my ($type, $time);
		{
			$limit =~ /([0-9]{1,3})([a-z])$/;
			($time, $type) = ($1, $2);
		}
		return 0 unless defined($chmodef_types{$type});

		my $restrictions = $chmodef_types{$type};
		if($restrictions == -1) {
			return 0 if defined($action);
		} else {
			my ($alt, $time) = split(//, $action, 2);
			return 0 if (defined($action) and $restrictions->[0]->{$a});
		}
	}
	return 1;
}

sub validate_chmodes($@) {
	my ($modes_in, @parms_in) = @_;
	my ($modes_out, @parms_out);
	my $sign = '+';
	foreach my $mode (split(//, $modes_in)) {
		my $parm;
		if ($mode =~ /^[+-]$/) {
			$sign = $mode;
		}
		elsif ($mode =~ /^[qaohv]$/) {
			$parm = shift @parms_in;
			unless(valid_nick($parm)) {
				next;
			}
		}
		else {
			$parm = shift @parms_in if $mode =~ /^[beIkflLj]$/;
			($mode, $parm) = validate_chmode($mode, $sign, $parm);
		}
		push @parms_out, $parm if $parm;
		$modes_out .= $mode;
	}
	return ($modes_out, @parms_out);
}

sub validate_extban($) {
# Unreal 3.3 will have chained extbans.
	my ($parm) = @_;
	my ($type, $payload) = split(':', $parm, 2);
	$type =~ s/^\~//;
	if($type eq 'q' or $type eq 'n') {
		return 1 if($payload =~ /^(.+)!(.+)@(.+)$/);
	} elsif($type eq 'c') {
		return 1 if($payload =~ /^[~&@%+]?#.{0,29}$/);
	} elsif($type eq 'r') {
		return 1; # how can this be invalid anyway?
	} elsif($type eq 'T') {
		my ($action, $mask) = split(':', $payload);
		return 1 if ($action =~ /^(block|censor)$/i);
	}
}

sub validate_ban($) {
	my ($parm) = @_;
	if($parm =~ /^(.+)!(.+)@(.+)$/) {
		# nothing obviously wrong
		return $parm;
	}
	elsif($parm =~ /^\~[qncrT]:/i) {
		# nothing obviously wrong
		# or at least, we know nothing about it.
		return $parm if validate_extban($parm);
	} else {
		# hopefully this will sufficiently sanitize it for the ircd.
		# if this is wrong, it may cause desyncs in the ban list.
		# thankfully most of those should be invalid bans and won't match on anything.
		return normalize_hostmask($parm);
	}
	return undef;
}

sub validate_chmode($$;$) {
	my ($mode, $sign, $parm) = @_;
	use Switch;
	switch($mode) {
	#CHANMODES=beI,kfL,lj,psmntirRcOAQKVCuzNSMTG
		case /^[beI]$/ { 
			$parm = validate_ban($parm);
			return ($mode, $parm) if $parm;
		}
		case 'f' {
			return ($mode, $parm) if $sign eq '-' or validate_chmodef($parm);
		}
		case 'k' {
			$parm = '*' if $sign eq '-' and !defined($parm);
			return ($mode, $parm)
		}
		case 'l' {
			$parm = '1' if $sign eq '-' and !defined($parm);
			return ($mode, $parm) if $parm =~ /^\d+$/;
		}
		case 'L' {
			$parm = '*' if $sign eq '-' and !defined($parm);
			return ($mode, $parm) if $parm =~ /^#/;
		}
		case 'j' {
			return ($mode, $parm) if validate_chmodej($parm);
		}
		case /^[psmntirRcOAQKVCuzNSMTG]$/ { return ($mode, undef); }
		else { return undef; }
	}
}

1;
