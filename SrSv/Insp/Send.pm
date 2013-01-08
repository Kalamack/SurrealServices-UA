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

use strict;
use constant { TS6_UID => 1 };

use IO::Socket::INET;
use Event;
use Carp;
use MIME::Base64;
use Data::Dumper;
use SrSv::Conf 'main';
use SrSv::Insp::UUID;
use SrSv::Debug;
use SrSv::Log;
use Exporter 'import';
our @EXPORT = qw (agent_doconn getAgentRevUuid getAgentUuid setAgentRevUuid setAgentUuid);
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
use SrSv::Unreal::Tokens;
use SrSv::IRCd::Parse qw(parse_tkl parse_addline);
use SrSv::Unreal::Base64 qw(itob64 b64toi);

use SrSv::Text::Format qw( wordwrap );
use SrSv::User '/./';
use SrSv::Agent;

use SrSv::Process::InParent qw(update_userkill getAgentRevUuid getAgentUuid setAgentRevUuid setAgentUuid);

our %defer_mode;
our %preconnect_defer_mode;
our @userkill;
our $unreal_protocol_version;
our %uuids; #NickServ -> AAAAAA
our %reverse_uuids; #AAAAA -> NickServ
addhandler('SEOS', undef(), undef(), 'ircd::eos', 1);
addhandler('NETINFO', undef(), undef(), 'ircd::netinfo', 1);
addhandler('VERSION', undef(), undef(), 'ircd::version', 1);
addhandler('SERVER', undef(), undef(), 'ircd::handle_server', 1);
addhandler('ENDBURST',undef(),undef(),'ircd::endburst',1);
sub encodeUUID_ ($) {
	my ($user) = @_;
	if (ref ($user) ne "HASH") {
		Carp::confess ("encodeUUID_ called on non-hash " . $user);
		return;
	}
	if (defined ($user->{e_ID})) {
		return $user->{e_ID};
	}
	if (!defined($user->{ID})) {
		Carp::confess ("encodeUUID_ called on a user w/o id " , Dumper ($user));
		return;
	}
	my $nick = $user->{NICK};
	if (!defined ($nick)) {
		$nick = get_user_nick ($user);
	}
	if (is_agent ($nick)) {
		return $user->{e_ID} = $user->{ID};
	}
	return $user->{e_ID} = encodeUUID ($user->{ID});
}
sub getAgentRevUuid($) {
	my $id = $_[0];
	my $nick = $reverse_uuids{$id};
	$uuids{lc $nick} = $id;
	return $nick;
}
sub getAgentUuid($) {
	my $nick = lc $_[0];
	my $id = $uuids{$nick};
	return $id;
}
sub setAgentRevUuid ($$) {
	my ($id, $nick) = @_;
	$reverse_uuids{$id} = lc $nick;
}
sub setAgentUuid ($$) {
	my ($nick, $id) = @_;
	$uuids{lc $nick} = $id;
}
sub serv_connect() {
	my $remote = $main_conf{remote};
	my $port = $main_conf{port};
	ircd_connect($remote, $port);
	ircsendimm(	'PASS :'.$main_conf{pass},
		'SERVER '.$main_conf{local}.' ' . $main_conf{pass} . ' 0 ' .$main_conf{numeric} . ' ' .$main_conf{info} );
	ircsendimm ('BURST ' .time);
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
sub endburst {
        agent_sync();
        flushmodes(\%preconnect_defer_mode);
        ircd_flush_queue();
        $ircd_ready = 1;
	ircd_flush_queue();
	ircsendimm ("ENDBURST");
	$ircd_ready = 1; #!
	
}
sub eos {

	#foreach my $k (keys %servers) {
	#	print "Server: $k ircline: ",$servers{$k}[0], " state: ", $servers{$k}[1], "\n";
	#}
	#print "Synced: ", synced(), "\n\n";
	#exit;
	
	ircsendimm(':'.$main_conf{local}.' EOS VERSION');

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

# Send Functions

sub kick($$$$) {
	my ($src, $chan, $target, $reason) = @_;
	$src = $main_conf{numeric} unless initial_synced();
	my $srcId;
	if (ref($src) eq "HASH") {
		$srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	}
	else {
		$srcId = $src;
	}
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	ircsend(":$srcId KICK $chan $targetId :$reason");
	callfuncs('KICK', 0, 2, [$srcId, $chan, $targetId, $reason]);
}

sub invite($$$) {
	my ($src, $chan, $target) = @_;
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	ircsend(":$srcId INVITE $targetId $chan 0");
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
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	
	# submit a list of messages as a single packet to the server
	ircsend(":$srcId PRIVMSG $dst :".join("\r\n".":$src PRIVMSG $dst :", @bufs));
	callfuncs('LOOP_PRIVMSG', 0, 1, [$src, $dst, \@bufs]);
}

sub debug(@) {
	my (@msgs) = @_;
	debug_privmsg($main_conf{local}, $main_conf{diag}, @msgs);
	write_log('diag', '<'.$main_conf{local}.'>', @msgs);
}
sub write_log () { }
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
	ircsendimm(":$src PRIVMSG $dst :".join("\r\n".":$src PRIVMSG $dst :", @bufs));
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
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId;
	if (ref ($dst) eq "HASH") { #User Object
		$targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	}
	else { # /notice #channel This probably sucks. Blame erry :(
		$targetId = $dst;
	}
	ircsend(":$srcId NOTICE $targetId :".join("\r\n".":$srcId NOTICE $targetId :", @bufs));
	callfuncs('LOOP_NOTICE', 0, 1, [$srcId, $targetId, \@bufs]);
}

sub ctcp($$@) {
	my ($src, $dst, $cmd, @toks) = @_;
	my $target = $dst; #lazy erry
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	privmsg($srcId, $targetId, "\x01".join(' ', ($cmd, @toks))."\x01");
}

sub ctcp_reply($$@) {
	my ($src, $dst, $cmd, @toks) = @_;
	my $target = $dst; #lazy erry
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	notice($srcId, $targetId, "\x01".join(' ', ($cmd, @toks))."\x01");
}

sub setumode($$$) {
	my ($src, $dst, $modes) = @_;
	my $target = $dst; #lazy erry
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	ircsend(":$srcId SVSMODE $targetId $modes");
	callfuncs('UMODE', 0, undef, [$dst, $modes]);
}

sub setsvsstamp($$$) {
	my ($src, $dst, $stamp) = @_;
	
	ircsend(":$src SVS2MODE $dst +d $stamp");
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
	my $srcId;
	if (initial_synced()) {
		if (ref($src) eq "HASH") {
			if ($src->{NICK} && !$src->{ID}) {
				get_user_id ($src);
			}
			$srcId = ($src->{ID}?$src->{ID}:($src->{UUID}?$src->{UUID}:$src->{NICK}));
		}
		else {
			$srcId = $src;
		}
	}
	else {
		$src = $main_conf{numeric};
		$srcId = $src;
	}
	my $targetId;
	if (ref ($target) eq "HASH") {
		$targetId = ($target->{UID}?$target->{UID}:($target->{ID}?encodeUUID_($target):$target->{NICK}));
	}
	else {
		$targetId = $target;
	}
	callfuncs('MODE', undef, 1, [$srcId, $dst, $modes, $targetId, $target]);
	print "$ircline -- setmode($srcId, $dst, $modes, $targetId)\n" if DEBUG;
	ircsend(":$srcId MODE $dst $modes $targetId");
}

sub setmode_many($$$;@) {
	my ($src, $dst, $modes, @targets) = @_;
	my $srcId;
	if (initial_synced()) {
		$srcId = ($src->{ID}?$src->{ID}:($src->{UUID}?$src->{UUID}:$src->{NICK}));
	}
	else {
		$src = $main_conf{local};
		$srcId = $src;
	}
	my $parms = "";
	foreach my $target (@targets) { 
		my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
		$parms .= ($parms eq ""?"":" ") . $targetId;
	}
	callfuncs('MODE', undef, 1, [$srcId, $dst, $modes, $parms, @targets]);
	print "$ircline -- setmode($srcId, $dst, $modes, $parms)\n" if DEBUG;
	ircsend(":$srcId MODE $dst $modes $parms");
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
	print "$ircline -- setmode_real($src, $dst, $modes, $parms)\n" if DEBUG;
	# for server sources, there must be a timestamp. but you can put 0 for unspecified.
	$parms =~ s/\s+$//; #trim any trailing whitespace, as it might break the simple parser in the ircd.
	
	ircsend(":$src MODE $dst $modes".($parms?" $parms":'').($src =~ /\./ ? ' 0' : ''));
}

sub settopic($$$$$) {
	my ($src, $chan, $setter, $time, $topic) = @_;
	$src = $main_conf{numeric} unless initial_synced();
	#>> 38 :583AAAAAF TOPIC #erry :Welcome to erry(world|net). Have a cookie.
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	ircsend(":$srcId TOPIC $chan :$topic");
	callfuncs('TOPIC', undef, undef, [$srcId, $chan, $setter, $time, $topic]);
}

sub wallops ($$) {
	my ($src, $message) = @_;
	ircsend(":$src WALLOPS :$message");
}

sub globops ($$) {
	my ($src, $message) = @_;
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	ircsend(":$srcId GLOBOPS :$message");
}

sub kline ($$$$$) {
    my ($setter, $ident, $host, $expiry, $reason) = @_;
	$setter = $main_conf{local} unless defined($setter);
	$ident = '*' unless defined($ident);
	# you need to use ADDLINE for this. GLINE is a user command
    # format is
    #>> 47 :583AAAAAA ADDLINE G test@testie inspircd.erry.omg 1308118489 0 :hi
    #NOTE FOR ALL ADDLINES:
    #note that you need to provide expiry alone, not expiry +time
    #otherwise you will end up with insanely long bans
    my $setId;
    if (ref ($setter) eq "HASH") {
    	$setId = $setter->{ID};
    }
    else {
    	$setId = $setter;
    }
    my $line = ":$setId ADDLINE G $ident\@$host " . $main_conf{local} . " ". time() . " " . ($expiry)." :$reason";
	ircsend($line);
	#return ($type, +1, $ident, $host, $setter, $expire, $time, $reason);
	callfuncs('TKL', undef, undef, [parse_addline($line)]);
}

sub unkline ($$$) {
	my ($setter, $ident, $host) = @_;
	my $line = "TKL - G $ident $host $setter";
	my $setId = getAgentUuid($setter);
    if ($setId) { $setter = $setId; }
	#:583AAAAAE DELLINE G test@test.com
	my $line = ":$setter DELLINE G $ident\@$host";
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_delline($line)]);
}

