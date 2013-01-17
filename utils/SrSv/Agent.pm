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

package SrSv::Agent;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT = qw(
	is_agent is_agent_in_chan
	agent_connect agent_quit agent_quit_all
	agent_join agent_part set_agent_umode
	agent_sync is_invalid_agentname
); }

use SrSv::Process::InParent qw(
	is_agent is_agent_in_chan
	agent_connect agent_quit agent_quit_all
	agent_join agent_part agent_sync
	whois_callback kill_callback
);

use SrSv::Conf2Consts qw(main);

use SrSv::Debug;
use SrSv::Unreal::Tokens qw( :tokens );
use SrSv::Unreal::Base64 qw(itob64);
use SrSv::IRCd::State qw(synced $ircd_ready %IRCd_capabilities);
use SrSv::IRCd::IO qw(ircsend ircsendimm);
use SrSv::IRCd::Event qw(addhandler);
use SrSv::IRCd::Validate qw(valid_nick);
use SrSv::RunLevel 'main_shutdown';

# FIXME
BEGIN { *SJB64 = \&ircd::SJB64 }

our %agents;
our @defer_join;

addhandler('WHOIS', undef(), undef(), 'whois_callback', 1);
addhandler('KILL', undef(), undef(), 'kill_callback', 1);

sub is_agent($) {
	my ($nick) = @_;
	return (defined($agents{lc $nick}));
}

sub is_agent_in_chan($$) {
	my ($agent, $chan) = @_;
	$agent = lc $agent; $chan = lc $chan;

	if($agents{$agent} and $agents{$agent}{CHANS} and $agents{$agent}{CHANS}{$chan}) {
		return 1;
	} else {
		return 0;
	}
}

sub agent_connect($$$$$) {
	my ($nick, $ident, $host, $modes, $gecos) = @_;
	my $time = time();

	my @chans;
	if(defined($agents{lc $nick}) and ref($agents{lc $nick}{CHANS})) {
		@chans = keys(%{$agents{lc $nick}{CHANS}});
	}

	$agents{lc $nick}{PARMS} = [ @_ ];

	$host = main_conf_local unless $host;
	ircsend("@{[TOK_NICK]} $nick 1 $time $ident $host ".
		(SJB64 ? itob64(main_conf_numeric) : main_conf_local).
		" 1 $modes * :$gecos");

	foreach my $chan (@chans) {
		ircsend(":$nick @{[TOK_JOIN]} $chan");
		# If we tracked chanmodes for agents, that would go here as well.
	}
}

sub agent_quit($$) {
	my ($nick, $msg) = @_;

	delete($agents{lc $nick}{CHANS});
	delete($agents{lc $nick});

	ircsendimm(":$nick @{[TOK_QUIT]} :$msg");
}

sub agent_quit_all($) {
	my ($msg) = @_;

	my @agents;
	@agents = keys(%agents);

	foreach my $a (@agents) {
		agent_quit($a, $msg);
	}
}

sub is_invalid_agentname($$$) {
	my ($botnick, $botident, $bothost) = @_;

	unless(valid_nick($botnick)) {
		return "Invalid nickname.";
	}
	unless($botident =~ /^[[:alnum:]_]+$/) {
		return "Invalid ident.";
	}
	unless($bothost =~ /^[[:alnum:].-]+$/) {
		return "Invalid vhost.";
	}
	unless($bothost =~ /\./) {
		return "A vhost must contain at least one dot.";
	}
	return undef;
}

sub agent_join($$) {
	my ($agent, $chan) = @_;

	if($agents{lc $agent}) {
		$agents{lc $agent}{CHANS}{lc $chan} = 1;
		ircsend(":$agent @{[TOK_JOIN]} $chan");
	} else {
		if($ircd_ready) {
			print "Tried to make nonexistent agent ($agent) join channel ($chan)" if DEBUG;
		} else {
			print "Deferred join: $agent $chan\n" if DEBUG;
			push @defer_join, "$agent $chan";
		}
	}
}

sub agent_part($$$) {
	my ($agent, $chan, $reason) = @_;

	delete($agents{lc $agent}{CHANS}{lc $chan});
	ircsend(":$agent @{[TOK_PART]} $chan :$reason");
}

