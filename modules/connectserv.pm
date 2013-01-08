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
package connectserv;

use strict;
no strict 'refs';

use SrSv::IRCd::State qw( initial_synced synced );
use SrSv::IRCd::Event 'addhandler';
use SrSv::RunLevel qw( $runlevel :levels );

use SrSv::Conf::Parameters connectserv => [
	[ joinpart => 0 ],
];

use SrSv::Conf2Consts qw( main connectserv );

use SrSv::Log;

use SrSv::Process::InParent qw(
	ev_nickconn ev_nickchange ev_quit ev_kill ev_umode ev_connect message
);

my %userlist;

use SrSv::Agent;

my $csnick = 'ConnectServ';
agent_connect($csnick, 'services', undef, '+pqzBHS', 'Connection Monitor');
my $csUser = { NICK => $csnick };
if(ircd::TS6_UID) {
	$csUser->{ID} = ircd::getUuid($csnick);
}
agent_join($csnick, main_conf_diag);
ircd::setmode($csUser, main_conf_diag, '+o', $csUser);

addhandler('NICKCONN', undef, undef, 'connectserv::ev_nickconn', 1);
sub ev_nickconn {
	my ($nick, $ident, $host, $server, $gecos) = @_[0,3,4,5,9];

	$userlist{lc $nick} = [$ident, $host, $gecos, $server];

	return unless initial_synced();
	message("\00304\002SIGNED ON\002 user: \002$nick\002 ($ident\@$host - $gecos\017\00304) at $server");
}

addhandler('NICKCHANGE', undef, undef, 'connectserv::ev_nickchange', 1);
sub ev_nickchange {
	my ($old, $new) = @_;
	my ($ident, $host);
	unless(lc($new) eq lc($old)) {
		$userlist{lc $new} = $userlist{lc $old};
		delete($userlist{lc $old});
	}
	($ident, $host) = @{$userlist{lc $new}} if (defined($userlist{lc $new}));
	message("\00307\002NICK CHANGE\002 user: \002$old\002 ($ident\@$host) changed their nick to \002$new\002");
}

addhandler('CHGIDENT', undef, undef, 'connectserv::ev_identchange', 1);
sub ev_identchange {
	my (undef, $nick, $ident) = @_;

	my ($oldident, $host, $gecos, $server);
	($oldident, $host, $gecos, $server) = @{$userlist{lc $nick}} if (defined($userlist{lc $nick}));
	$userlist{lc $nick} = [$ident, $host, $gecos, $server];

	message("\00310\002IDENT CHANGE\002 user: \002$nick\002 ($oldident\@$host) changed their virtual ident to \002$ident\002");
}

addhandler('QUIT', undef, undef, 'connectserv::ev_quit', 1);
sub ev_quit {
	my ($nick, $reason) = @_;
	return unless synced() && $runlevel == ST_NORMAL;
	my ($ident, $host, $gecos, $server);
	if(defined($userlist{lc $nick})) {
		($ident, $host, $gecos, $server) = @{$userlist{lc $nick}};
		delete($userlist{lc $nick});
	}
	return unless initial_synced();
	message("\00303\002SIGNED OFF\002 user: \002$nick\002 ($ident\@$host - $gecos\017\00303) at $server - $reason");
}

addhandler('KILL', undef, undef, 'connectserv::ev_kill', 1);
sub ev_kill {
	my ($src, $target, $reason) = @_[0,1,3];
	my ($ident, $host, $gecos, $server);
	if(defined($userlist{lc $target})) {
		($ident, $host, $gecos, $server) = @{$userlist{lc $target}};
		delete($userlist{lc $target});
	}
	message("\00302\002GLOBAL KILL\002 user: \002$target\002 ($ident\@$host) killed by \002$src\002 - $reason");
}

addhandler('UMODE', undef, undef, 'connectserv::ev_umode', 1);
sub ev_umode {
	my ($nick, $modes) = @_;
	my @modes = split(//, $modes);
	my $sign;
	foreach my $m (@modes) {
		$sign = 1 if $m eq '+';
		$sign = 0 if $m eq '-';

		my $label;
		$label = 'Global Operator' if $m eq 'o';
		$label = 'Services Administrator' if $m eq 'a';
		$label = 'Server Administrator' if $m eq 'A';
		$label = 'Network Administrator' if $m eq 'N';
		$label = 'Co Administrator' if $m eq 'C';
		$label = 'Bot' if $m eq 'B';

		if($label) {
			message("\00306\002$nick\002 is ".($sign ? 'now' : 'no longer')." a \002$label\002 (".($sign ? '+' : '-')."$m)");
		}
	}
}

addhandler('SJOIN', undef, undef, 'connectserv::chan_join', 1) if connectserv_conf_joinpart;
sub chan_join {
	my ($server, $cn, $ts, $chmodes, $chmodeparms, $userarray, $banarray, $exceptarray) = @_;
	return unless synced() && $runlevel == ST_NORMAL;
	foreach my $user (@$userarray) {
		my $nick = $user->{NICK};
		message ("\00310CHANNEL JOIN: \002$nick\002 joined to \002$cn\002\003");
	}
}

addhandler('PART', undef, undef, 'connectserv::chan_part', 1) if connectserv_conf_joinpart;
sub chan_part {
	my ($nick, $cn) = @_;
	return unless synced() && $runlevel == ST_NORMAL;
	message ("\00310CHANNEL PART: \002$nick\002 parted from \002$cn\002\003");
}

addhandler('JOIN', undef, undef, 'connectserv::chan_join0', 1) if connectserv_conf_joinpart;
sub chan_join0 {
	my ($nick, $cn) = @_;
	return unless synced() && $runlevel == ST_NORMAL;
	if($cn eq '0') {
		message ("\00310CHANNEL PART: \002$nick\002 parted all channels\003");
	} else {
		message ("\00310CHANNEL JOIN: \002$nick\002 joined to \002$cn\002\003");
	}
}

sub message(@) {
	ircd::privmsg($csnick, main_conf_diag, @_);
	write_log('diag', '<'.$csnick.'>', @_);
}

sub init { }
sub begin { }
sub end { }
sub unload { }

1;
