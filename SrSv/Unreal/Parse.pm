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

package SrSv::IRCd::Parse;

use strict;

use Exporter 'import';
# parse_sjoin shouldn't get used anywhere else, as we never produce SJOINs
# parse_tkl however is used for loopbacks.
BEGIN { our @EXPORT_OK = qw(parse_line parse_tkl parse_addline) }

# FIXME
BEGIN { *SJB64 = \&ircd::SJB64; *CLK = \&ircd::CLK; *NICKIP = \&ircd::NICKIP; }

use SrSv::Conf 'main';

use SrSv::Debug;
use SrSv::IRCd::State qw($ircline $remoteserv create_server get_server_children set_server_state get_server_state %IRCd_capabilities);
use SrSv::IRCd::Queue qw(queue_size);
use SrSv::IRCd::IO qw( ircsend  ircsendimm);
use SrSv::Unreal::Modes qw(%opmodes);

# Unreal uses its own modified base64 for everything except NICKIP
use SrSv::Unreal::Base64 qw(b64toi itob64);
use SrSv::User '/./';
# Unreal uses unmodified base64 for NICKIP.
# Consider private implementation,
# tho MIME's is probably faster
use MIME::Base64;
use Data::Dumper;
# FIXME
use constant {
	# Wait For
	WF_NONE => 0,
	WF_NICK => 1,
	WF_CHAN => 2,
	WF_ALL => 3,
};

use SrSv::Shared qw(@servernum);

our %cmdhash;

