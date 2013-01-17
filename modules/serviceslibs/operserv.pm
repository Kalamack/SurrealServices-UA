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
package operserv;

use strict;

use SrSv::Timer qw(add_timer);

use SrSv::IRCd::State qw(get_server_state);
use SrSv::IRCd::Validate qw( valid_server valid_nick );

use SrSv::Time;
use SrSv::Text::Format qw(columnar);
use SrSv::Errors;
use SrSv::Log;

use SrSv::Conf2Consts qw(main services);

use SrSv::User qw(get_user_nick get_user_id get_user_agent is_online get_user_info get_user_ip :flood);
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::NickReg::Flags qw(NRF_NOHIGHLIGHT nr_chk_flag_user);

use SrSv::MySQL '$dbh';

use SrSv::IPv6;

use constant {
	MAX_LIM => 16777215
};

*kill_user = \&nickserv::kill_user;

our $osnick_default = 'OperServ';
our $osnick = $osnick_default;

my %newstypes = (
	u => 'User',
	o => 'Oper'
);

=cut
	$add_akill, $del_akill, $get_all_akills, $get_expired_akills,
	$get_akill, $check_akill,
=cut

our (
	$add_qline, $del_qline, $get_all_qlines, $get_expired_qlines,
	$get_qline, $check_qline,

	$add_logonnews, $del_logonnews, $list_logonnews, $get_logonnews,
	$consolidate_logonnews, $count_logonnews, $del_expired_logonnews,

	$add_clone_exceptname, $add_clone_exceptserver, $add_clone_exceptip,
	$del_clone_exceptname, $del_clone_exceptip,
	$list_clone_exceptname, $list_clone_exceptserver, $list_clone_exceptip,

	$get_clones_fromhost, $get_clones_fromnick, $get_clones_fromid, $get_clones_fromipv4,

	$get_session_list,

	$get_newusers, $get_newusers_noid
);