sub set_agent_umode($$) {
	my ($src, $modes) = @_;

	ircsend(":$src @{[TOK_UMODE2]} $modes");
}

sub agent_sync() {
	foreach my $j (@defer_join) {
		print "Processing join: $j\n" if DEBUG;
		my ($agent, $chan) = split(/ /, $j);
		agent_join($agent, $chan);
	}
	undef(@defer_join);
}

sub whois_callback {
#:wyvern.surrealchat.net 311 blah2 tabris northman SCnet-E5870F84.dsl.klmzmi.ameritech.net * :Sponsored by Skuld
#:wyvern.surrealchat.net 307 blah2 tabris :is a registered nick
#:wyvern.surrealchat.net 312 blah2 tabris wyvern.surrealchat.net :SurrealChat - aphrodite.wcshells.com - Chicago.IL
#:wyvern.surrealchat.net 671 blah2 tabris :is using a Secure Connection
#:wyvern.surrealchat.net 317 blah2 tabris 54 1118217330 :seconds idle, signon time
#:wyvern.surrealchat.net 401 blah2 nikanoru :No such nick/channel
#:wyvern.surrealchat.net 311 blah2 somebot bot SCnet-DA158DBF.hsd1.nh.comcast.net * :Some sort of bot
#:wyvern.surrealchat.net 312 blah2 somebot nascent.surrealchat.net :SurrealChat - Hub
#:wyvern.surrealchat.net 335 blah2 somebot :is a Bot on SurrealChat.net
#:wyvern.surrealchat.net 318 blah2 tabris,nikanoru,somebot :End of /WHOIS list.

# Also reference http://www.alien.net.au/irc/irc2numerics.html

	my ($src, $nicklist) = @_;

	my @nicks = split(/\,/, $nicklist);
	my @reply;
	foreach my $nick (@nicks) {
		if (is_agent($nick)) {
			my ($nick, $ident, $host, $modes, $gecos) = @{$agents{lc $nick}{PARMS}};
			$host = main_conf_local unless $host;
			push @reply, ':'.main_conf_local." 311 $src $nick $ident $host * :$gecos";
			push @reply, ':'.main_conf_local." 312 $src $nick ".main_conf_local.' :'.main_conf_info;
			foreach my $mode (split(//, $modes)) {
				if ($mode eq 'z') {
					push @reply, ':'.main_conf_local." 671 $src $nick :is using a Secure Connection";
				}
				elsif($mode eq 'S') {
					#313 tab ChanServ :is a Network Service
					push @reply, ':'.main_conf_local." 313 $src $nick :is a Network Service";
				}
				elsif($mode eq 'B') {
					#335 blah2 TriviaBot :is a Bot on SurrealChat.net
					push @reply, ':'.main_conf_local.
						" 335 $src $nick :is a \002Bot\002 on ".$IRCd_capabilities{NETWORK};
				}
			}
		}
		else {
			push @reply, ':'.main_conf_local." 401 $src $nick :No such service";
		}

	}
	push @reply, ':'.main_conf_local." 318 $src $nicklist :End of /WHOIS list.";
	ircsend(@reply);
}

sub kill_callback($$$$) {
	my ($src, $dst, $path, $reason) = @_;
	if (defined($agents{lc $dst})) {
		if (defined ($agents{lc $dst}{KILLED}) and ($agents{lc $dst}{KILLED} == time())) {
			if ($agents{lc $dst}{KILLCOUNT} > 3) {
				ircd::debug("Caught in a kill loop for $dst, dying now.");
				main_shutdown;
			} else {
				$agents{lc $dst}{KILLCOUNT}++;
			}
		} else {
			$agents{lc $dst}{KILLED} = time();
			$agents{lc $dst}{KILLCOUNT} = 1;
		}

		if($src =~ /\./) {
			# let's NOT loopback this event
			ircsendimm(':'.main_conf_local.' '."@{[TOK_KILL]} $dst :Nick Collision");
		} elsif (defined($agents{lc $src})) {
			# Do Nothing.
		} else {
			ircd::irckill($main::rsnick, $src, "Do not kill services agents.");
		}

		&agent_connect(@{$agents{lc $dst}{PARMS}}) if synced();
	}
}

1;