sub parse_line($) {
	my ($in) = @_;
	if (!$in) {
		return;
	}
	my $cmd;

	if($in =~ /^(?:@|:)(\S+) (\S+)/) {
		$cmd = $2;
	}
	elsif ($in =~ /^(\S+)/) {
		$cmd = $1;
	}
	my $sub = $cmdhash{$cmd};
	unless (defined($sub)) {
		print "Bailing out from $ircline:$cmd for lack of cmdhash\n" if DEBUG();
		return undef();
	}
	my ($event, $src, $dst, $wf, @args) = &$sub($in);
	unless (defined($event)) {
		print "Bailing out from $ircline:$cmd for lack of event\n" if DEBUG;
		return undef();
	}
	#return unless defined $event;

	my (@recipients, @out);
	if(defined($dst)) {
		#$args[$dst] = lc $args[$dst];
		@recipients = split(/\,/, $args[$dst]);
	}
	#if(defined($src)) { $args[$src] = lc $args[$src]; }

	if(@recipients > 1) {
		foreach my $rcpt (@recipients) {
			$args[$dst] = $rcpt;
			push @out, [$event, $src, $dst, $wf, [@args]];
		}
	} else {
		@out = [$event, $src, $dst, $wf, [@args]];
	}

	return @out;
}
sub parse_sjoin($$$$) {
	my ($server, $ts, $cn, $parms) = @_;
	my (@users, @bans, @excepts, @invex, @blobs, $blobs, $chmodes, $chmodeparms);

	$server = '' unless $server;

	if($parms =~ /^:(.*)/) {
		$blobs = $1;
	} else {
		($chmodes, $blobs) = split(/ :/, $parms, 2);
		($chmodes, $chmodeparms) = split(/ /, $chmodes, 2);
	}
	@blobs = split(/ /, $blobs);

	foreach my $x (@blobs) {
		if($x =~ /^(\&|\"|\')(.*)$/) {
			my $type;
			push @bans, $2 if $1 eq '&';
			push @excepts, $2 if $1 eq '"';
			push @invex, $2 if $1 eq "\'";
		} else {
			$x =~ /^([*~@%+]*)(.*)$/;
			my ($prefixes, $nick) = ($1, $2);
			my @prefixes = split(//, $prefixes);
			my $op = 0;
			foreach my $prefix (@prefixes) {
				$op |= $opmodes{q} if ($prefix eq '*');
				$op |= $opmodes{a} if ($prefix eq '~');
				$op |= $opmodes{o} if ($prefix eq '@');
				$op |= $opmodes{h} if ($prefix eq '%');
				$op |= $opmodes{v} if ($prefix eq '+');
			}

			push @users, { NICK => $nick, __OP => $op };
		}
	}

	return ($server, $cn, $ts, $chmodes, $chmodeparms, \@users, \@bans, \@excepts, \@invex);
}
sub parse_tkl ($) {
	my ($in) = @_;
	# This function is intended to accept ALL tkl types,
	# tho maybe not parse all of them in the first version.

	# Discard first token, 'TKL'
	my (undef, $sign, $type, $params) = split(/ /, $in, 4);

	# Yes, TKL types are case sensitive!
	# also be aware (and this applies to the net.pm generator functions too)
	# This implementation may appear naiive, but Unreal assumes that, for a given
	# TKL type, that all parameters are non-null.
	# Thus, if any parameters ARE null, Unreal WILL segfault.
	## Update: this problem may have been fixed since Unreal 3.2.2 or so.
	if ($type eq 'G' or $type eq 'Z' or $type eq 's' or $type eq 'Q') {
		# format is
		# TKL + type ident host setter expiretime settime :reason
		# TKL - type ident host setter
		# for Q, ident is always '*' or 'h' (Services HOLDs)
		if ($sign eq '+') {
			my ($ident, $host, $setter, $expire, $time, $reason) = split(/ /, $params, 6);

			$reason =~ s/^\://;
			return ($type, +1, $ident, $host, $setter, $expire, $time, $reason);
		}
		elsif($sign eq '-') {
			my ($ident, $host, $setter) = split(/ /, $params, 3);
			return ($type, -1, $ident, $host, $setter);
		}
	}
	elsif($type eq 'F') {
		# TKL + F cpnNPq b saturn!attitude@netadmin.SCnet.ops 0 1099959668 86400 Possible_mIRC_DNS_exploit :\/dns (\d+\.){3}\d
		# TKL + F u g saturn!attitude@saturn.netadmin.SCnet.ops 0 1102273855 604800 sploogatheunbreakable:_Excessively_offensive_behavior,_ban_evasion. :.*!imleetnig@.*\.dsl\.mindspring\.com
		# TKL - F u Z tabris!northman@tabris.netadmin.SCnet.ops 0 0 :do_not!use@mask
		if ($sign eq '+') {
			my ($target, $action, $setter, $expire, $time, $bantime, $reason, $mask) = split(/ /, $params, 8);
			$mask =~ s/^\://;
			return ($type, +1, $target, $action, $setter, $expire, $time, $bantime, $reason, $mask);
		}
		elsif($sign eq '-') {
			my ($target, $action, $setter, $expire, $time, $mask) = split(/ /, $params, 6);
			$mask =~ s/^\://;
			return ($type, -1, $target, $action, $setter, $mask);
		}
	}
}

sub PING($) {
	my ($event, $src, $dst, @args);
	$_[0] =~ /^(?:8|PING) :(\S+)$/;
	# ($event, $src, $dst, $args)
	return ('PING', undef, undef, WF_NONE, $1);
}
sub EOS($) {
	my $event;
	$_[0] =~ /^(@|:)(\S+) (?:EOS|ES)/; # Sometimes there's extra crap on the end?
	my $server;
	if ($1 eq '@') {
		$server = $servernum[b64toi($2)];
	}
	else {
		$server = $2;
	}
	print "SERVER $server\n";
	set_server_state($server, 1);
	return undef() unless get_server_state($remoteserv);
	if($server eq $remoteserv) { $event = 'SEOS' } else { $event = 'EOS' }
	print "Ok. we had EOS\n";
	return ($event, undef, undef, WF_ALL, $server);
}

sub SERVER($) {
	#ircd::debug($_[0]) if $debug;

	if($_[0] =~ /^(?:SERVER|\') (\S+) (\S+) :(U[0-9]+)-([A-Za-z0-9]+)-([0-9]+) (.*)$/) {
		# SERVER test-tab.surrealchat.net 1 :U2307-FhinXeOoZEmM-200 SurrealChat
		# cmd, servername, hopCount, U<protocol>-<buildflags>-<numeric> infoLine
		$remoteserv = $1;
		create_server($1);
		$servernum[$5] = $1;

		return ('SERVER', undef, undef, WF_ALL, undef, $1, $2, $6, $5, $3, $4);
		# src, serverName, numHops, infoLine, serverNumeric, protocolVersion, buildFlags
	}
	elsif($_[0] =~ /^(:|@)(\S+) (?:SERVER|\') (\S+) (\d+) (\d+) :(.*)$/) {
	# @38 SERVER test-hermes.surrealchat.net 2 100 :SurrealChat
	# source, cmd, new server, hopCount, serverNumeric, infoLine
		my ($numeric, $name);
		if ($1 eq '@') {
			$name = $servernum[b64toi($2)];
		}
		else {
			$name = $2;
		}
		create_server($3, $name);
		$servernum[$5] = $3;

		return ('SERVER', undef, undef, WF_ALL, $name, $3, $4, $6, $5);
		# src, serverName, numHops, infoLine, serverNumeric
	}
	if($_[0] =~ /^(?:SERVER|\') (\S+) (\S+) :(.*)$/) {
		$remoteserv = $1;
		create_server($1);
		return ('SERVER', undef, undef, WF_ALL, undef, $1, $2, $3);
		# src, serverName, numHops, infoLine
	}
	elsif($_[0] =~ /^:(\S+) (?:SERVER|\') (\S+) (\d+) :(.*)$/) {
		# source, new server, hop count, description
		create_server($2, $1);
		return ('SERVER', undef, undef, WF_ALL, $1, $2, $3, $4);
		# src, serverName, numHops, infoLine
	}
	elsif ($_[0] =~ /SERVER (\S+) (\S+) (\d+) (\S+) :(.*)$/) {
		#SERVER inspircd.erry.omg mypass 0 583 :erry World
		#SERVER servername password hopcount SID :Server Desc
		$remoteserv = $4;
		create_server ($4);
		#since from now on we'll be getting commands as sent from the SID it's much wiser to keep that than the name.
		return ("SERVER", undef, undef, WF_ALL, undef, $1, $3, $5, $4);
	}
}

sub SQUIT($) {
	if($_[0] =~ /^(?:SQUIT|-) (\S+) :(.*)$/) {
		my $list = [get_server_children($1)];
		set_server_state($1, undef());
		return ('SQUIT', undef, undef, WF_ALL, undef, $list, $2);
	}
	elsif($_[0] =~ /^(:|@)(\S+) (?:SQUIT|-) (\S+) :(.*)$/) {
		my $name;
		if ($1 eq '@') {
			$name = $servernum[b64toi($2)];
		}
		else {
			$name = $2;
		}
		my $list = [get_server_children($3)];
		set_server_state($3, undef());
		return ('SQUIT', undef, undef, WF_ALL, $name, $list, $4);
	}
}

sub NETINFO($) {
	$_[0] =~ /^(?:NETINFO|AO) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) :(.*)$/;
	return ('NETINFO', undef, undef, WF_NONE, $1, $2, $3, $4, $5, $6, $7, $8);
}

sub PROTOCTL($) {
	$_[0] =~ /^PROTOCTL (.*)$/;
	return ('PROTOCTL', undef, undef, WF_NONE, $1);
}

sub JOIN($) {
	$_[0] =~ /^:(\S+) (?:C|JOIN) (\S+)$/;
	my $user = { NICK => $1 };
	get_user_id ($user);
	return ('JOIN', undef, 1, WF_CHAN, $user, $2);
}

sub SJOIN($) {
	if ($_[0] =~ /^(?:\~|SJOIN) (\S+) (\S+) (.*)$/) {
		my ($ts, $cn, $payload) = ($1, $2, $3);
		if ($ts =~ s/^!//) {
			$ts = b64toi($ts);
		}
		return ('SJOIN', undef, undef, WF_CHAN, parse_sjoin($remoteserv, $ts, $cn, $payload));
	}
	elsif($_[0] =~ /^(@|:)(\S+) (?:\~|SJOIN) (\S+) (\S+) (.*)$/) {
		print "SJOIN\n";
		my ($server, $ts, $cn, $payload) = ($2, $3, $4, $5);
		if ($1 eq '@') {
			$server = $servernum[b64toi($2)];
		}
		else {
			$server = $2;
		}
		if ($ts =~ s/^!//) {
			$ts = b64toi($ts);
		}
		return ('SJOIN', undef, undef, WF_CHAN, parse_sjoin($server, $ts, $cn, $payload));
	}
}

sub PART($) {
	my $user;
	
	if($_[0] =~ /^:(\S+) (?:D|PART) (\S+) :(.*)$/) {
		$user = {NICK => $1};
		get_user_id ($user);
		return ('PART', undef, 0, WF_CHAN, $user, $2, $3);
	}
	elsif($_[0] =~ /^:(\S+) (?:D|PART) (\S+)$/) {
		$user = {NICK => $1};
		get_user_id ($user);
		return ('PART', undef, 0, WF_CHAN, $user, $2, undef);
	}
}
sub MODE($) {
	my $user;
	
	if($_[0] =~ /^(@|:)(\S+) (?:G|MODE) (#\S+) (\S+) (.*)(?: \d+)?$/) {
		my $name;
		if ($1 eq '@') {
			$name = $servernum[b64toi($2)];
			$user = {NICK => $name};
		}
		else {
			$name = $2;
			$user = { NICK=>$name};
			get_user_id ($user);
		}
		return ('MODE', undef, 1, WF_ALL, $user, $3, $4, $5);
	}
	elsif($_[0] =~ /^:(\S+) (?:G|MODE) (\S+) :(\S+)$/) {
		# We shouldn't ever get this, as UMODE2 is preferred
		$user = { NICK => $1 };
		get_user_id($user);
		return ('UMODE', 0, 0, WF_ALL, $user, $3);
	}

}

sub MESSAGE($) {
	my ($event, @args);
	if($_[0] =~ /^(@|:)(\S+) (?:\!|PRIVMSG) (\S+) :(.*)$/) {
	
		my ($name, $srcUser, $dstUser) ;
		if ($1 eq '@') {
			$name = $servernum[b64toi($2)];
			$srcUser = {NICK=>$name};
		}
		else {
			$name = $2;
			$srcUser = {NICK=>$name};
			get_user_id ($srcUser);
		}
		my $dest = $3;
		$dstUser = {NICK=>$dest};
		$event = 'PRIVMSG'; @args = ($srcUser, $dstUser, $4);
	}
	elsif($_[0] =~ /^(@|:)(\S+) (?:B|NOTICE) (\S+) :(.*)$/) {
		my $name;
		if ($1 eq '@') {
			$name = $servernum[b64toi($2)];
		}
		else {
			$name = $2;
		}
		$event = 'NOTICE'; @args = ($name, $3, $4);
	}
	$args[1] =~ s/\@${main_conf{local}}.*//io;

	if(queue_size > 50 and $event eq 'PRIVMSG' and $args[1] !~ /^#/ and $args[2] =~ /^\w/) {
		ircd::notice($args[1], $args[0], "It looks like the system is busy. You don't need to do your command again, just hold on a minute...");
	}

	return ($event, 0, 1, WF_ALL, @args);
}

sub AWAY($) {
	if($_[0] =~ /^:(\S+) (?:6|AWAY) :(.*)$/) {
		my $user = {NICK=>$1};
		get_user_id($user);
		return ('AWAY', undef, undef, WF_ALL, $user, $2);
	}
	elsif($_[0] =~ /^:(\S+) (?:6|AWAY)$/) {
		my $user = {NICK => $1};
		get_user_id ($user);
		return ('BACK', undef, undef, WF_ALL, $user);
	}
}

sub NICK($) {
	my ($event, @args);
	#>> 32 :erry_ & erry2 :1310809099
	if($_[0] =~ /^:(\S+) (?:NICK|\&) (\S+) :?(\S+)$/) {
		my $user = {NICK=>$1};		
		return ('NICKCHANGE', undef, undef, WF_NICK, $user, $2, $3);
	}
	elsif(CLK && NICKIP && $_[0] =~ /^(?:NICK|\&) (\S+) (\d+) (\S+) (\S+) (\S+) (\S+) (\d+) (\S+) (\S+) (\S+) (\S+) :(.*)$/) {
#NICK Guest57385 1 !14b7t0 northman tabriel.tabris.net 38 0 +iowghaAxNWzt netadmin.SCnet.ops SCnet-3B0714C4.tabris.net CgECgw== :Sponsored By Skuld
#NICK outis 1 !14corv northman localhost 38 0 +iowghaAxNWzt tabris.netadmin.SCnet.ops SCnet-D8C01838 AAAAAAAAAAAAAAAAAAAAAQ== :Sponsored By Skuld
		my ($nick, $hops, $ts, $ident, $host, $server, $stamp, $modes, $vhost, $cloakhost, $IP, $gecos) =
			($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);
		if ($ts =~ s/^!//) {
			$ts = b64toi($ts);
		}
		if (SJB64 and length($server) <= 2 and $server !~ /\./) {
			$server = $servernum[b64toi($server)];

		}
		if((length($IP) > 8)) {
			#$IP = Socket6::inet_ntop(AF_INET6, MIME::Base64::decode($IP));
		} else {
			$IP = join('.', unpack('C4', MIME::Base64::decode($IP)));
		}
		my $user = {NICK=>$nick};
		return ('NICKCONN', undef, undef, WF_NICK, $user, $hops, $ts, $ident, $host, $server, $stamp, $modes, $vhost,
			$gecos, $IP, $cloakhost
		);
	}
	elsif(!CLK && NICKIP && $_[0] =~ /^(?:NICK|\&) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) :(.*)$/) {
#NICK tab 1 1116196525 northman tabriel.tabris.net test-tab.surrealchat.net 0 +iowghaAxNWzt netadmin.SCnet.ops CgECgw== :Sponsored by Skuld
		my ($nick, $hops, $ts, $ident, $host, $server, $stamp, $modes, $vhost, $IP, $gecos) =
			($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);
		if ($ts =~ s/^!//) {
			$ts = b64toi($ts);
		}
		if (SJB64 and length($server) <= 2 and $server !~ /\./) {
			$server = $servernum[b64toi($server)];

		}
		if( length($IP) > 8) {
			$IP = Socket6::inet_ntop(AF_INET6, MIME::Base64::decode($IP));
		} else {
			$IP = join('.', unpack('C4', MIME::Base64::decode($IP)));
		}
		my $user = {NICK=>$nick};
		return ('NICKCONN', undef, undef, WF_NICK, $user, $hops, $ts, $ident, $host, $server, $stamp, $modes, $vhost,
			$gecos, $IP
		);
	}
	elsif(!CLK && !NICKIP && $_[0] =~ /^(?:NICK|\&) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) :(.*)$/) {
#NICK tab 1 1116196525 northman tabriel.tabris.net test-tab.surrealchat.net 0 +iowghaAxNWzt netadmin.SCnet.ops :Sponsored by Skuld
		my ($nick, $hops, $ts, $ident, $host, $server, $stamp, $modes, $vhost, $gecos) =
			($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
		if ($ts =~ s/^!//) {
			$ts = b64toi($ts);
		}
		if (SJB64 and length($server) <= 2 and $server !~ /\./) {
			$server = $servernum[b64toi($server)];

		}
		my $user = {NICK=>$nick};
		return ('NICKCONN', undef, undef, WF_NICK, $user, $hops, $ts, $ident, $host, $server, $stamp, $modes,
			$vhost, $gecos);
	}
}

sub QUIT($) {
	print "?????????/";
	$_[0] =~ /^:(\S+) (?:QUIT|\,) :(.*)$/;
	my $user = { NICK=>$1 };
	return ('QUIT', 0, undef, WF_NICK, $user, $2);
}

sub KILL($) {
	$_[0] =~ /^:(\S+) KILL (\S+) :(.*)$/;
	my $murderer = {NICK=>$1};
	my $victim = {NICK=>$2};
	return ("KILL", 0, 1, WF_NICK, $murderer, $victim, $3, undef);
}
sub KICK($) {
#:tabris KICK #diagnostics SurrealBot :i know you don't like this. but it's for science!
	$_[0] =~ /^(@|:)(\S+) (?:KICK|H) (\S+) (\S+) :(.*)$/;
	# source, chan, target, reason
	#$src = 0; #$dst = 2;
	my $name;
	if ($1 eq '@') {
		$name = $servernum[b64toi($2)];
	}
	else {
		$name = $2;
	}
	my $user = {NICK => $name};
	return ('KICK', 0, undef, WF_CHAN, $user, $3, $4, $5);
}

sub HOST($) {
	if($_[0] =~ /^:(\S+) (?:CHGHOST|AL) (\S+) (\S+)$/) {
	#:Agent CHGHOST tabris tabris.netadmin.SCnet.ops
		return ('CHGHOST', 0, 1, WF_CHAN, $1, $2, $3);
		#setter, target, vhost
	}
	elsif($_[0] =~ /^:(\S+) (?:SETHOST|AA) (\S+)$/) {
	#:tabris SETHOST tabris.netadmin.SCnet.ops
		return ('CHGHOST', 0, 1, WF_CHAN, $1, $1, $2);
	}

	elsif ($_[0] =~ /^:(?:\S* )?302 (\S+) :(\S+?)\*?=[+-].*?\@(.*)/) {
	#:serebii.razorville.co.uk 302 leif :Jesture=+~Jesture00@buzz-3F604D09.sympatico.ca
		return ('CHGHOST', 0, 1, WF_CHAN, $1, $2, $3);
	}
}


sub USERIP($) {
	$_[0] =~ /^:(?:\S* )?340 (\S+) :(\S+?)\*?=[+-].*?\@((?:\.|\d)*)/;
	return ('USERIP', 0, 1, WF_CHAN, $1, $2, $3);
}

sub IDENT($) {
	if($_[0] =~ /^:(\S+) (?:CHGIDENT|AL) (\S+) (\S+)$/) {
		return ('CHGIDENT', 0, 1, WF_ALL, $1, $2, $3);
		#setter, target, IDENT
	}
	elsif($_[0] =~ /^:(\S+) (?:SETIDENT|AD) (\S+)$/) {
		return ('CHGIDENT', 0, 1, WF_ALL, $1, $1, $2);
		#setter, target, ident
	}
}


sub TOPIC($) {
	if($_[0] =~ /^(@|:)(\S+) (?:TOPIC|\)) (\S+) (\S+) (\S+) :(.*)$/) {
	#:tabris TOPIC #the_lounge tabris 1089336598 :Small Channel in search of Strong Founder for long term relationship, growth, and great conversation.
		my $name;
		my ($name, $cn, $setter, $ts, $topic) = ($2, $3, $4, $5, $6);
		if ($1 eq '@') {
			$name = $servernum[b64toi($2)];
		}
		else {
			$name = $2;
		}
		if ($ts =~ s/^!//) {
			$ts = b64toi($ts);
		}
		my $usetter = {NICK=>$name};
		return ('TOPIC', 0, 1, WF_ALL, $usetter, $cn, $setter, $ts, $topic);
	}
	elsif($_[0] =~ /^(?:TOPIC|\)) (\S+) (\S+) (\S+) :(.*)$/) {
		my ($cn, $setter, $ts, $topic) = ($1, $2, $3, $4);
		if ($ts =~ s/^!//) {
			$ts = b64toi($ts);
		}
		# src, channel, setter, timestamp, topic
		my $usetter = {NICK=>$setter};
		return ('TOPIC', 0, 1, WF_ALL, undef, $cn, $usetter, $ts, $topic);
	}
}

sub UMODE($) {
#:tabris | +oghaANWt
	$_[0] =~ /^:(\S+) (?:UMODE2|\|) (\S+)$/;
	# src, umodes
	# a note, not all umodes are passed
	# +s, +O, and +t are not passed. possibly others
	# also not all umodes do we care about.
	# umodes we need care about:
	# oper modes: hoaACN,O oper-only modes: HSq
	# regular modes: rxB,izV (V is only somewhat, as the ircd
	# does the conversions from NOTICE to PRIVSMG for us).

	# Yes, I'm changing the event type on this
	# It's better called UMODE, and easily emulated
	# on IRCds with only MODE.
	my $user = {NICK => $1};
	get_user_id ($user);
	return ('UMODE', 0, 0, WF_ALL, $user, $2);
}
sub SVSMODE($) {
#:tabris | +oghaANWt
	$_[0] =~ /^:(\S+) (?:SVS2?MODE|n|v) (\S+) (\S+)$/;
	# src, umodes
	# a note, not all umodes are passed
	# +s, +O, and +t are not passed. possibly others
	# also not all umodes do we care about.
	# umodes we need care about:
	# oper modes: hoaACN,O oper-only modes: HSq
	# regular modes: rxB,izV (V is only somewhat, as the ircd
	# does the conversions from NOTICE to PRIVSMG for us).

	return ('UMODE', 0, 0, WF_ALL, $2, $3);
}

sub WHOIS($) {
# :tab WHOIS ConnectServ :ConnectServ
	if($_[0] =~ /^:(\S+) (?:WHOIS|\#) (\S+)$/) {
		return ('WHOIS', 0, undef, WF_NONE, $1, $2);
	}
	elsif($_[0] =~ /^:(\S+) (?:WHOIS|\#) (\S+) :(\S+)$/) {
		return ('WHOIS', 0, undef, WF_NONE, $1, $3);
	}
}

sub TSCTL($) {
	$_[0] =~ /^:(\S+) (?:TSCTL|AW) alltime$/;
	ircsend(":$main_conf{local} NOTICE $1 *** Server=$main_conf{local} TSTime=".
		time." time()=".time." TSOffset=0");
	return;
}

sub VERSION($) {
	$_[0] =~ /^:(\S+) (?:VERSION|\+).*$/;
	return ('VERSION', 0, undef, WF_NONE, $1);
}

sub TKL($) {
	if ($_[0] =~ /^(@|:)(\S+) (?:TKL|BD) (.*)$/) {
	# We discard the source anyway.
	#my $server;
	#if ($1 eq '@') {
	#	$server = $servernum[b64toi($2)];
	#}
	#else {
	#	$server = $2;
	#}
		return ('TKL', undef, undef, WF_NONE, parse_tkl("TKL $3"));
	}
	elsif ($_[0] =~ /^(?:TKL|BD) (.*)$/) {
		return ('TKL', undef, undef, WF_NONE, parse_tkl("TKL $1"));
	}
}

sub SNOTICE($) {
	$_[0] =~ /^(@|:)(\S+) (SENDSNO|Ss|SMO|AU) ([A-Za-z]) :(.*)$/;
	#@servernumeric Ss snomask :message
	my $name;
	if ($1 eq '@') {
		$name = $servernum[b64toi($2)];
	}
	else {
		$name = $2;
	}
	my $event;
	$event = 'SENDSNO' if(($3 eq 'SENDSNO' or $3 eq 'Ss'));
	$event = 'SMO' if(($3 eq 'SMO' or $3 eq 'AU'));
	return ($event, 0, undef, WF_NONE, $name, $4, $5);
}

sub GLOBOPS($) {
	$_[0] =~ /^(@|:)(\S+) (?:GLOBOPS|\]) :(.*)$/;
	#@servernumeric [ :message
	my $name;
	if ($1 eq '@') {
		$name = $servernum[b64toi($2)];
	}
	else {
		$name = $2;
	}
	return ('GLOBOPS', 0, undef, WF_NONE, $name, $3);
}

sub ISUPPORT($) {
	$_[0] =~ /^:(\S+) (?:105|005) (\S+) (.+) :are supported by this server$/;
	# :test-tab.surrealchat.net 105 services.SC.net CMDS=KNOCK,MAP,DCCALLOW,USERIP :are supported by this server
	foreach my $token (split(/\s+/, $3)) {
		my ($key, $value) = split('=', $token);
		$IRCd_capabilities{$key} = ($value ? $value : 1);
	}
	# Insp compatibility... :(
	$IRCd_capabilities{"CHGHOST"} = 1;
	$IRCd_capabilities{"CHGIDENT"} = 1;
	$IRCd_capabilities{"CLOAKHOST"} = 1;
	$IRCd_capabilities{"CLOAK"} = 1;
	$IRCd_capabilities{"ADMIN"} = 'a';
	$IRCd_capabilities{"FOUNDER"} = 'q';
	$IRCd_capabilities{"SILENCE"} = 32; 
	$IRCd_capabilities{"WATCH"} = 32;
	$IRCd_capabilities{"REG"} = 1;
	$IRCd_capabilities{"HALFOP"} = 'h';
	$IRCd_capabilities{"INSP"} = 0;
	# so ugly. Ugly Ugly UGLY.
}

sub STATS($) {
	$_[0] =~ /^:(\S+) (?:STATS|2) (\S) :(.+)$/;
	return ('STATS', undef, undef, WF_NONE, $1, $2, $3)
}

BEGIN {
	%cmdhash = (
		PING		=>	\&PING,
		'8'		=>	\&PING,

		EOS		=>	\&EOS,
		ES		=>	\&EOS,
		SERVER		=>	\&SERVER,
		"\'"		=>	\&SERVER,

		SQUIT		=>	\&SQUIT,
		'-'		=>	\&SQUIT,

		NETINFO		=>	\&NETINFO,
		AO		=>	\&NETINFO,

		PROTOCTL	=>	\&PROTOCTL,

		JOIN		=>	\&JOIN,
		C		=>	\&JOIN,

		PART		=>	\&PART,
		D		=>	\&PART,

		SJOIN		=>	\&SJOIN,
		'~'		=>	\&SJOIN,
		FJOIN   =>   \&FJOIN,
		FMODE   =>    \&FMODE,
		MODE		=>	\&MODE,
		G		=>	\&MODE,

		PRIVMSG		=>	\&MESSAGE,
		'!'		=>	\&MESSAGE,
		NOTICE		=>	\&MESSAGE,
		B		=>	\&MESSAGE,

		AWAY		=>	\&AWAY,
		'6'		=>	\&AWAY,

		NICK		=>	\&NICK,
		'&'		=>	\&NICK,

		QUIT		=>	\&QUIT,
		','		=>	\&QUIT,

		KILL		=>	\&KILL,
		'.'		=>	\&KILL,

		KICK		=>	\&KICK,
		H		=>	\&KICK,

		CHGHOST		=>	\&HOST,
		AL		=>	\&HOST,
		SETHOST		=>	\&HOST,
		AA		=>	\&HOST,
		'302'		=>	\&HOST,

		'340'		=>	\&USERIP,

		CHGIDENT	=>	\&IDENT,
		AZ		=>	\&IDENT,
		SETIDENT	=>	\&IDENT,
		AD		=>	\&IDENT,

		TOPIC		=>	\&TOPIC,
		')'		=>	\&TOPIC,

		UMODE2		=>	\&UMODE,
		'|'		=>	\&UMODE,

		TSCTL		=>	\&TSCTL,
		AW		=>	\&TSCTL,

		VERSION		=>	\&VERSION,
		'+'		=>	\&VERSION,

		TKL		=>	\&TKL,
		BD		=>	\&TKL,

		WHOIS		=>	\&WHOIS,
		'#'		=>	\&WHOIS,

		SENDSNO		=>	\&SNOTICE,
		Ss		=>	\&SNOTICE,

		SMO		=>	\&SNOTICE,
		AU		=>	\&SNOTICE,

		GLOBOPS		=>	\&GLOBOPS,
		']'		=>	\&GLOBOPS,

		'105'		=>	\&ISUPPORT,
		'005'		=>	\&ISUPPORT,

		SVSMODE		=>	\&SVSMODE,
		'n'		=>	\&SVSMODE,
		SVS2MODE	=>	\&SVSMODE,
		'v'		=>	\&SVSMODE,

		STATS		=>	\&STATS,
		'2'		=>	\&STATS,
	);
}

1;
