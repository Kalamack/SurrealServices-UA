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
package logserv;

use strict;
no strict 'refs';
use Storable;

use SrSv::Process::InParent qw(chanlog addchan delchan ev_sjoin ev_join ev_part
ev_kick ev_mode ev_nickconn ev_nickchange ev_quit ev_message ev_notice
ev_chghost ev_kill ev_topic ev_connect saveconf loadconf join_chans);

use SrSv::Conf2Consts qw(main);
use SrSv::IRCd::Event 'addhandler';
use SrSv::IRCd::State 'initial_synced';
use SrSv::Agent;
use SrSv::User::Notice;
use SrSv::Log qw( :all );

my %userlist;
my %chanlist;

our $lsnick = 'LogServ';
my $chanopmode = '+v';

loadconf();
agent_connect($lsnick, 'services', undef, '+pqzBHSD', 'Log Service');
agent_join($lsnick, main_conf_diag);
ircd::setmode($lsnick, main_conf_diag, '+o', $lsnick);
join_chans();

sub chanlog($@) {
	my ($cn, @payload) = @_;
	write_log("logserv:$cn", '', @payload)
		# This if allows us to be lazy
		if defined($chanlist{lc $cn});
}

sub addchan($$) {
	my ($user, $cn) = @_;
	unless(defined($chanlist{lc $cn})) {
		open_log("logserv:$cn", lc($cn).'.log');
		$chanlist{lc $cn} = 1;
		agent_join($lsnick, $cn);
		ircd::setmode($lsnick, $cn, $chanopmode, $lsnick);
		notice($user, "Channel $cn will now be logged");
		saveconf();
		return 1;
	} else {
		notice($user, "Channel $cn is already being logged");
		return 0;
	}
}

sub delchan($$) {
	my ($user, $cn) = @_;
	if(defined($chanlist{lc $cn})) {
		close_log("logserv:$cn");
		delete($chanlist{lc $cn});
		agent_part($lsnick, $cn, "Channel has been deleted by ".$user->{NICK});
		notice($user, "Channel $cn will not be logged");
		saveconf();
		return 1;
	} else {
		notice($user, "Channel $cn is not being logged");
		return 0;
	}
}

# Handler Functions

addhandler('SJOIN', undef, undef, 'logserv::ev_sjoin');
sub ev_sjoin {
	# ($server, $cn, $ts, $chmodes, $chmodeparms, \@users, \@bans, \@excepts, \@invex);
	my (undef, $cn, undef, undef, undef, $users, undef, undef, undef) = @_;
	foreach my $user (@$users) {
		ev_join($user->{NICK}, $cn);
	}
}

addhandler('JOIN', undef, undef, 'logserv::ev_join');
sub ev_join {
	my ($nick, $cn) = @_;
	return if is_agent($nick); # Ignore agent joins.
	return unless defined($userlist{lc $nick}); # Sometimes we get JOINs after a KILL or QUIT
	{
		$userlist{lc $nick}{CHANS}{$cn} = 1;
	}
	if(initial_synced()) {
		if($cn eq '0') {
			foreach my $cn (keys(%{$userlist{lc $nick}{CHANS}})) {
				ev_part($nick, $cn, 'Left all channels');
			}
		} else {
			my ($ident, $vhost) = @{$userlist{lc $nick}{INFO}};
			chanlog($cn, "-!- $nick [$ident\@$vhost] has joined $cn");
		}
	}
}

addhandler('PART', undef, undef, 'logserv::ev_part');
sub ev_part {
	my ($nick, $cn, $reason) = @_;
	return if is_agent($nick); # Ignore agent parts.
	return unless defined($userlist{lc $nick}); # Sometimes we get JOINs after a KILL or QUIT
	{
		delete($userlist{lc $nick}{CHANS}{$cn});
	}
	my ($ident, $vhost) = @{$userlist{lc $nick}{INFO}};
	chanlog("$cn", "-!- $nick [$ident\@$vhost] has left $cn [$reason]");
}

addhandler('KICK', undef, undef, 'logserv::ev_kick');
sub ev_kick {
	my ($src, $cn, $target, $reason) = @_;
	return unless defined($userlist{lc $target}); # Sometimes we get JOINs after a KILL or QUIT
	if(lc $target eq lc $lsnick) {
		agent_join($lsnick, $cn);
		ircd::setmode($lsnick, $cn, '+o', $lsnick);
		return;
	}
	{
		delete($userlist{lc $target}{CHANS}{$cn});
	}
	chanlog("$cn", "-!- $target was kicked by $src [$reason]");
}

addhandler('MODE', undef, undef, 'logserv::ev_mode');
sub ev_mode {
	my ($src, $cn, $modes, $parms) = @_;
	return unless initial_synced();
	chanlog("$cn", "-!- mode/$cn [$modes".($parms ? " $parms" : '')."] by $src");
}

addhandler('NICKCONN', undef, undef, 'logserv::ev_nickconn');
sub ev_nickconn {
	my ($nick, $ident, $host, $modes, $vhost, $cloakhost) = @_[0,3,4,7,8,11];
        if ($vhost eq '*') {
                if ({modes::splitumodes($modes)}->{x} eq '+') {
                        if(defined($cloakhost)) {
                                $vhost = $cloakhost;
                        }
                        else {
				# Since we have no desire to do ircd::userhost checks
				# This makes us dependent on VHP or CLK.
				# Do we care? Not at the moment.
				# This should NEVER happen with VHP or CLK.
				$vhost = $host;
                        }
                } else {
                        $vhost = $host;
                }
        }
	$userlist{lc $nick} = {
		INFO => [$ident, $vhost],
		CHANS => {},
	};
}