sub init() {
=cut
	$add_akill = $dbh->prepare("INSERT INTO akill SET setter=?, mask=?, reason=?, time=?, expire=?");
	$del_akill = $dbh->prepare("DELETE FROM akill WHERE mask=?");
	$get_all_akills = $dbh->prepare("SELECT setter, mask, reason, time, expire FROM akill ORDER BY time ASC");
	$get_akill = $dbh->prepare("SELECT setter, mask, reason, time, expire FROM akill WHERE mask=?");
	$check_akill = $dbh->prepare("SELECT 1 FROM akill WHERE mask=?");

	$get_expired_akills = $dbh->prepare("SELECT setter, mask, reason, time, expire FROM akill WHERE expire < UNIX_TIMESTAMP() AND expire!=0");
=cut

	$add_qline = $dbh->prepare("INSERT INTO qline SET setter=?, mask=?, reason=?, time=?, expire=?");
	$del_qline = $dbh->prepare("DELETE FROM qline WHERE mask=?");
	$get_all_qlines = $dbh->prepare("SELECT setter, mask, reason, time, expire FROM qline ORDER BY time ASC");
	$get_qline = $dbh->prepare("SELECT setter, mask, reason, time, expire FROM qline WHERE mask=?");
	$check_qline = $dbh->prepare("SELECT 1 FROM qline WHERE mask=?");

	$get_expired_qlines = $dbh->prepare("SELECT mask FROM qline WHERE expire < UNIX_TIMESTAMP() AND expire!=0");

	$add_logonnews = $dbh->prepare("INSERT INTO logonnews SET setter=?, expire=?, type=?, id=?, msg=?, time=UNIX_TIMESTAMP()");
	$del_logonnews = $dbh->prepare("DELETE FROM logonnews WHERE type=? AND id=?");
	$list_logonnews = $dbh->prepare("SELECT setter, time, expire, id, msg FROM logonnews WHERE type=? ORDER BY id ASC");
	$get_logonnews = $dbh->prepare("SELECT setter, time, msg FROM logonnews WHERE type=? ORDER BY id ASC");
	$consolidate_logonnews = $dbh->prepare("UPDATE logonnews SET id=id-1 WHERE type=? AND id>?");
	$count_logonnews = $dbh->prepare("SELECT COUNT(*) FROM logonnews WHERE type=?");
	$del_expired_logonnews = $dbh->prepare("DELETE FROM logonnews WHERE expire < UNIX_TIMESTAMP() AND expire!=0");
	
	$add_clone_exceptname = $dbh->prepare("REPLACE INTO sesexname SET host=?, serv=0, adder=?, lim=?");
	$add_clone_exceptserver = $dbh->prepare("REPLACE INTO sesexname SET host=?, serv=1, adder=?, lim=?");
	$add_clone_exceptip = $dbh->prepare("REPLACE INTO sesexip SET ip=INET_ATON(?), mask=?, adder=?, lim=?");

	$del_clone_exceptname = $dbh->prepare("DELETE FROM sesexname WHERE host=?");
	$del_clone_exceptip = $dbh->prepare("DELETE FROM sesexip WHERE ip=INET_ATON(?)");

	$list_clone_exceptname = $dbh->prepare("SELECT host, adder, lim FROM sesexname WHERE serv=0 ORDER BY host ASC");
	$list_clone_exceptserver = $dbh->prepare("SELECT host, adder, lim FROM sesexname WHERE serv=1 ORDER BY host ASC");
	$list_clone_exceptip = $dbh->prepare("SELECT INET_NTOA(ip), mask, adder, lim FROM sesexip ORDER BY ip ASC");

	$get_clones_fromhost = $dbh->prepare("SELECT user.nick, user.id, user.online
		FROM user JOIN user AS clone ON (user.ip=clone.ip)
		WHERE clone.host=? GROUP BY id");
	$get_clones_fromnick = $dbh->prepare("SELECT user.nick, user.id, user.online
		FROM user JOIN user AS clone ON (user.ip=clone.ip)
		WHERE clone.nick=? GROUP BY id");
	$get_clones_fromid = $dbh->prepare("SELECT user.nick, user.id, user.online
		FROM user JOIN user AS clone ON (user.ip=clone.ip)
		WHERE clone.id=? GROUP BY id");
	$get_clones_fromipv4 = $dbh->prepare("SELECT user.nick, user.id, user.online
		FROM user JOIN user AS clone ON (user.ip=clone.ip)
		WHERE clone.ip=INET_ATON(?) GROUP BY id");

	$get_session_list = $dbh->prepare("SELECT host, COUNT(*) AS c FROM user WHERE online=1 GROUP BY host HAVING c >= ?");

	$get_newusers = $dbh->prepare("SELECT user.nick, user.id, user.online
		FROM user
		WHERE user.time > ?");
	$get_newusers_noid = $dbh->prepare("SELECT user.nick, user.id, user.online
		FROM user LEFT JOIN nickid ON (nickid.id=user.id)
		WHERE nickid.id IS NULL AND user.time > ?");
}

sub dispatch($$$) {
	my ($src, $dst, $msg) = @_;
	$msg =~ s/^\s+//;
	my @args = split(/\s+/, $msg);
	my $cmd = shift @args;

	my $user = { NICK => $src, AGENT=> $dst };

	services::ulog($osnick, LOG_INFO(), "cmd: [$msg]", $user);

	return if flood_check($user);
	unless(adminserv::is_svsop($user) or adminserv::is_ircop($user)) {
		notice($user, $err_deny);
		if($cmd =~ /^set/i) {
			nickserv::kill_user($user, "OS SET doesn't exist here");
		}
		ircd::globops($osnick, "\002$src\002 failed access to $osnick $msg");
		return;
	}

	if ($cmd =~ /^fjoin$/i) 	{ os_fjoin($user, @args); }
	elsif ($cmd =~ /^fpart$/i) 	{ os_fpart($user, @args); }
	elsif ($cmd =~ /^unidentify$/i)	{ os_unidentify($user, @args); }
	elsif ($cmd =~ /^qline$/i) {
		my $cmd2 = shift @args;

		if($cmd2 =~ /^add$/i) {
			if(@args >= 3 and $args[0] =~ /^\+/) {
				@args = split(/\s+/, $msg, 5);
				
				os_qline_add($user, @args[2..4]);
			}
			elsif(@args >= 2) {
				@args = split(/\s+/, $msg, 4);
				
				os_qline_add($user, 0, @args[2..3]);
			}
			else {
				notice($user, 'Syntax: QLINE ADD [+expiry] <mask> <reason>');
			}
		}
		elsif($cmd2 =~ /^del$/i) {
			if(@args == 1) {
				os_qline_del($user, $args[0]);
			}
			else {
				notice($user, 'Syntax: QLINE DEL <mask>');
			}
		}
		elsif($cmd2 =~ /^list$/i) {
			if(@args == 0) {
				os_qline_list($user);
			}
			else {
				notice($user, 'Syntax: QLINE LIST');
			}
		}
	}	
	elsif ($cmd =~ /^jupe$/i) {
		if(@args >= 2) {
			os_jupe($user, shift @args, join(' ', @args));
		}
		else {
			notice($user, 'Syntax: JUPE <server> <reason>');
		}
	}
	elsif ($cmd =~ /^uinfo$/i)	{ os_uinfo($user, @args); }
	elsif ($cmd =~ /^ninfo$/i)	{ os_ninfo($user, @args); }
	elsif ($cmd =~ /^svsnick$/i)	{ os_svsnick($user, $args[0], $args[1]); }
	elsif ($cmd =~ /^gnick$/i)	{ os_gnick($user, @args); }
	elsif ($cmd =~ /^help$/i)	{ sendhelp($user, 'operserv', @args) }
	elsif ($cmd =~ /^(staff|listadm)$/i)	{ adminserv::as_staff($user) }
	elsif ($cmd =~ /^logonnews$/i) {
		my $cmd2 = shift @args;

		if($cmd2 =~ /^add$/i) {
			if(@args >= 3 and $args[1] =~ /^\+/) {
				@args = split(/\s+/, $msg, 5);

				os_logonnews_add($user, $args[2], $args[3], $args[4]);
			}
			elsif(@args >= 2) {
				@args = split(/\s+/, $msg, 4);

				os_logonnews_add($user, $args[2], 0, $args[3]);
			}
			else {
				notice($user, 'Syntax: LOGONNEWS ADD <type> [+expiry] <reason>');
			}
		}
		elsif($cmd2 =~ /^del$/i) {
			if(@args == 2) {
				os_logonnews_del($user, $args[0], $args[1]);
			}
			else {
				notice($user, 'Syntax: LOGONNEWS DEL <type> <id>');
			}
		}
		elsif($cmd2 =~ /^list$/i) {
			if(@args == 1) {
				os_logonnews_list($user, $args[0]);
			}
			else {
				notice($user, 'Syntax: LOGONNEWS LIST <type>');
			}
		}
		else {
			notice($user, 'Syntax: LOGONNEWS <LIST|ADD|DEL> <type>');
		}
	}
	elsif($cmd =~ /^except(ion)?$/i) {
		my $cmd2 = shift @args;
		if($cmd2 =~ /^server$/i) {
			my $cmd3 = shift @args;
			if($cmd3 =~ /^a(dd)?$/) {
				if(@args == 2) {
					os_except_server_add($user, $args[0], $args[1]);
				}
				else {
					notice($user, 'Syntax EXCEPT SERVER ADD <hostname> <limit>');
				}
			}
			elsif($cmd =~ /^d(el)?$/) {
				if(@args == 1) {
					os_except_server_del($user, $args[0]);
				}
				else {
					notice($user, 'Syntax EXCEPT SERVER DEL <hostname>');
				}
			}
			else {
				notice($user, 'Syntax EXCEPT SERVER <ADD|DEL>');
			}
		}
		elsif($cmd2 =~ /^h(ostname)?$/i) {
			my $cmd3 = shift @args;
			if($cmd3 =~ /^a(dd)?$/) {
				if(@args == 2) {
					os_except_hostname_add($user, $args[0], $args[1]);
				}
				else {
					notice($user, 'Syntax EXCEPT HOSTNAME ADD <hostname> <limit>');
				}
			}
			elsif($cmd3 =~ /^d(el)?$/) {
				if(@args == 1) {
					os_except_hostname_del($user, $args[0]);
				}
				else {
					notice($user, 'Syntax EXCEPT HOSTNAME DEL <hostname>');
				}
			}
			else {
				notice($user, 'Syntax EXCEPT HOSTNAME <ADD|DEL>');
			}
		}
		elsif($cmd2 =~ /^i(p)?$/i) {
			my $cmd3 = shift @args;
			if($cmd3 =~ /^a(dd)?$/) {
				if(@args == 2) {
					os_except_IP_add($user, $args[0], $args[1]);
				}
				else {
					notice($user, 'Syntax EXCEPT IP ADD <IP/mask> <limit>');
				}
			}
			elsif($cmd3 =~ /^d(el)?$/) {
				if(@args == 1) {
					os_except_IP_del($user, $args[0]);
				}
				else {
					notice($user, 'Syntax EXCEPT IP DEL <IP>');
				}
			}
			else {
				notice($user, 'Syntax EXCEPT IP <ADD|DEL>');
			}
		}
		elsif($cmd2 =~ /^l(ist)?$/i) {
			if(@args == 0) {
				os_except_list($user);
			}
			else {
				notice($user, 'Syntax EXCEPT LIST');
			}
		}
		else {
			notice($user, 'Syntax: EXCEPT <SERVER|HOSTNAME|IP|LIST>');
		}
	}
	elsif($cmd =~ /^session$/i) {
		if(@args == 1) {
			os_session_list($user, $args[0]);
		} else {
			notice($user, 'Syntax SESSION <lim>');
		}
	}
	elsif($cmd =~ /^chankill$/i) {
		if(@args >= 2) {
			(undef, @args) = split(/\s+/, $msg, 3);
			os_chankill($user, @args);
		} else {
			notice($user, 'Syntax: CHANKILL <#chan> <reason>');
		}
	}
	elsif ($cmd =~ /^rehash$/i) {
		if(@args <= 1) {
			os_rehash($user, @args);
		}
		else {
			notice($user, 'Syntax: REHASH [type]');
		}
	}
	elsif ($cmd =~ /^loners$/i) {
		os_loners($user, @args);
	}
	elsif($cmd =~ /^svskill$/i) {
		if(@args >= 2) {
			os_svskill($user, shift @args, join(' ', @args));
		}
		else {
			notice($user, 'Syntax SVSKILL <target> <reason here>');
		}
	}
	elsif($cmd =~ /^kill$/i) {
		if(@args >= 1) {
			os_kill($user, shift @args, join(' ', @args));
		}
		else {
			notice($user, 'Syntax KILL <target> <reason here>');
		}
	}
	elsif ($cmd =~ /^clones$/i) {
		os_clones($user, @args);
	}
	elsif ($cmd =~ /^m(ass)?kill$/i) {
		os_clones($user, 'KILL', @args);
	}
	elsif($cmd =~ /^(kline|gline)$/i) {
	        if(@args >= 1) {
	                os_gline($user, 0, @args);
	        }
	        else {
			notice($user, 'Syntax GLINE <target> [+time] [reason here]');
		}
	}
	elsif($cmd =~ /^(zline|gzline)$/i) {
		if(@args >= 1) {
			os_gline($user, 1, @args);
		}
		else {
			notice($user, 'Syntax GZLINE <target> [+time] [reason here]');
		}
	}
	elsif ($cmd =~ /^killnew$/i) {
		os_killnew($user, @args);
	}

	else { notice($user, "Unknown command."); }
}

sub os_fjoin($$@) {
	my ($user, $target, @chans) = @_;
	if ((!$target or !@chans) or !($chans[0] =~ /^#/)) {
		notice($user, "Syntax: /OS FJOIN <nick> <#channel1> [#channel2]");
	}
	unless (is_online($target)) {
		notice($user, "\002$target\002 is not online");
		return;
	}
    
	if (!adminserv::can_do($user, 'FJOIN')) {
		notice($user, "You don't have the right access");
		return $event::SUCCESS;
	}
	ircd::svsjoin($osnick, $target, @chans);
}

sub os_fpart($$@) {
	my ($user, $target, @params) = @_;
	if ((!$target or !@params) or !($params[0] =~ /^#/)) {
		notice($user, "Syntax: /OS FPART <nick> <#channel1> [#channel2] [reason]");
	}
	unless (is_online($target)) {
		notice($user, "\002$target\002 is not online");
		return;
	}

	if (!adminserv::can_do($user, 'FJOIN')) {
		notice($user, "You don't have the right access");
		return $event::SUCCESS;
	}
	
	my ($reason, @chans);
	while ($params[0] =~ /^#/) {
		push @chans, shift @params;
	}
	$reason = join(' ', @params) if @params;
	
	ircd::svspart($osnick, $target, $reason, @chans);
}

sub os_qline_add($$$$) {
	my ($user, $expiry, $mask, $reason) = @_;
	
	chk_auth($user, 'QLINE') or return;
	
	$expiry = parse_time($expiry);
	if($expiry) { $expiry += time() }
	else { $expiry = 0 }
	
	$check_qline->execute($mask);
	if ($check_qline->fetchrow_array) {
		notice($user, "$mask is already qlined");
		return $event::SUCCESS;
	} else {
		my $src = get_user_nick($user);
		$add_qline->execute($src, $mask, $reason, time(), $expiry);
		ircd::sqline($mask, $reason);
		notice($user, "$mask is now Q:lined");
	}
}

sub os_qline_del($$) {
	my($user, $mask) = @_;
	
	chk_auth($user, 'QLINE') or return;
	
	$check_qline->execute($mask);
	if($check_qline->fetchrow_array) {
		$del_qline->execute($mask);
		ircd::unsqline($mask);
		notice($user, "$mask unqlined");
	} else {
		notice($user, "$mask is not qlined");
	}
}

sub os_qline_list($) {
	my ($user) = @_;
	my (@reply);

	chk_auth($user, 'QLINE') or return;

	push @reply, 'Q:line list:';
	
	$get_all_qlines->execute();
	my $i;
	while (my ($setter, $mask, $reason, $time, $expiry) = $get_all_qlines->fetchrow_array) {
		$i++;
		my $akill_entry1 = "  $i) \002$mask\002  $reason";
		my $akill_entry2 = "    set by $setter on ".gmtime2($time).'; ';
		if($expiry) {
			my ($weeks, $days, $hours, $minutes, $seconds) = split_time($expiry-time());
			$akill_entry2 .= "Expires in ".($weeks?"$weeks weeks ":'').
				($days?"$days days ":'').
				($hours?"$hours hours ":'').
				($minutes?"$minutes minutes ":'');
		}
		else {
			$akill_entry2 .= "Does not expire.";
		}
		push @reply, $akill_entry1; push @reply, $akill_entry2;
	}
	$get_all_qlines->finish();
	push @reply, ' --';

	notice($user, @reply) if @reply;
}

sub os_jupe($$$) {
	# introduces fake server to network.
	my ($user, $server, $reason) = @_;

	unless (adminserv::is_svsop($user, adminserv::S_ROOT())) {
		notice($user, $err_deny);
		return $event::SUCCESS;
	}
	unless (valid_server($server)) {
		notice($user, "$server is not a valid servername.");
		return $event::SUCCESS;
	}
	if (get_server_state($server)) {
		notice($user, "$server is currently connected. You must SQUIT before using JUPE.");
		return $event::SUCCESS;
	}

	ircd::jupe_server($server, "Juped by ".get_user_nick($user).": $reason");
	notice($user, "$server is now juped.");
	return $event::SUCCESS;
}

sub os_unidentify($$) {
	my ($user, $tnick) = @_;
	
	my $tuser = { NICK => $tnick };
	my $tuid;
	
	unless ($tuid = get_user_id($tuser)) {
		notice($user, "\002$tnick\002 is not online");
	}
	unless (adminserv::can_do($user, 'SERVOP')) {
		notice($user, $err_deny);
	}
	$nickserv::logout->execute($tuid);
	notice($user, "$tnick logged out from all nick identifies");
}

sub os_uinfo($@) {
	my ($user, @targets) = @_;

	my @userlist;
	my @reply;
	foreach my $target (@targets) {
		if(ref($target)) {
			push @userlist, $target;
			next;
		}
		if($target =~ /\,/) {
			push @targets, split(',', $target);
			next;
		}
		my @data;
		my $tuser = { NICK => $target };
		my $tuid = get_user_id($tuser);
		unless ($tuid) {
			push @reply, "\002$target\002: user not found";
			next;
		}
		push @userlist, $tuser;
	}
	@targets = (); # drop this list now.

	notice($user, @reply, get_uinfo($user, @userlist));
	return $event::SUCCESS;
}

sub os_ninfo($@) {
	my ($user, @targetsIn) = @_;

	my (@targetsOut, @reply);
	foreach my $target (@targetsIn) {
		if(not nickserv::is_registered($target)) {
			push @reply, "\002$target\002: is not registered.";
		}
		my @targets = SrSv::NickReg::User::get_nick_users_all($target);
		if(scalar(@targets) == 0) {
			push @reply, "\002$target\002: no user[s] online.";
			next;
		}
		push @targetsOut, @targets;
	}
	@targetsIn = (); # drop this list now.
	notice($user, @reply) if scalar(@reply);
	if(scalar(@targetsOut)) {
		return os_uinfo($user, @targetsOut);
	}
	return $event::SUCCESS;
}

sub os_svsnick($$$) {
	my ($user, $curnick, $newnick) = @_;
	my $tuser = { NICK => $curnick };

	if(!adminserv::is_svsop($user, adminserv::S_ROOT())) {
		notice($user, $err_deny);
		return $event::SUCCESS;
	}
	if ((!$curnick) or (!$newnick)) {
		notice($user, "Syntax: SVSNICK <curnick> <newnick>");
		return $event::SUCCESS;
	}
	if (!is_online($tuser)) {
		notice($user, $curnick.' is not online.');
		return $event::SUCCESS;
	}
	if (nickserv::is_online($newnick)) {
		notice($user, $newnick.' already exists.');
		return $event::SUCCESS;
	}
	nickserv::enforcer_quit($newnick);
	ircd::svsnick($osnick, $curnick, $newnick);
	notice($user, $curnick.' changed to '.$newnick);
	return $event::SUCCESS;
}

sub os_gnick($@) {
	my ($user, @targets) = @_;

	if(!adminserv::can_do($user, 'QLINE')) {
		notice($user, $err_deny);
		return $event::SUCCESS;
	}
	if (@targets == 0) {
		notice($user, "Syntax: GNICK <nick>");
		return $event::SUCCESS;
	}
	foreach my $target (@targets) {
		if (!is_online($target)) {
			notice($user, $target.' is not online.');
			next;
		}
		my $newnick = nickserv::collide($target);
		notice($user, $target.' changed to '.$newnick);
	}
	return $event::SUCCESS;
}

sub os_logonnews_pre($$) {
	my ($user, $type) = @_;

	unless(adminserv::is_svsop($user, adminserv::S_ADMIN())) {
		notice($user, $err_deny);
		return undef;
	}

	return 'u' if($type =~ /^(user)|(u)$/i);
	return 'o' if($type =~ /^(oper)|(o)$/i);
	notice($user, 'invalid LOGONNEWS <type>');
	return undef;
}

sub os_logonnews_add($$$) {
	my ($user, $type, $expiry, $msg) = @_;

	return unless ($type = os_logonnews_pre($user, $type));

	my $mlength = length($msg);
	if($mlength >= 350) {
		notice($user, 'Message is too long by '. $mlength-350 .' character(s). Maximum length is 350 chars');
		return;
	}

	if($expiry) {
		$expiry = parse_time($expiry);
	}
	else {
		$expiry = 0;
	}

	my $src = get_user_nick($user);
	$count_logonnews->execute($type);
	my $count = $count_logonnews->fetchrow_array;

	$add_logonnews->execute($src, $expiry ? time()+$expiry : 0, $type, ++$count, $msg);

	notice($user, "Added new $newstypes{$type} News #\002$count\002");
}

sub os_logonnews_del($$$) {
	my ($user, $type, $id) = @_;

	return unless ($type = os_logonnews_pre($user, $type));

	my $ret = $del_logonnews->execute($type, $id);

	if ($ret == 1) {
		notice($user, "News Item $newstypes{$type} News #\002$id\002 deleted");
		$consolidate_logonnews->execute($type, $id);
	}
	else {
		notice($user, "Delete of $newstypes{$type} News #\002$id\002 failed.",
			"$newstypes{$type} #\002$id\002 does not exist?");
	}
}

sub os_logonnews_list($$) {
	my ($user, $type) = @_;

	return unless ($type = os_logonnews_pre($user, $type));

	my @reply;
	push @reply, "\002$newstypes{$type}\002 News";

	$list_logonnews->execute($type);
	push @reply, "There is no $newstypes{$type} News"
		unless($list_logonnews->rows);
	while(my ($adder, $time, $expiry, $id, $msg) = $list_logonnews->fetchrow_array) {
		my ($weeks, $days, $hours, $minutes, $seconds) = split_time($expiry-time());
		my $expire_string = ($expiry?"Expires in ".($weeks?"$weeks weeks ":'').
			($days?"$days days ":'').
			($hours?"$hours hours ":'').
			($minutes?"$minutes minutes ":'')
			:'Does not expire');
		push @reply, "$id\) $msg";
		push @reply, join('  ', '', 'added: '.gmtime2($time), $expire_string, "added by: $adder");
	}
	$list_logonnews->finish();
	notice($user, @reply);
}

sub os_except_pre($) {
	my ($user) = @_;

	if (adminserv::is_svsop($user, adminserv::S_ADMIN()) ) {
		return 1;
	}
	else {
		notice($user, $err_deny);
		return 0;
	}
}

sub os_except_hostname_add($$$) {
	my ($user, $hostname, $limit) = @_;

	os_except_pre($user) or return 0;

	if ($hostname =~ m/\@/ or not $hostname =~ /\./) {
		notice($user, 'Invalid hostmask.', 'A clone exception hostmask is the HOST portion only, no ident',
			'and must contain at least one dot \'.\'');
		return;
	}

	$limit = MAX_LIM() unless $limit;

	my $src = get_user_nick($user);
	my $hostmask = $hostname;
	$hostmask =~ s/\*/\%/g;
	$add_clone_exceptname->execute($hostmask, $src, $limit);
	notice($user, "Clone exception for host \002$hostname\002 added.");
}

sub os_except_server_add($$$) {
	my ($user, $hostname, $limit) = @_;

	os_except_pre($user) or return 0;

	if ($hostname =~ m/\@/ or not $hostname =~ /\./) {
		notice($user, 'Invalid hostmask.', 'A clone exception servername has no ident',
			'and must contain at least one dot \'.\'');
		return;
	}

	$limit = MAX_LIM() unless $limit;

	my $src = get_user_nick($user);
	my $hostmask = $hostname;
	$hostmask =~ s/\*/\%/g;
	$add_clone_exceptserver->execute($hostmask, $src, $limit);
	notice($user, "Clone exception for server \002$hostname\002 added.");
}

sub os_except_IP_add($$$$) {
	my ($user, $IP, $limit) = @_;

	os_except_pre($user) or return 0;

	my $mask;
	($IP, $mask) = split(/\//, $IP);
	$mask = 32 unless $mask;
	if ($IP =~ m/\@/ or not $IP =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/) {
		notice($user, 'Invalid hostmask.', 'A clone exception IP has no ident',
			'and must be a valid IP address with 4 octets (example: 1.2.3.4)');
		return;
	}

	$limit = MAX_LIM() unless $limit;

	my $src = get_user_nick($user);
	$add_clone_exceptip->execute($IP, $mask, $src, $limit);
	notice($user, "IP clone exception \002$IP\/$mask\002 added.");
}

sub os_except_hostname_del($$) {
	my ($user, $hostname) = @_;

	os_except_pre($user) or return 0;
	
	my $hostmask = $hostname;
	$hostmask =~ s/\*/\%/g;
	my $ret = $del_clone_exceptname->execute($hostmask);
	ircd::notice($osnick, main_conf_diag, "hostname: $hostname; hostmask: $hostmask");
	
	if($ret == 1) {
		notice($user, "\002$hostname\002 successfully deleted from the hostname exception list");
	}
	else {
		notice($user, "Deletion of \002$hostname\002 \037failed\037. \002$hostname\002 entry does not exist?");
	}
}

sub os_except_server_del($$) {
	my ($user, $hostname) = @_;

	os_except_pre($user) or return 0;
	
	my $hostmask = $hostname;
	$hostmask =~ s/\*/\%/g;
	my $ret = $del_clone_exceptname->execute($hostmask);
	
	if($ret == 1) {
		notice($user, "\002$hostname\002 successfully deleted from the server exception list");
	}
	else {
		notice($user, "Deletion of \002$hostname\002 \037failed\037. \002$hostname\002 entry does not exist?");
	}
}

sub os_except_IP_del($$$) {
	my ($user, $IP) = @_;

	os_except_pre($user) or return 0;
	
	no warnings 'misc';
	my ($IP, $mask) = split(/\//, $IP);
	$mask = 32 unless $mask;
	my $ret = $del_clone_exceptip->execute($IP);
	
	if($ret == 1) {
		notice($user, "\002$IP/$mask\002 successfully deleted from the IP exception list");
	}
	else {
		notice($user, "Deletion of \002$IP/$mask\002 \037failed\037. \002$IP/$mask\002 entry does not exist?");
	}
}

sub os_except_list($) {
	my ($user) = @_;
	my @data;

	$list_clone_exceptserver->execute();
	while(my ($host, $adder, $lim) = $list_clone_exceptserver->fetchrow_array) {
		$host =~ s/\%/\*/g;
		push @data, ['Server:', $host, $lim!=MAX_LIM()?$lim:'unlimited', "($adder)"];
	}

	$list_clone_exceptname->execute();
	while(my ($host, $adder, $lim) = $list_clone_exceptname->fetchrow_array) {
		$host =~ s/\%/\*/g;
		push @data, ['Host:', $host, $lim!=MAX_LIM()?$lim:'unlimited', "($adder)"];
	}
	
	$list_clone_exceptip->execute();
	while(my ($ip, $mask, $adder, $lim) = $list_clone_exceptip->fetchrow_array) {
		push @data, ['IP:', "$ip/$mask", $lim!=MAX_LIM()?$lim:'unlimited', "($adder)"];
	}
	
	notice($user, columnar {TITLE => "Clone exception list:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data);
}

sub os_session_list($) {
	my ($user, $lim) = @_;

	unless($lim > 1) {
		notice($user, "Please specify a number greater than 1.");
		return;
	}

	$get_session_list->execute($lim);
	my $data = $get_session_list->fetchall_arrayref;

	notice($user, columnar {TITLE => "Hosts with at least $lim sessions:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @$data);
}

sub os_chankill($$$) {
	my ($user, $cn, $reason) = @_;

	unless(adminserv::is_svsop($user, adminserv::S_OPER())) {
		notice($user, $err_deny);
		return;
	}
	my $src = get_user_nick($user);

	chanserv::chan_kill({ CHAN => $cn }, "$reason ($src - ".gmtime2(time()).")");
}

sub os_rehash($;$) {
	my ($user, $type) = @_;

	unless (adminserv::is_svsop($user, adminserv::S_ROOT())) {
	    notice($user, $err_deny);
	    return $event::SUCCESS;
	}

	ircd::rehash_all_servers($type);
	return $event::SUCCESS;
}


sub os_svskill($$$) {
	my ($user, $targets, $reason) = @_;
	
	
	if(!adminserv::is_svsop($user, adminserv::S_ROOT())) {
		notice($user, $err_deny);
		return $event::SUCCESS;
	}

	foreach my $target (split(',', $targets)) {
		#my $tuser = { NICK => $target };
		if (!is_online({ NICK => $target })) {
			notice($user, $target.' is not online.');
			return $event::SUCCESS;
		}

		ircd::svskill($osnick, $target, $reason);
	}

	return $event::SUCCESS;
}

sub os_kill($$$) {
	my ($user, $targets, $reason) = @_;
	
	
	if(!adminserv::can_do($user, 'KILL')) {
		notice($user, $err_deny);
		return $event::SUCCESS;
	}

	foreach my $target (split(',', $targets)) {
		my $tuser = { NICK => $target, AGENT => $osnick };
		if (!get_user_id($tuser)) {
			notice($user, $target.' is not online.');
			return $event::SUCCESS;
		}

		nickserv::kill_user($tuser, "Killed by ".get_user_nick($user).($reason ? ': '.$reason : ''));
	}

}

sub os_gline($$$@) {
	my ($user, $zline, $target, @args) = @_;

	my $opernick;
	return unless ($opernick = adminserv::is_svsop($user, adminserv::S_OPER));

	my $expiry;
	$expiry = parse_time(shift @args) if $args[0] =~ /^\+/;
	my $reason = join(' ', @args);
	$reason =~ s/^\:// if $reason;
	my $remove;
	if($target =~ /^-/) {
		$remove = 1;
		$target =~ s/^-//;
	}

	my ($ident, $host);
	if($target =~ /\!/) {
		notice($user, "Invalid G:line target \002$target\002");
		return;
	}
	elsif($target =~ /^(\S+)\@(\S+)$/) {
		($ident, $host) = ($1, $2);
	} elsif($target =~ /\./) {
		($ident, $host) = ('*', $target);
	} elsif(valid_nick($target)) {
		my $tuser = { NICK => $target };
		unless(get_user_id($tuser)) {
			notice($user, "Unknown user \002$target\002");
			return;
		}
		unless($zline) {
			(undef, $host) = nickserv::get_host($tuser);
			$ident = '*';
		} else {
			$host = get_user_ip($tuser);
			if ($host =~ /:/) {
				$host = get_ipv6_64($host);
			}
		}
	} else {
		notice($user, "Invalid G:line target \002$target\002");
		return;
	}
	unless($zline) {
		if(!$remove) {
			ircd::kline($opernick, $ident, $host, $expiry, $reason);
		} else {
			ircd::unkline($opernick, $ident, $host);
		}

	} else {
		if($ident and $ident !~ /^\**$/) {
			notice($user, "You cannot specify an ident in a Z:line");
		}
		elsif ($host =~ /^(?:\d{1,3}\.){3}(?:\d{1,3})/) {
			# all is well, do nothing
		}
		elsif ($host =~ /^[0-9\/\*\?\.]+$/) {
			# This may allow invalid CIDR, not sure.
			# We're trusting our opers to not do stupid things.
			# THIS MAY BE A SOURCE OF BUGS.

			# all is well, do nothing
		} elsif($host =~ /:/) {
			#validating IPv6 addrs without using inet_pton and inet_ntop is a crapshoot
			# for now, we do nothing.
		} else {
			notice($user, "Z:lines can only be placed on IPs or IP ranges");
			return;
		}
		if(!$remove) {
			ircd::zline($opernick, $host, $expiry, $reason);
		} else {
			ircd::unzline($opernick, $host);
		}
	}

	return $event::SUCCESS;
}

sub os_loners($@) {
	my ($user, @args) = @_;
	my $cmd = shift @args;
	my $noid;
	if ($cmd =~ /(not?id|noidentify)/) {
		$noid = 1;
		$cmd = shift @args;
	}
	if (defined($args[0]) and $args[0] =~ /(not?id|noidentify)/) {
		$noid = 1;
		shift @args;
	}

	return __os_massmod($user, uc 'clones', $cmd, \&chanserv::get_users_nochans, $noid, @args);
}
sub os_clones($@) {
	my ($user, @args) = @_;
	my $cmd = shift @args;
	my $target = shift @args;

	return __os_massmod($user, 'Clones', $cmd, \&get_clones, $target, @args);
}

sub os_killnew($@) {
	my ($user, @args) = @_;
	my $cmd = shift @args;

	my ($noid, $time);
	if ($cmd =~ /(not?id|noidentify)/) {
		$noid = 1;
		$cmd = shift @args;
	}
	if (defined($args[0]) and $args[0] =~ /(not?id|noidentify)/) {
		$noid = 1;
		shift @args;
	}
	if(defined($args[0] and $args[0] =~ /^\+/)) {
		$time = parse_time(shift @args);
	}

	return __os_massmod($user, 'killnew', $cmd, \&get_newusers, [$noid, $time], @args);
}

sub __os_massmod($$$$@) {
	my ($user, $cmd0, $cmd1, $func, $arg, @args) = @_;
	my $msg = join(' ', @args);

	if($cmd1 =~ /^list$/i) {
		my @data;
		my $noun;
		foreach my $tuser (&$func($arg)) {
			push @data, [get_user_nick($tuser), (is_online($tuser) ? "\002Online\002" : "\002Offline\002")];
		}
		my $title;
		if($cmd0 eq 'Clones') {
			$title = "$cmd0 matching \002$arg\002";
		} elsif($cmd0 eq 'Loners') {
			$title = "$cmd0 ".($arg ? 'Not identified' : '');
		} elsif($cmd0 eq 'Loners') {
			$title = "New users ".($arg ? 'Not identified' : '');
		}
		notice($user, columnar {TITLE => $title,
			NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data);
	}
	elsif($cmd1 =~ /^uinfo$/i) {
		notice($user, get_uinfo($user, &$func($arg)));
	}
	elsif($cmd1 =~ /^kill$/i) {
		unless(adminserv::can_do($user, 'KILL')) {
			notice($user, $err_deny);
			return;
		}
		foreach my $tuser (&$func($arg)) {
			next unless is_online($tuser);
			$tuser->{AGENT} = $osnick;
			nickserv::kill_user($tuser,
				"Killed by \002".get_user_nick($user)."\002".
				($msg ? ": $msg" : '')
			);
		}
	}
	elsif($cmd1 =~ /^kline$/i) {
		unless(adminserv::is_svsop($user, adminserv::S_OPER())) {
			notice($user, $err_deny);
			return;
		}
		foreach my $tuser (&$func($arg)) {
			next unless is_online($tuser);
			$tuser->{AGENT} = $osnick;
			nickserv::kline_user($tuser, services_conf_chankilltime,
				"K:Lined by \002".get_user_nick($user)."\002".
				($msg ? ": $msg" : '')
			);
		}
	}
	elsif($cmd1 =~ /^(msg|message|notice)$/i) {
		notice($user, "Must have message to send") unless(@args);
		foreach my $tuser (&$func($arg)) {
			next unless is_online($tuser);
			$tuser->{AGENT} = $osnick;
			notice($tuser,
				"Automated message from \002".get_user_nick($user),
				$msg
			);
		}
	}
	elsif($cmd1 =~ /^fjoin$/i) {
		unless(adminserv::can_do($user, 'FJOIN')) {
			notice($user, $err_deny);
			return;
		}

		if ($args[0] !~ /^#/) {
			notice($user, "\002".$args[0]."\002 is not a valid channel name");
			return;
		}

		foreach my $tuser (&$func($arg)) {
			next unless is_online($tuser);
			my $cn = $msg; # not a message, most cases it is
			$tuser->{AGENT} = $osnick;
			ircd::svsjoin($osnick, get_user_nick($tuser), $cn);
		}
	}
	else {
		notice($user, "Unknown $cmd0 command: $cmd1",
			"Syntax: OS $cmd0 [LIST|UINFO|MSG|FJOIN|KILL|KLINE] [msg/reason]");
	}
}

### MISCELLANEA ###

sub do_news($$) {
	my ($nick, $type) = @_;

	my ($banner, @reply);

	if ($type eq 'u') {
		$banner = "\002Logon News\002";
	}
	elsif ($type eq 'o') {
		$banner = "\002Oper News\002";
	}
	$get_logonnews->execute($type);
	while(my ($adder, $time, $msg) = $get_logonnews->fetchrow_array) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
		$year += 1900;
		push @reply, "[$banner ".$months[$mon]." $mday $year] $msg";
	}
	$get_logonnews->finish();
	ircd::notice(main_conf_local, $nick, @reply) if scalar(@reply);
}

sub chk_auth($$) {
	my ($user, $perm) = @_;
	
	if(adminserv::can_do($user, $perm)) {
		return 1;
	}
	
	notice($user, $err_deny);
	return 0;
}

sub expire(;$) {
	add_timer('OperServ Expire', 60, __PACKAGE__, 'operserv::expire');

	$get_expired_qlines->execute();
	while (my ($mask) = $get_expired_qlines->fetchrow_array() ) {
		ircd::unsqline($mask);
		$del_qline->execute($mask);
	}
	$get_expired_qlines->finish();
	
	#don't run this code yet.
=cut
	$get_expired_akills->execute();
	while (my ($mask) = $get_expired_akills->fetchrow_array() ) {
		($ident, $host) = split('@', $mask);
		ircd::unkline($osnick, $ident, $host);
		$del_akill->execute($mask);
	}
	$get_expired_akills->finish();
=cut

	$del_expired_logonnews->execute();
}

sub get_uinfo($@) {
	my ($user, @userlist) = @_;
	my @reply;
	foreach my $tuser (@userlist) {
		my ($ident, $host, $vhost, $gecos, $server, $signontime, $quittime) = get_user_info($tuser);
		my $modes = nickserv::get_user_modes($tuser);
		my $target = get_user_nick($tuser);

		my ($curchans, $oldchans) = chanserv::get_user_chans_recent($tuser);
	
		my @data = (
			["Status:", (nickserv::is_online($tuser) ?
				"Online (".gmtime2($signontime).')' :
				"Offline (".gmtime2($quittime).')'
				)
			],
			["ID Nicks:", join(', ', nickserv::get_id_nicks($tuser))],
			["Channels:", join(', ', @$curchans)],
			["Recently Parted:", join(', ', @$oldchans)],
			["Flood level:", get_flood_level($tuser)],
			["Hostmask:", "$target\!$ident\@$vhost"],
			["GECOS:", $gecos],
			["Connecting from:", "$host"],
			["Current Server:", $server],
			["Modes:", $modes]
		);
		if(module::is_loaded('country')) {
			push @data, ["Country:", country::get_user_country_long($tuser)];
		} elsif(module::is_loaded('geoip')) {
			push @data, ["Location:", geoip::stringify_location(geoip::get_user_location($tuser))];
		}
			
		push @reply, columnar {TITLE => "User info for \002$target\002:",
			NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data;
	}
	return @reply;
}

sub get_clones($) {
	my ($targets) = @_;
	my @users;
	foreach my $target (split(',', $targets)) {
		my $sth; # statement handle. You'll see what I'll do with it next!
		if($target =~ /^(?:\d{1,3}\.){3}\d{1,3}$/) {
			$sth = $get_clones_fromipv4;
		} elsif($target =~ /\./) { # doesn't really work with localhost. oh well.
			$sth = $get_clones_fromhost;
		} else {
			$sth = $get_clones_fromnick;
		}

		$sth->execute($target);
		while(my ($nick, $id, $online) = $sth->fetchrow_array()) {
			push @users, { NICK => $nick, ID => $id, ONLINE => $online };
		}
		$sth->finish();
	}
	return @users;
}

sub get_newusers($) {
	my ($noid, $time) = @{$_[0]};
	ircd::debug("get_newusers: $time");
	my @users;
	my $sth; # statement handle. You'll see what I'll do with it next!
	if($noid) {
		$sth = $get_newusers_noid;
	} else {
		$sth = $get_newusers;
	}

	$sth->execute(CORE::time()-$time);
	while(my ($nick, $id, $online) = $sth->fetchrow_array()) {
		push @users, { NICK => $nick, ID => $id, ONLINE => $online };
	}
	$sth->finish();
	return @users;
}

## IRC EVENTS ##

1;
