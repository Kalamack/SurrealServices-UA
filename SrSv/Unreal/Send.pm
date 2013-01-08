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
package ircd;

use constant { TS6_UID => 0 };

use strict;
use IO::Socket::INET;
use Event;
use Carp;
use MIME::Base64;
use Data::Dumper;
use SrSv::Conf 'main';
use SrSv::Conf::main;
use SrSv::Conf2Consts qw( main );
use SrSv::Debug;
use SrSv::Log;
use Exporter 'import';
our @EXPORT = qw (agent_doconn getUuid getRevUuid setUuid setRevUuid);
# FIXME
use constant {
	MAXBUFLEN => 510,

# These appear to match the implementations I've seen, but are unspecified in the RFCs.
# They may vary by implementation.
	NICKLEN => 30, # some ircds are different. hyperion is 16.
	IDENTLEN => 10, # Sometimes 8 or 9.
			# hyperion may break this due to it's ident format: [ni]=identhere, like this n=northman
	HOSTLEN => 63, # I think I've seen 64 here before.
	MASKLEN => 30 + 10 + 63 + 2, # 105, or maybe 106. the 2 constant is for !@

	CHANNELLEN => 32, # From 005 reply. hyperion is 30.
	
	SJ3 => 1,
	NOQUIT => 1,
	NICKIP => 1,
	SJB64 => 1,
	CLK => 1,

	PREFIXAQ_DISABLE => 0,
};
die "NICKIP must be enabled if CLK is\n" if CLK && !NICKIP;

use SrSv::IRCd::IO qw(ircd_connect ircsend ircsendimm ircd_flush_queue);
use SrSv::IRCd::Event qw(addhandler callfuncs);
use SrSv::IRCd::State qw($ircline $remoteserv $ircd_ready synced initial_synced set_server_state set_server_juped get_server_state get_online_servers);

use SrSv::Unreal::Modes qw(@opmodes %opmodes $scm $ocm $acm);
use SrSv::Unreal::Tokens qw( :tokens );
use SrSv::IRCd::Parse qw(parse_tkl parse_addline);
use SrSv::Unreal::Base64 qw(itob64 b64toi);

use SrSv::Text::Format qw( wordwrap );

use SrSv::Agent;

use SrSv::Process::InParent qw(update_userkill);

our %defer_mode;
our %preconnect_defer_mode;
our @userkill;
our $unreal_protocol_version;
our $count = 65;
our %uuids; #NickServ -> AAAAAA
our %reverse_uuids; #AAAAAA -> NickServ
addhandler('SEOS', undef(), undef(), 'ircd::eos', 1);
addhandler('NETINFO', undef(), undef(), 'ircd::netinfo', 1);
addhandler('VERSION', undef(), undef(), 'ircd::version', 1);
addhandler('SERVER', undef(), undef(), 'ircd::handle_server', 1);
sub getAgentRevUuid($) {
        return undef;
}
sub getAgentUuid($) {
        return undef;
}
sub setAgentRevUuid ($$) {
}
sub setAgentUuid ($$) {

}
sub serv_connect() {
	my $remote = main_conf_remote;
	my $port = main_conf_port;

	ircd_connect($remote, $port);
	
	ircsendimm('PROTOCTL '.(main_conf_tokens ? 'TOKEN ' : '').'NICKv2 UMODE2 TKLEXT'.
		(CLK ? ' CLK' : ' VHP'). # CLK obsoletes VHP. Plus if you leave VHP on, CLK doesn't work.
		(NOQUIT ? ' NOQUIT' : '').(SJ3 ? ' SJOIN SJOIN2 SJ3' : '').
		(NICKIP ? ' NICKIP' : '').
		(SJB64 ? ' SJB64 NS VL' : ''),
		'PASS :'.main_conf_pass,
		'SERVER '.main_conf_local.' 1 '.main_conf_numeric.(SJB64 ? ( ':U*-*-'.main_conf_numeric.' ') : ' :').main_conf_info);
	
	%preconnect_defer_mode = %defer_mode;
	%defer_mode = ();
}


# Helper Functions

sub handle_server($$$$;$$$) {
# This is mostly a stub function, but we may need the $unreal_protocol_version
# at a later date. Plus we may want to maintain a server tree in another module.
	my ($src_server, $server_name, $num_hops, $info_line, $server_numeric, $protocol_version, $build_flags) = @_;
	$unreal_protocol_version = $protocol_version if defined $protocol_version;
}