sub zline ($$$$) {
	my ($setter, $host, $expiry, $reason) = @_;
	$setter=$main_conf{local} unless defined($setter);
	my $setId = getAgentUuid($setter);
	if ($setId) { $setter = $setId; }
   	 #:583AAAAAE ADDLINE Z test.com inspircd.erry.omg 1308216407 0 :go away
   	my $line = ":$setter ADDLINE Z $host " . $main_conf{local} . " ". time() . " " . ($expiry)." :$reason";
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_addline($line)]);
}

sub unzline ($$) {
	my ($setter, $host) = @_;
	my $setId = getAgentUuid($setter);
    if ($setId) { $setter = $setId; }
	my $line = ":$setter DELLINE Z $host";
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_delline($line)]);
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
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	my $srcNick = $target->{NICK};
	return 0 unless update_userkill($targetId);
	ircsendimm(":$srcId KILL $targetId :($reason)");
	callfuncs('KILL', 0, 1, [$src, $target, $srcNick, $reason]);
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
    my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
    ircsend(":$srcId SVSNICK $targetId $newnick ".time);
}

sub svsnoop($$$) {
    my ($targetserver, $bool, $src) = @_;
    $src = $main_conf{local} unless defined($src);
    if ($bool > 0) { $bool = '+'; } else { $bool = '-'; }
#this is SVS NO-OP not SVS SNOOP
    ircsend(":$main_conf{local} SVSNOOP $targetserver $bool");
}


