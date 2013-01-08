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

package SrSv::HostMask;

=head1 NAME

SrSv::HostMask - Functions for manipulating hostmasks

=head1 SYNOPSIS

 use SrSv::HostMask qw(normalize_hostmask hostmask_to_regexp parse_mask parse_hostmask make_hostmask);

=cut

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw( normalize_hostmask hostmask_to_regexp parse_mask parse_hostmask make_hostmask ) }

=pod

 normalize_hostmask($hostmask);

 # Heuristically convert random stuff entered by the user to normal *!*@* form
 $hostmask = normalize_hostmask($hostmask)


=cut

sub normalize_hostmask($) {
	my ($in) = @_;
	if($in !~ /[!@]/) { # we have to guess whether they mean nick or host
		if($in =~ /\./) { # nicks can't contain dots, so assume host
			#if($in =~ /\*/) {
				return '*!*@' . $in;
			#} else { # no wildcard, so add one
			#	return '*!*@*' . $in;
			#}
		} else { # no dots, so assume nick
			return $in . '!*@*';
		}
	}

	my @parts = ($in =~ /^(.*?)(?:!(.*?))(?:\@(.*?))?$/);
	my $out;

	for my $i (0..2) {
		$parts[$i] = '*' unless length($parts[$i]);
		$out .= $parts[$i] . @{['!', '@', '']}[$i];
	};

	return $out;
}


=pod

 my $re = hostmask_to_regexp('*!*@*.aol.com');
 if($hostmask =~ $re) {
 	# user is from AOL
 	# ...
 }

=cut

sub hostmask_to_regexp($) {
	my $mask = normalize_hostmask(shift);

	$mask =~ s/([^a-zA-Z0-9?*])/\\$1/g;
	$mask =~ s/\*/.*/g;
	$mask =~ s/\?/./g;

	return qr/^$mask$/i;
}

=pod

  my ($nick, $ident, $host) = parse_mask($mask);

  split a nick!ident@hostmask into components
  also lets you just do @host, or nick!

=cut

sub parse_mask($) {
	my ($mask) = @_;
	my ($mnick, $mident, $mhost);

	$mask =~ /^(.*?)(?:\!|\@|$)/;
	$mnick = $1;

	if($mask =~ /\!(.*?)(?:\@|$)/) {
		$mident = $1;
	} else {
		$mident = '';
	}

	if($mask =~ /\@(.*?)$/) {
		$mhost = $1;
	} else {
		$mhost = '';
	}

	return ($mnick, $mident, $mhost);
}

=pod

  my ($ident, $host) = parse_hostmask($mask);

  This is like parse_mask, but only will parse ident@host
  TKL in particular will use this.
  also could be used to parse email addresses

=cut

sub parse_hostmask($) {
	my ($mask) = @_;
	my ($mident, $mhost);

	if($mask !~ /@/) {
		return ('', $mask);
	}
	elsif($mask =~ /\!(.*?)(?:\@|$)/) {
		$mident = $1;
	} else {
		$mident = '';
	}

	if($mask =~ /\@(.*?)$/) {
		$mhost = $1;
	} else {
		$mhost = '';
	}

	return ($mident, $mhost);
}

=pod

  make_hostmask($type, $nick, $ident, $host);

  Some of this may be Unreal/cloak specific, but is mostly generic.
  No IPv6 support yet.
  $type is an integer, 0 - 10
   0 - *!user@host.domain
   1 - *!*user@host.domain
   2 - *!*@host.domain
   3 - *!*user@*.domain
   4 - *!*@*.domain
   5 - nick!user@host.domain
   6 - nick!*user@host.domain
   7 - nick!*@host.domain
   8 - nick!*user@*.domain
   9 - nick!*@*.domain
  10 - cross btwn 2 and 3, depending on if is a java-abcd1 ident or not
  
  10 is very SCnet specific (more accurately, it is specific to our java iframe)
  our java iframe is _not_ open source [yet]. I do not know if it will be either.

=cut
use SrSv::Conf2Consts qw( main );
our $ident_regexp = qr/^(@{[main_conf_ban_webchat_prefixes]})-/;

sub make_hostmask($$$$) {
	my ($type, $nick, $ident, $host) = @_;
	no warnings 'prototype'; #we call ourselves

	if($type == 10) {
		if ($ident =~ $ident_regexp) {
			return make_hostmask(3, $nick, $ident, $host);
		}
		else {
			return make_hostmask(2, $nick, $ident, $host);
		}
	}

	if($host =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) {
	# IPv4 address, dotted quad.
		my @octets = ($1, $2, $3, $4);
		if($type =~ /^[3489]$/) {
			$host = $octets[0].'.'.$octets[1].'.'.$octets[2].'.*';
		}
	}
	elsif($host =~ /^[A-Z0-9]{7}\.[A-Z0-9]{8}\.[A-Z0-9]{7}\.IP$/) { # should probably be case-sensitive.
	# 74BBBBF2.493EE1E3.CA7BA255.IP
		if($type =~ /^[3489]$/) {
			my @host = split(/\./, $host);
			pop @host; #discard last token ('IP')
			$host = '*.'.$host[2].'.IP'; # Unreal's cloak makes last group be the first two octets.
		}
	} else {
		# we assume normal hostname
		# We don't know what the cloak prefix will be, nor that it will be sane
		# Or even that we'll have a normal cloaked host (it could be a vhost)
		# So we can't restrict the character-class [much].
		# This could be improved further by popping off the
		# parts that are mostly numbers, if not a normal cloakhost.
		if($type =~ /^[3489]$/) {
			$host =~ /(.+?)\.(.+\.[a-z]{2,3})/i;
			$host = "*.$2";
		}
	}

	if($type =~ /^[1368]$/) {
		$ident =~ s/^\~//;
		$ident = "*$ident" unless (length($ident) > (ircd::IDENTLEN - 1));
	} elsif($type =~ /^[2479]$/) {
		$ident = '*';
	}

	if ($type < 5 and $type >= 0) {
		$nick = '*';
	}

	return ($nick, $ident, $host);
}

1;