# Handler functions
sub pong($$$) {
    my ($src, $cookie, $dst) = @_;
	# This will only make sense if you remember that
	# $src is where it came from, $dst is where it went (us)
	# we're basically bouncing it back, but changing from PING to PONG.
	if (defined($dst) and defined($cookie)) {
		# $dst is always $main_conf{local} anyway...
		# this is only valid b/c we never have messages routed THROUGH us
		# we are always an end point.
		ircsendimm(":$dst PONG $src :$cookie");
	}
	else {
		ircsendimm("PONG :$src");
        }
}
sub eos {
	print "GOT EOS\n\n";

	#foreach my $k (keys %servers) {
	#	print "Server: $k ircline: ",$servers{$k}[0], " state: ", $servers{$k}[1], "\n";
	#}
	#print "Synced: ", synced(), "\n\n";
	#exit;
	
	ircsendimm(':'.$main_conf{local}.' EOS');
	ircsendimm(':'.$main_conf{local}.' VERSION');
	agent_sync();
	flushmodes(\%preconnect_defer_mode);
	ircd_flush_queue();

	$ircd_ready = 1;
}

sub netinfo($$$$$$$$) {
	ircsendimm('NETINFO 0 '.time." $_[2] $_[3] 0 0 0 :$_[7]");
	$main_conf{network} = $_[7];
}

sub tssync {
	ircsendimm((SJB64 ? '@'.itob64($main_conf{numeric}) : ':'.$main_conf{local})." TSCTL SVSTIME ".time);
}

=cut
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
			my $op;
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
=cut

# Send Functions

sub kick($$$$) {
	my ($src, $chan, $target, $reason) = @_;
	$src = $main_conf{local} unless initial_synced();
	my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
	ircsend(":$srcN @{[TOK_KICK]} $chan $targetN :$reason");
	callfuncs('KICK', 0, 2, [$srcN, $chan, $targetN, $reason]);
}

sub invite($$$) {
	my ($src, $chan, $target) = @_;
	my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
	ircsend(":$srcN @{[TOK_INVITE]} $targetN $chan 0");
}

sub ping {
#	if(@_ == 1) {
		ircsend(':'.$main_conf{local}.' PING :'.$main_conf{local});
#	} else {
#		ircsend(':'.$_[2].' '.$tkn{PONG}[$tkn].' '.$_[0].' :'.$_[1]);
#	}
}

sub privmsg($$@) {
	my ($src, $dst, @msgs) = @_;
	my @bufs;
	foreach my $buf (@msgs) {
		# 3 spaces, two colons, PRIVMSG=7
		# Length restrictions are for CLIENT Protocol
		# hence the (MASKLEN - (NICKLEN + 1))
		# Technically optimizable if we use $agent{lc $src}'s ident and host
		my $buflen = length($src) + length($dst) + 12 + (MASKLEN - (NICKLEN + 1));
		push @bufs, wordwrap($buf, (MAXBUFLEN - $buflen));
	}
	my $srcN = $src->{NICK};
	# submit a list of messages as a single packet to the server
	ircsend(":$srcN @{[TOK_PRIVMSG]} $dst :".join("\r\n".":$src @{[TOK_PRIVMSG]} $dst :", @bufs));
	callfuncs('LOOP_PRIVMSG', 0, 1, [$src, $dst, \@bufs]);
}

sub debug(@) {
	my (@msgs) = @_;
	debug_privmsg($main_conf{local}, $main_conf{diag}, @msgs);
	write_log('diag', '<'.$main_conf{local}.'>', @msgs);
}
#FIXME: This is part of SrSv::Log... what is it doing here?
#sub write_log () { }
sub debug_nolog(@) {
	my (@msgs) = @_;
	debug_privmsg($main_conf{local}, $main_conf{diag}, @msgs);
}

sub debug_privmsg($$@) {
	my ($src, $dst, @msgs) = @_;

	my @bufs;
	foreach my $buf (@msgs) {
		# 3 spaces, two colons, PRIVMSG=7
		# Length restrictions are for CLIENT Protocol
		# hence the (MASKLEN - (NICKLEN + 1))
		my $buflen = length($src) + length($dst) + 12 + (MASKLEN - (NICKLEN + 1));
		push @bufs, wordwrap($buf, (MAXBUFLEN - $buflen));
	}

	# submit a list of messages as a single packet to the server
	ircsendimm(":$src @{[TOK_PRIVMSG]} $dst :".join("\r\n".":$src @{[TOK_PRIVMSG]} $dst :", @bufs));
	callfuncs('LOOP_PRIVMSG', 0, 1, [$src, $dst, \@bufs]);
}