addhandler('NICKCHANGE', undef, undef, 'logserv::ev_nickchange');
sub ev_nickchange {
	my ($old, $new) = @_;
	return unless defined($userlist{lc $old}); # Sometimes we get JOINs after a KILL or QUIT
	unless (lc($old) eq lc($new)) {
		$userlist{lc $new} = $userlist{lc $old};
		delete($userlist{lc $old});
	}
	foreach my $cn (keys(%{$userlist{lc $new}{CHANS}})) {
		chanlog($cn, "-!- $old is now known as $new");
	}
}

addhandler('QUIT', undef, undef, 'logserv::ev_quit');
sub ev_quit {
	my ($nick, $reason) = @_;
	my ($ident, $vhost) = @{$userlist{lc $nick}{INFO}};
	if (initial_synced()) {
		foreach my $cn (keys(%{$userlist{lc $nick}{CHANS}})) {
			chanlog($cn, "$nick [$ident\@$vhost] has quit [$reason]");
		}
	}
	delete($userlist{lc $nick});
}

addhandler('LOOP_PRIVMSG', undef, qr/^#/, 'logserv::ev_loop_message');
sub ev_loop_message {
	my ($nick, $cn, $messages) = @_;
	my $channel = $cn;
	$channel =~ s/^[+%@&~]+//;
	return unless defined($chanlist{lc $channel});
	foreach my $message (@$messages) {
		if ($message =~ /^\001(\w+)(?: (.*))\001$/i) {
			my ($ctcp, $payload) = ($1, $2);
			if($ctcp eq 'ACTION') {
				$message = "* $nick $payload";
			}
			else {
				$message = "$nick requested CTCP $1 from $cn: $2";
			}
		} else {
			$message = "<$nick> $message";
		}
	}
	chanlog($channel, @$messages);
}
addhandler('LOOP_NOTICE', undef, qr/^#/, 'logserv::ev_loop_notice');
sub ev_loop_notice {
	my ($nick, $cn, $messages) = @_;
	my $channel = $cn;
	$channel =~ s/^[+%@&~]+//;
	return unless defined($chanlist{lc $channel});
	foreach my $message (@$messages) {
		$message = "-$nick:$cn- $message";
	}
	chanlog($channel, @$messages);
}

addhandler('PRIVMSG', undef, qr/^#/, 'logserv::ev_message');
sub ev_message {
	my ($nick, $cn, $message) = @_;
	my $channel = $cn;
	$channel =~ s/^[+%@&~]+//;
	return unless defined($chanlist{lc $channel});
	if ($message =~ /^\001(\w+)(?: (.*))\001$/i) {
		my ($ctcp, $payload) = ($1, $2);
		if($ctcp eq 'ACTION') {
			chanlog($channel, "* $nick $payload");
		}
		else {
			chanlog($channel, "$nick requested CTCP $1 from $cn: $2");
		}
	} else {
		chanlog($channel, "<$nick> $message");
	}
	
}
addhandler('NOTICE', undef, qr/^#/, 'logserv::ev_notice');
sub ev_notice {
	my ($nick, $cn, $message) = @_;
	my $channel = $cn;
	$channel =~ s/^[+%@&~]+//;
	return unless defined($chanlist{lc $channel});
	chanlog($channel, "-$nick:$cn- $message");
}

addhandler('CHGHOST', undef, undef, 'logserv::ev_chghost');
sub ev_chghost {
	my (undef, $nick, $vhost) = @_;
	return unless defined($userlist{lc $nick}); # Sometimes we get JOINs after a KILL or QUIT
	{
		my ($ident, undef) = @{$userlist{lc $nick}{INFO}};
		$userlist{lc $nick}{INFO} = [$ident, $vhost];
	}
	
}

addhandler('KILL', undef, undef, 'logserv::ev_kill');
sub ev_kill {
	my ($src, $target, $reason) = @_;
	return if is_agent($target) or !defined($userlist{lc $target}); # Ignore agent kills.
	my ($ident, $vhost) = @{$userlist{lc $target}{INFO}};
	if (initial_synced()) {
		foreach my $cn (keys(%{$userlist{lc $target}{CHANS}})) {
			chanlog($cn, "$target [$ident\@$vhost] has quit [Killed ($src ($reason))]");
		}
	}
	delete($userlist{lc $target});
}

addhandler('TOPIC', undef, undef, 'logserv::ev_topic');
sub ev_topic {
	my ($src, $cn, $setter, undef, $topic) = @_;
	# We don't care about the timestamp
	return unless initial_synced();
	chanlog($cn, "$src changed the topic of $cn to: $topic".($setter ne $src ? " ($setter)" : ''));
}

# Internal Only functions.

sub saveconf() {
	my @channels = keys(%chanlist);
	Storable::nstore(\@channels, "config/logserv/chans.conf");
}

sub loadconf() {
	(-d "config/logserv") or mkdir "config/logserv";
	return unless(-f "config/logserv/chans.conf");
	my @channels = @{Storable::retrieve("config/logserv/chans.conf")};
	foreach my $cn (@channels) {
		$chanlist{lc $cn} = 1;
	}
}

sub join_chans() {
	foreach my $cn (keys(%chanlist)) {
		open_log("logserv:$cn", lc($cn).'.log');
		agent_join($lsnick, $cn);
		ircd::setmode($lsnick, $cn, $chanopmode, $lsnick);
	}
}

sub init { }
sub begin { }
sub end { }
sub unload { saveconf(); }

1;