sub svswatch ($$@) { 
	my ($src, $target, @watchlist) = @_;
 	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	my $base_str = ":$srcId SVSWATCH $targetId ";
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
    my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	my $base_str = ":$srcId SVSSILENCE $targetId ";
	my $send_str = $base_str;
	while (@silencelist) {
		my $silence = shift @silencelist;
		if (length("$send_str $silence") > MAXBUFLEN) {
			ircsend($send_str);
			$send_str = $base_str;
		}
		$send_str = "$send_str $silence";
	}
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

sub svsjoin($$@) {
	my ($src, $target, @chans) = @_;
	foreach my $chan (@chans) {
		# insp only allows one at the time. 
		__svsjoin($src, $target, $chan);
	}
}

sub __svsjoin($$@) {
    my ($src, $target, $chan) = @_;
    # a note. a JOIN is returned back to us on success
    # so no need to process this command.
    # similar for svspart.
    my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
    ircsend(($srcId?":$srcId":'')." SVSJOIN $targetId $chan");
}

sub svspart($$$@) {
    my ($src, $target, $reason, @chans) = @_;
    my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
    ircsend(($srcId ? ":$srcId" : '')." SVSPART $targetId ".join(',', @chans).
    	($reason ? " :$reason" : ''));
}

sub sqline ($;$) {
# we need to sqline most/all of our agents.
# tho whether we want to put it in agent_connect
# or leave it to the module to call it...
	my ($nickmask, $reason) = @_;
	#ircsend("$tkn{S1QLINE}[$tkn] $nickmask".($reason?" :$reason":''));
	qline($nickmask, 0, $reason);
}

sub svshold($$$) {
	my ($nickmask, $expiry, $reason) = @_;
	#:583AAAAAA ADDLINE Q hell3o inspircd.erry.omg 1308295479 600 :Bye Bye
	my $line = ':' . $main_conf{numeric} . ' ADDLINE Q '.$nickmask.' '.$main_conf{local}.' '. time() . ' ' . ($expiry ? $expiry : 0 ) . ' :'.$reason;
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_addline($line)]);
}