sub notice($$@) {
	my ($src, $dst, @msgs) = @_;
	my $target = $dst; #lazy erry
	my @bufs;
	foreach my $buf (@msgs) {
		# 3 spaces, two colons, NOTICE=6
		# Length restrictions are for CLIENT Protocol
		# hence the (MASKLEN - (NICKLEN + 1))
		my $buflen = length($src) + length($dst) + 12 + (MASKLEN - (NICKLEN + 1));
		push @bufs, wordwrap($buf, (MAXBUFLEN - $buflen));
	}
	my $srcN = $src->{NICK};
	my $targetN;
	if (ref ($dst) eq "HASH") { #User Object
		$targetN = $target->{NICK};
	}
	elsif(!ref($dst) && $dst =~ /^#/) { # /notice #channel This probably sucks. Blame erry :(
		$targetN = $dst;
	}
	ircsend(":$srcN @{[TOK_NOTICE]} $targetN :".join("\r\n".":$srcN @{[TOK_NOTICE]} $targetN :", @bufs));
	callfuncs('LOOP_NOTICE', 0, 1, [$srcN, $targetN, \@bufs]);
}

sub ctcp($$@) {
	my ($src, $dst, $cmd, @toks) = @_;
	my $target = $dst; #lazy erry
	my $srcN = $src->{NICK};
	my $targetN = ($target->{NICK});
	privmsg($srcN, $targetN, "\x01".join(' ', ($cmd, @toks))."\x01");
}

sub ctcp_reply($$@) {
	my ($src, $dst, $cmd, @toks) = @_;
	my $target = $dst; #lazy erry
	my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
	notice($srcN, $targetN, "\x01".join(' ', ($cmd, @toks))."\x01");
}

sub setumode($$$) {
	my ($src, $dst, $modes) = @_;
	my $target = $dst; #lazy erry
	my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
	ircsend(":$srcN SVSMODE $targetN $modes");
	callfuncs('UMODE', 0, undef, [$dst, $modes]);
}

sub setsvsstamp($$$) {
	my ($src, $dst, $stamp) = @_;
	my $srcN = $src->{NICK};
	my $dstN = $dst->{NICK};
	ircsend(":$srcN @{[TOK_SVS2MODE]} $dstN +d $stamp");
	# This function basically set the svsstamp to
	# be the same as the userid. Not all ircd will
	# support this function.
	#and insp doesn't.
	# We obviously already know the userid, so don't
	# use a callback here.
	#callfuncs('UMODE', 0, undef, [$dst, $modes]);
}

sub setagent_umode($$) {
	my ($src, $modes) = @_;
	ircsend(":$src UMODE2 $modes");
}

sub setmode2($$@) {
	my ($src, $dst, @modelist) = @_;
	#debug(" --", "-- ircd::setmode2: ".$_[0], split(/\n/, Carp::longmess($@)), " --");
	foreach my $modetuple (@modelist) {
		my $target = $modetuple->[1];
		setmode($src, $dst, $modetuple->[0], $modetuple->[1]);
	}
}
sub ban_list($$$$@) {
# Convenience function for lots of bans or excepts.
	my ($src, $cn, $sign, $mode, @parms) = @_;
	my @masklist;
	foreach my $mask (@parms) {
		push @masklist, [( ($sign >= 1) ? '+' : '-').$mode, $mask];
	}
	ircd::setmode2($src, $cn, @masklist);
}

sub setmode($$$;$) {
	my ($src, $dst, $modes, $target) = @_;
	my $srcN;
	if (initial_synced()) {
		if (ref($src) eq "HASH") {
			$srcN = $src->{NICK};
		}
		else {
			$srcN = $src;
		}
	}
	else {
		$src = $main_conf{local};
		$srcN = $src;
	}
	my $targetN;
	if (ref ($target) eq "HASH") {
		$targetN = $target->{NICK};
	}
	else {
		$targetN = $target;
	}
	callfuncs('MODE', undef, 1, [$srcN, $dst, $modes, $targetN]);
	#print "$ircline -- setmode($srcId, $dst, $modes, $targetId)\n" ;
	ircsend(":$srcN MODE $dst $modes $targetN");
}

sub setmode_many($$$;@) {
	my ($src, $dst, $modes, @targets) = @_;
	my $srcN;
	if (initial_synced()) {
		$srcN = $src->{NICK};
	}
	else {
		$srcN = $main_conf{local};
		$srcN = $src;
	}
	my $parms = "";
	foreach my $target (@targets) { 
		my $targetN = $target->{NICK};
		$parms .= ($parms eq ""?"":" ") . $targetN;
		print "parms" . $parms . "\n";
	}
	callfuncs('MODE', undef, 1, [$srcN, $dst, $modes, $parms]);
	print "$ircline -- setmode($srcN, $dst, $modes, $parms)\n" ;
	ircsend(":$srcN MODE $dst $modes $parms");
}


sub flushmodes(;$) {
	my $dm = (shift or \%defer_mode);
	my @k = keys(%$dm); my @v = values(%$dm);
	for(my $i; $i<@k; $i++) {
		my ($src, $dst) = split(/ /, $k[$i]);
		my @m = @{$v[$i]};
		foreach my $m (@m) {
			my ($modes, $parms) = split(/ /, $m, 2);
			setmode_real($src, $dst, $modes, $parms);
		}
	}
	%$dm = ();
}

sub setmode_real($$$;$) {
	my ($src, $dst, $modes, $parms) = @_;
	print "$ircline -- setmode_real($src, $dst, $modes, $parms)\n";
	# for server sources, there must be a timestamp. but you can put 0 for unspecified.
	$parms =~ s/\s+$//; #trim any trailing whitespace, as it might break the simple parser in the ircd.
	
	ircsend(":$src MODE $dst $modes".($parms?" $parms":'').($src =~ /\./ ? ' 0' : ''));
}

sub settopic($$$$$) {
	my ($src, $chan, $setter, $time, $topic) = @_;
	my $srcN;
	$srcN = $main_conf{local} unless initial_synced();
	if ($srcN eq "") {
		$srcN = $src->{NICK};
	}
	ircsend(":$srcN TOPIC $chan :$topic");
	callfuncs('TOPIC', undef, undef, [$srcN, $chan, $setter, $time, $topic]);
}

sub wallops ($$) {
	my ($src, $message) = @_;
	ircsend(":$src WALLOPS :$message");
}

sub globops ($$) {
	my ($src, $message) = @_;
	my $srcN = $src->{NICK};
	ircsend(":$srcN GLOBOPS :$message");
}

sub kline ($$$$$) {
    my ($setter, $ident, $host, $expiry, $reason) = @_;
	$setter = "srsv.erry.omg" unless defined($setter); #FIXME
	$ident = '*' unless defined($ident);
	my $setN;
	if (ref ($setter) eq "HASH") {
		$setN = $setter->{NICK};
	}
	else { $setN = $setter; }
	#:nascent.surrealchat.net TKL + G * *.testing.only tabris!northman@netadmin.SCnet.ops 1089168439 1089168434 :This is just a test.
    my $line = "TKL + G $ident $host $setN ".($expiry + time()).' '.time()." :$reason";

	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}