sub svsunhold($) {
	my ($nickmask) = @_;
	#>> 37 :583AAAAAA DELLINE Q errietta3
	my $line = ":" . $main_conf{numeric} . ' DELLINE Q ' . $nickmask . "\n";
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub qline($$$) {
	my ($nickmask, $expiry, $reason) = @_;
	#:583AAAAAA ADDLINE Q hell3o inspircd.erry.omg 1308295479 600 :Bye Bye
	my $line = ':' . $main_conf{numeric} . ' ADDLINE Q '.$nickmask . ' ' . $main_conf{local} . ' '. time() . ' ' . ($expiry ? $expiry : 0).' :'.$reason;
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
	#>> 37 :583AAAAAA DELLINE Q errietta3
	my $line = ':' . $main_conf{numeric} . ' DELLINE Q '.$nickmask;
	ircsend($line);
	callfuncs('TKL', undef, undef, [parse_tkl($line)]);
}

sub svskill($$$) {
	my ($src, $target, $reason) = @_;
	# SVSKILL requires a src, it will NOT work w/o one.
	# not sure if it'll accept a servername or not.
	# consider defaulting to ServServ
	die('svskill called w/o $src') unless $src;
	ircsend(':'.$src.' SVSKILL '.$target.' :'.$reason);
	callfuncs('QUIT', 0, undef, [$target, $reason]);
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
    my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	ircsend(($srcId?":$srcId ":'')." CHGHOST $targetId $vhost");
        callfuncs('CHGHOST', 0, 1, [$srcId, $targetId, $vhost]);
}

sub chgident($$$) {
	my ($src, $target, $ident) = @_;
    my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $targetId = ($target->{ID}?encodeUUID_($target):$target->{NICK});
	ircsend(($src?":$srcId ":'')." CHGIDENT $targetId $ident");
        callfuncs('CHGIDENT', 0, 1, [$srcId, $targetId, $ident]);
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
	my $srcId;
	if (ref($agent) ne "HASH") {
		$srcId = getAgentUuid($agent);
		if (!$srcId) {
			$srcId = $agent;
		}
	}
	else {
		my $src = $agent;
		$srcId = ($src->{ID}?$src->{ID}:($src->{UUID}?$src->{UUID}:$src->{NICK}));
	}
	ircsend(":" . $srcId .  " JOIN " . $chan);
}

sub agent_dopart ($$$) {
	my ($agent, $chan, $reason) = @_;
	my $srcId;
	if (ref($agent) ne "HASH") {
		$srcId = getAgentUuid($agent);
		if (!$srcId) {
			$srcId = $agent;
		}
	}
	else {
		my $src = $agent;
		$srcId = ($src->{ID}?$src->{ID}:($src->{UUID}?$src->{UUID}:$src->{NICK}));
	}
	ircsend(":$srcId PART $chan :$reason");
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
	my $srcId = ($src->{ID}?$src->{ID}:$src->{NICK});
	my $i = 0; my @nicklist = ();
	while(my $nick = shift @nicks) {
		push @nicklist, $nick;
		if(++$i >= 10) {
			ircsend(($src ? ":$src" : '' )." SVSMODE $cn -".'b'x($i).' '.join(' ', @nicklist));
			$i = 0; @nicklist = ();
		}
	}
	
	ircsend(($srcId ? ":$srcId " : "SVSMODE $cn -".'b'x($i).' '.join(' ', @nicklist)));
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
my $startInt = -1;
sub agent_doconn ($$$$$) {
	my ($nick, $ident, $host, $modes, $gecos) = @_;
	$modes = "+okiIB";
	my $uuid;
	if ($startInt == -1) {
		$uuid = $main_conf{numeric} . "AAAAAA";
		$startInt = decodeUUID ($uuid);
	}
	else {
		$uuid = encodeUUID($startInt);
	}
	ircsend(":" . $main_conf{numeric} . " UID" . " $uuid " . time . " $nick $host $host $ident 127.0.0.1 ". (time+5) . " $modes " . ":$gecos" );
	setAgentUuid($nick,$uuid);
	setAgentRevUuid($uuid, $nick);
	$startInt++;
}

sub nolag($$@) {
	my ($src, $sign, @targets) = @_;
	$src = $main_conf{local} unless $src;
	foreach my $target (@targets) {
		ircsend(':'.$src .' SVSNOLAG '.$sign.' '.$target);
	}
}

1;