sub unkline ($$$) {
	my ($setter, $ident, $host) = @_;
	# TKL - G ident host setter
# TKL - G ident *.test.dom tabris!northman@netadmin.SCnet.ops
	my $setN;
	if (ref ($setter) eq "HASH") {
		$setN = $setter->{NICK};
	}
	else { $setN = $setter; }
	my $line = "TKL - G $ident $host $setN";
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub zline ($$$$) {
    my ($setter, $host, $expiry, $reason) = @_;

	#foreach my $ex (@except) { return 1 if $mask =~ /\Q$ex\E/i; }
	
        # format is
        # TKL +/- type ident host setter expiretime settime :reason
    my $setN;
	if (ref ($setter) eq "HASH") {
		$setN = $setter->{NICK};
	}
	else { $setN = $setter; }
    my $line = "TKL + Z * $host $setN ".($expiry + time).' '.time." :$reason";
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub unzline ($$) {
	my ($setter, $host) = @_;
	# TKL - G ident host setter
# TKL - G ident *.test.dom tabris!northman@netadmin.SCnet.ops
	my $setN;
	if (ref ($setter) eq "HASH") {
		$setN = $setter->{NICK};
	}
	else { $setN = $setter; }
	my $line = "TKL - Z * $host $setN";
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub spamfilter($$$$$$$) {
# Note the hardcoded zero (0).
# Looks like theoretically one can have expirable spamfilters.
# This is untested however.
	my ($sign, $tkl_target, $tkl_action, $setter, $bantime, $reason, $regex) = @_;
	my $tkl = "TKL ".($sign ? '+' : '-' )." F $tkl_target $tkl_action $setter 0 ".time()." $bantime $reason :$regex";
	ircsend($tkl);
	callfuncs('TKL', undef, undef, [parse_tkl($tkl)]);
}

sub update_userkill($) {
	my ($target) = @_;

	# This is a simple way to do it, that _could_ be defeated
	# with enough users getting killed at once.
	# The alternative would require a timer to expire the old entries.
	return undef if (time() == $userkill[1] and $target eq $userkill[0]);
	@userkill = ($target, time());

	return 1;
}

sub irckill($$$) {
	my ($src, $target, $reason) = @_;
	$src = $main_conf{local} unless initial_synced();
	my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
	return 0 unless update_userkill($targetN);
	ircsendimm(":$srcN KILL $targetN ($reason)");
	callfuncs('KILL', 0, 1, [$src, $target, $srcN, $reason]);
}

sub svssno($$$) {
    my ($src, $target, $snomasks) = @_;
    $src=$main_conf{local} unless defined($src);
    # TODO:
    # None, this doesn't affect us.

    # SVSSNO is not in tokens.txt nor msg.h
    ircsend(":$src ".'SVS2SNO'." $target $snomasks ".time);
}

sub svsnick($$$) {
    my ($src, $target, $newnick) = @_;
    $src=$main_conf{local} unless defined($src);
    # note: we will get a NICK cmd back after a 
    # successful nick change.
    # warning, if misused, this can KILL the user
    # with a collision
  	my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
    ircsend(":$srcN SVSNICK $targetN $newnick ".time);
}

sub svsnoop($$$) {
    my ($targetserver, $bool, $src) = @_;
    $src = $main_conf{local} unless defined($src);
    if ($bool > 0) { $bool = '+'; } else { $bool = '-'; }
#this is SVS NO-OP not SVS SNOOP
    ircsend(":$main_conf{local} SVSNOOP $targetserver $bool");
}

#START TODO - erry

sub svswatch ($$@) { 
# Changes the WATCH list of a user.
# Syntax: SVSWATCH <nick> :<watch parameters>
# Example: SVSWATCH Blah :+Blih!*@* -Bluh!*@* +Bleh!*@*.com
# *** We do not track this info nor care.
	my ($src, $target, @watchlist) = @_;
    my $srcId = ($src->{NICK});
	my $targetId = $target->{NICK};
	my $base_str = ":$srcId SVSWATCH $targetId :";
	my $send_str = $base_str;
	while (@watchlist) {
		my $watch = shift @watchlist;
		if (length("$send_str $watch") > MAXBUFLEN) {
			ircsend($send_str);
			$send_str = $base_str;
		}
		$send_str = "$send_str $watch";
	}
	ircsend($send_str);
}

sub svssilence ($$@) {
# Changes the SILENCE list of a user.
# Syntax: SVSSILENCE <nick> :<silence parameters>
# Example: SVSSILENCE Blah :+Blih!*@* -Bluh!*@* +Bleh!*@*.com
# *** We do not track this info nor care.
	my ($src, $target, @silencelist) = @_;
    my $srcId = ($src->{NICK});
	my $targetId = ($target->{NICK});
	my $base_str = ":$srcId SVSSILENCE $targetId :";
	my $send_str = $base_str;
	while (@silencelist) {
		my $silence = shift @silencelist;
		if (length("$send_str $silence") > MAXBUFLEN) {
			ircsend($send_str);
			$send_str = $base_str;
		}
		$send_str = "$send_str $silence";
	}
	print "SENDING $send_str\n";
	ircsend($send_str);
}

sub svso($$$) {
# Gives nick Operflags like the ones in O:lines.
# SVSO <nick> <+operflags> (Adds the Operflags)
# SVSO <nick> - (Removes all O:Line flags)
# Example: SVSO SomeNick +bBkK
# *** We do not track this info nor care.
# *** We will see any umode changes later.
# *** this cmd does not change any umodes!
    my ($src, $target, $oflags) = @_;
    $src = $main_conf{local} unless defined($src);
    ircsend(":$src SVSO $target $oflags");
}

sub swhois($$$) {
# *** We do not track this info nor care.
    my ($src, $target, $swhois) = @_;
    $src = $main_conf{local} unless defined($src);
    ircsend(":$src SWHOIS $target :$swhois");
}
#END TODO - erry

sub svsjoin($$@) {
	my ($src, $target, @chans) = @_;
	while(my @chanList = splice(@chans, 0, 10)) {
	# split into no more than 10 at a time.
		__svsjoin($src, $target, @chanList);
	}
}

sub __svsjoin($$@) {
    my ($src, $target, @chans) = @_;
    # a note. a JOIN is returned back to us on success
    # so no need to process this command.
    # similar for svspart.
	my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
    ircsend(($srcN?":$srcN":'')." SVSJOIN $targetN ".join(',', @chans));
}

sub svspart($$$@) {
    my ($src, $target, $reason, @chans) = @_;
   	my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
    ircsend(($srcN ? ":$srcN" : '')." SVSPART $targetN ".join(',', @chans).
    	($reason ? " :$reason" : ''));
}

sub sqline ($;$) {
	# we need to sqline most/all of our agents.
	# tho whether we want to put it in agent_connect
	# or leave it to the module to call it...
	my ($nickmask, $reason) = @_;
	#ircsend("$tkn{SQLINE}[$tkn] $nickmask".($reason?" :$reason":''));
	qline($nickmask, 0, $reason);
}

sub svshold($$$) {
	# Not all IRCd will support this command, as such the calling module must check the IRCd capabilities first.
	my ($nickmask, $expiry, $reason) = @_;
	# TKL version - Allows timed qlines.
	# TKL + Q * test services.SC.net 0 1092179497 :test
	my $line = 'TKL + Q H '.$nickmask.' '.main_conf_local.' '.($expiry ? $expiry+time() : 0).' '.time().' :'.$reason;
	ircsend($line);
	# at startup we send these too early,
	# before the handlers are initialized
	# so they may be lost.
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub svsunhold($) {
	my ($nickmask) = @_;
	# TKL version
	# TKL - Q * test services.SC.net
	my $line = 'TKL - Q H '.$nickmask.' '.main_conf_local;
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub qline($$$) {
	my ($nickmask, $expiry, $reason) = @_;
# TKL version - Allows timed qlines.
# TKL + Q * test services.SC.net 0 1092179497 :test
	my $line = 'TKL + Q * '.$nickmask.' '.main_conf_local.' '.($expiry ? $expiry+time() : 0).' '.time().' :'.$reason;
	ircsend($line);

	# at startup we send these too early,
	# before the handlers are initialized
	# so they may be lost.
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub unsqline ($) {
# we need to sqline most/all of our agents.
# tho whether we want to put it in agent_connect
# or leave it to the module to call it...
	my ($nickmask) = @_;
	unqline($nickmask);
}

sub unqline($) {
	my ($nickmask) = @_;
# TKL version
# TKL - Q * test services.SC.net
	my $line = 'TKL - Q * '.$nickmask.' '.main_conf_local;
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub svskill($$$) {
	my ($srcUser, $targetUser, $reason) = @_;
	# SVSKILL requires a src, it will NOT work w/o one.
	# not sure if it'll accept a servername or not.
	# consider defaulting to ServServ
	my $srcN = $srcUser -> {NICK};
	my $targetN = $targetUser -> {NICK};
	die('svskill called w/o $srcUser') unless $srcUser;
	ircsend(':'.$srcN.' SVSKILL '.$targetN.' :'.$reason);
	callfuncs('QUIT', 0, undef, [$targetUser, $reason]);
}

sub version($) {
	my ($src) = @_;
	#ircsend(":$main_conf{local} 351 $src $main::progname ver $main::version $main_conf{local} ".
	#	$main::extraversion);
}

sub userhost($) {
	my ($target) = @_;
	ircsend("USERHOST $target");
}

sub userip($) {
	my ($target) = @_;
	die "We're not supposed to use USERIP anymore!" if DEBUG and NICKIP;
	ircsend(":$main::rsnick USERIP $target");
}

sub chghost($$$) {
	my ($src, $target, $vhost) = @_;
    my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
	ircsend(($srcN?":$srcN ":'')." CHGHOST $targetN $vhost");
        callfuncs('CHGHOST', 0, 1, [$srcN, $targetN, $vhost]);
}

sub chgident($$$) {
	my ($src, $target, $ident) = @_;
    my $srcN = $src->{NICK};
	my $targetN = $target->{NICK};
	ircsend(($src?":$srcN ":'')." CHGIDENT $targetN $ident");
        callfuncs('CHGIDENT', 0, 1, [$srcN, $targetN, $ident]);
}

sub jupe_server($$) {
	my ($server, $reason) = @_;

	# :nascent.surrealchat.net SERVER wyvern.surrealchat.net 2 :SurrealChat
	die "You can't jupe $server"
		if ((lc($server) eq lc($remoteserv)) or (lc($server) eq lc($main_conf{local})));
	ircsend(':'.$main_conf{local}." SQUIT $server :");
	ircsend(':'.$main_conf{local}." SERVER $server 2 :$reason");

	set_server_juped($server);
}
sub agent_dojoin($$) {
	my ($agent, $chan) = @_;
	my $srcN;
	if (ref($agent) ne "HASH") {
		$srcN = $agent;
	}
	else {
		my $src = $agent;
		$srcN = $src->{NICK};
	}
	ircsend(":" . $srcN .  " JOIN " . $chan);
}

sub agent_dopart ($$$) {
	my ($agent, $chan, $reason) = @_;
	my $srcN;
	if (ref($agent) ne "HASH") {
		$srcN = $agent;
	}
	else {
		my $src = $agent;
		$srcN = $src->{NICK};
	}
	ircsend(":$srcN PART $chan :$reason");
}
sub rehash_all_servers(;$) {
	my ($type) = @_;

	# Validate the type before passing it along.
	# Very IRCd specific! May be version specific.
	$type = undef() if(defined($type) && !($type =~ /^\-(motd|botmotd|opermotd|garbage)$/i));

	foreach my $server (get_online_servers()) {
		ircsend(':'.$main::rsnick.' REHASH '.$server.(defined($type) ? ' '.$type : '') );
	}
}

sub unban_nick($$@) {
# This is an Unreal-specific server-protocol HACK.
# It is not expected to be portable to other ircds.
# Similar concepts may exist in other ircd implementations
	my ($src, $cn, @nicks) = @_;
	my $srcN = $src->{NICK};
	my $i = 0; my @nicklist = ();
	while(my $nick = shift @nicks) {
		push @nicklist, $nick;
		if(++$i >= 10) {
			ircsend(($src ? ":$src" : '' )." SVSMODE $cn -".'b'x($i).' '.join(' ', @nicklist));
			$i = 0; @nicklist = ();
		}
	}
	ircsend(($srcN ? ":$srcN " : "SVSMODE $cn -".'b'x($i).' '.join(' ', @nicklist)));
	# We don't loopback this, as we'll receive back the list
	# of removed bans.
}

sub clear_bans($$) {
# This is an Unreal-specific server-protocol HACK.
# It is not expected to be portable to other ircds.
# Similar concepts may exist in other ircd implementations
	my ($src, $cn) = @_;
	
	ircsend(($src ? ":$src " : '' ). "SVSMODE $cn -b");
	# We don't loopback this, as we'll receive back the list
	# of removed bans.
}

# HostServ OFF would want this.
# resets the vhost to be the cloakhost.
sub reset_cloakhost($$) {
	my ($src, $target) = @_;
	setumode($src, $target, '-x+x'); # only works in 3.2.6.
}

# removes the cloakhost, so that vhost matches realhost
sub disable_cloakhost($$) {
	my ($src, $target) = @_;
	setumode($src, $target, '-x'); # only works in 3.2.6.
}

# enables the cloakhost, so that vhost becomes the cloakhost
sub enable_cloakhost($$) {
	my ($src, $target) = @_;
	setumode($src, $target, '+x'); # only works in 3.2.6.
}

sub agent_doconn ($$$$$) {
	my ($nick, $ident, $host, $modes, $gecos) = @_;
	ircsend("NICK $nick 1 " . time . " $ident $host ".
		(SJB64 ? itob64(main_conf_numeric) : main_conf_local).
		" 1 $modes * :$gecos");
}

sub nolag($$@) {
	my ($src, $sign, @targets) = @_;
	$src = $main_conf{local} unless $src;
	foreach my $target (@targets) {
		ircsend(':'.$src .' SVSNOLAG '.$sign.' '.$target);
	}
}

1;
