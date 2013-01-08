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
package memoserv;

use strict;
#use constant {
#	READ => 1,
#	DEL => 2,
#	ACK => 4,
#	NOEXP => 8
#};

use SrSv::Agent qw(is_agent);

use SrSv::Time;
use SrSv::Text::Format qw(columnar);
use SrSv::Errors;

use SrSv::User qw(get_user_nick get_user_id get_user_agent :flood);
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::Conf2Consts qw( main );

use SrSv::NickReg::Flags;
use SrSv::NickReg::User qw(is_identified get_nick_user_nicks);

use SrSv::MySQL qw( $dbh :sql_types );

use SrSv::Util qw( makeSeqList seqifyList );

use constant (
	MAX_MEMO_LEN => 400
);

our $msnick_default = 'MemoServ1';
our $msnick = $msnick_default;
our $msuser = { NICK => $msnick, ID => ircd::getAgentUuid($msnick) };
our (
	$send_memo, $send_chan_memo, $get_chan_recipients,

	$get_memo_list,

	$get_memo, $get_memo_full, $get_memo_count, $get_unread_memo_count,

	$set_flag,

	$delete_memo, $purge_memos, $delete_all_memos,
	$memo_chgroot,

	$add_ignore, $get_ignore_num, $del_ignore_nick, $list_ignore, $chk_ignore,
	$wipe_ignore, $purge_ignore,
	$get_first_unread
);

sub init() {
	$msuser = { NICK => $msnick, ID => ircd::getAgentUuid($msnick) };
	$get_first_unread = $dbh->prepare("SELECT memo.src, memo.chan, memo.time, memo.flag, memo.msg FROM memo, nickreg WHERE nickreg.nick=? AND memo.dstid=nickreg.id AND memo.flag=0 LIMIT 1");
	$send_memo = $dbh->prepare("INSERT INTO memo SELECT ?, id, NULL, UNIX_TIMESTAMP(), NULL, ? FROM nickreg WHERE nick=?");
	$send_chan_memo = $dbh->prepare("INSERT INTO memo SELECT ?, nickreg.id, ?, ?, NULL, ? FROM chanacc, nickreg
		WHERE chanacc.chan=? AND chanacc.level >= ? AND chanacc.nrid=nickreg.id
		AND !(nickreg.flags & ". NRF_NOMEMO() . ")");
	$get_chan_recipients = $dbh->prepare("SELECT user.nick FROM user, nickid, nickreg, chanacc WHERE
		user.id=nickid.id AND nickid.nrid=chanacc.nrid AND chanacc.nrid=nickreg.id AND chanacc.chan=?
		AND level >= ? AND
		!(nickreg.flags & ". NRF_NOMEMO() . ")");

	$get_memo_list = $dbh->prepare("SELECT memo.src, memo.chan, memo.time, memo.flag, memo.msg FROM memo, nickreg WHERE nickreg.nick=? AND memo.dstid=nickreg.id ORDER BY memo.time ASC");

	$get_memo = $dbh->prepare("SELECT memo.src, memo.chan, memo.time 
		FROM memo JOIN nickreg ON (memo.dstid=nickreg.id) WHERE nickreg.nick=? ORDER BY memo.time ASC LIMIT 1 OFFSET ?");
	$get_memo->bind_param(2, 0, SQL_INTEGER);
	$get_memo_full = $dbh->prepare("SELECT memo.src, memo.chan, memo.time, memo.flag, memo.msg FROM memo, nickreg WHERE nickreg.nick=? AND memo.dstid=nickreg.id ORDER BY memo.time ASC LIMIT 1 OFFSET ?");
	$get_memo_full->bind_param(2, 0, SQL_INTEGER);
	$get_memo_count = $dbh->prepare("SELECT COUNT(*) FROM memo, nickreg WHERE nickreg.nick=? AND memo.dstid=nickreg.id");
	$get_unread_memo_count = $dbh->prepare("SELECT COUNT(*) FROM memo, nickreg WHERE nickreg.nick=? AND memo.dstid=nickreg.id AND memo.flag=0");

	$set_flag = $dbh->prepare("UPDATE memo, nickreg SET memo.flag=? WHERE memo.src=? AND nickreg.nick=? AND memo.dstid=nickreg.id AND memo.chan=? AND memo.time=?");

	$delete_memo = $dbh->prepare("DELETE FROM memo USING memo, nickreg WHERE memo.src=? AND nickreg.nick=? AND memo.dstid=nickreg.id AND memo.chan=? AND memo.time=?");
	$purge_memos = $dbh->prepare("DELETE FROM memo USING memo, nickreg WHERE nickreg.nick=? AND memo.dstid=nickreg.id AND memo.flag=1");
	$delete_all_memos = $dbh->prepare("DELETE FROM memo USING memo, nickreg WHERE nickreg.nick=? AND memo.dstid=nickreg.id");

	$add_ignore = $dbh->prepare("INSERT INTO ms_ignore (ms_ignore.nrid, ms_ignore.ignoreid, time)
		SELECT nickreg.id, ignorenick.id, UNIX_TIMESTAMP() FROM nickreg, nickreg AS ignorenick
		WHERE nickreg.nick=? AND ignorenick.nick=?");
	$del_ignore_nick = $dbh->prepare("DELETE FROM ms_ignore USING ms_ignore
		JOIN nickreg ON (ms_ignore.nrid=nickreg.id)
		JOIN nickreg AS ignorenick ON(ms_ignore.ignoreid=ignorenick.id)
		WHERE nickreg.nick=? AND ignorenick.nick=?");
	$get_ignore_num = $dbh->prepare("SELECT ignorenick.nick FROM ms_ignore
		JOIN nickreg ON (ms_ignore.nrid=nickreg.id)
		JOIN nickreg AS ignorenick ON(ms_ignore.ignoreid=ignorenick.id)
		WHERE nickreg.nick=?
		ORDER BY ms_ignore.time LIMIT 1 OFFSET ?");
	$get_ignore_num->bind_param(2, 0, SQL_INTEGER);

	$list_ignore = $dbh->prepare("SELECT ignorenick.nick, ms_ignore.time
		FROM ms_ignore, nickreg, nickreg AS ignorenick
		WHERE nickreg.nick=? AND ms_ignore.nrid=nickreg.id AND ms_ignore.ignoreid=ignorenick.id
		ORDER BY ms_ignore.time");
	$chk_ignore = $dbh->prepare("SELECT 1
		FROM ms_ignore, nickreg, nickreg AS ignorenick
		WHERE nickreg.nick=? AND ms_ignore.nrid=nickreg.id AND ignorenick.nick=? AND ms_ignore.ignoreid=ignorenick.id");

	$wipe_ignore = $dbh->prepare("DELETE FROM ms_ignore USING ms_ignore JOIN nickreg ON(ms_ignore.nrid=nickreg.id) WHERE nickreg.nick=?");
	$purge_ignore = $dbh->prepare("DELETE FROM ms_ignore USING ms_ignore JOIN nickreg ON(ms_ignore.ignoreid=nickreg.id) WHERE nickreg.nick=?");
}

### MEMOSERV COMMANDS ###

sub dispatch($$$) {
	$msuser = { NICK => $msnick, ID => ircd::getAgentUuid($msnick) };
	my ($user, $dstUser, $msg) = @_;
	$msg =~ s/^\s+//;
	my @args = split(/\s+/, $msg);
	my $cmd = shift @args;
	$user -> {AGENT} = $msuser;
	return unless (lc $dstUser->{NICK} eq lc $msnick);
	get_user_id ($user);
	return if flood_check($user);
	if($SrSv::IRCd::State::queue_depth > main_conf_highqueue && !adminserv::is_svsop($user)) {
		notice($user, get_user_agent($user)." is too busy right now. Please try your command again later.");
	}

	if($cmd =~ /^send$/i) {
		if(@args >= 2) {
			my @args = split(/\s+/, $msg, 3);
			ms_send($user, $args[1], $args[2], 0);
		} else {
			notice($user, 'Syntax: SEND <recipient> <message>');
		}
	}
	elsif($cmd =~ /^csend$/i) {
		if(@args >= 3 and $args[1] =~ /^(?:[uvhas]op|co?f(ounder)?|founder)$/i) {
			my @args = split(/\s+/, $msg, 4);
			my $level = chanserv::xop_byname($args[2]);
			ms_send($user, $args[1], $args[3], $level);
		} else {
			notice($user, 'Syntax: CSEND <recipient> <uop|vop|hop|aop|sop|cf|founder> <message>');
		}
	}
	elsif($cmd =~ /^read$/i) {
		if(@args == 1 and (lc($args[0]) eq 'last' or $args[0] > 0 or (lc($args[0]) eq 'unread'))) {
			ms_read($user, $args[0]);
		} else {
			notice($user, 'Syntax: READ <num|LAST|UNREAD>');
		}
	}
	elsif($cmd =~ /^list$/i) {
		ms_list($user);
	}
	elsif($cmd =~ /^del(ete)?$/i) {
		if(@args >= 1 and (lc($args[0]) eq 'all' or $args[0] > 0)) {
			ms_delete($user, $args[0]);
		} else {
			notice($user, 'Syntax: DELETE <num|num1-num2|ALL>');
		}
	}
	elsif($cmd =~ /^ign(ore)?$/i) {
		my $cmd2 = shift @args;
		if($cmd2 =~ /^a(dd)?$/i) {
			if(@args == 1) {
				ms_ignore_add($user, $args[0]);
			}
			else {
				notice($user, 'Syntax: IGNORE ADD <nick>');
			}
		}
		elsif($cmd2 =~ /^d(el)?$/i) {
			if(@args == 1) {
				ms_ignore_del($user, $args[0]);
			}
			else {
				notice($user, 'Syntax: IGNORE DEL [nick|num]');
			}
		}
		elsif($cmd2 =~ /^l(ist)?$/i) {
			ms_ignore_list($user);
		}
		else {
			notice($user, 'Syntax: IGNORE <ADD|DEL|LIST> [nick|num]');
		}
	}
	elsif($cmd =~ /^help$/i) {
		sendhelp($user, 'memoserv', @args);
	}
	else {
		notice($user, "Unrecognized command.  For help, type: \002/ms help\002");
	}
}

sub ms_send($$$$) {
	my ($user, $dst, $msg, $level) = @_;
	my $src = get_user_nick($user);

	my $root = auth($user) or return;
	
	if(length($msg) > MAX_MEMO_LEN()) {
		notice($user, 'Memo too long. Maximum memo length is '.MAX_MEMO_LEN().' characters.');
		return;
	}

	if($dst =~ /^#/) {
		my $chan = { CHAN => $dst };
		unless(chanserv::is_registered($chan)) {
			notice($user, "$dst is not registered");
			return;
		}
		
		my $srcnick = chanserv::can_do($chan, 'MEMO', $user) or return;

		send_chan_memo($srcnick, $chan, $msg, $level);
	} else {
		nickserv::chk_registered($user, $dst) or return;
		
		if (nr_chk_flag($dst, NRF_NOMEMO(), +1)) {
			notice($user, "\002$dst\002 is not accepting memos.");
			return;
		}
		$chk_ignore->execute(nickserv::get_root_nick($dst), $root);
		if ($chk_ignore->fetchrow_array) {
			notice($user, "\002$dst\002 is not accepting memos.");
			return;
		}
			
		send_memo($src, $dst, $msg);
	}

	notice($user, "Your memo has been sent.");
}

sub ms_read($$) {
	my ($user, $num) = @_;
	my ($from, $chan, $time, $flag, $msg);
	my $src = get_user_nick($user);

	my $root = auth($user) or return;

	my @nums;
	if(lc($num) eq 'last') {
		$get_memo_count->execute($root);
		($num) = $get_memo_count->fetchrow_array;
		if (!$num) {
			notice($user, "Memo \002$num\002 not found.");
			return;
		}
		@nums = ($num);
	}
	elsif (lc($num) eq 'unread') {
		$get_first_unread->execute($root);
		$get_memo_full->execute($root, $num-1);
		unless(($from, $chan, $time, $flag, $msg) = $get_first_unread->fetchrow_array) {
			notice($user, "You have no unread memos.");
			return;
		}
		$set_flag->execute(1, $from, $root, $chan, $time);
		my @reply;
		push @reply, "Memo \002$num\002 from \002$from\002 ".
			($chan ? "to \002$chan\002 " : "to \002$root\002 ").
			"at ".gmtime2($time), $msg, ' --';
		notice ($user, @reply);
		return;
	}
	else {
		@nums = makeSeqList($num);
	}

	my $count = 0;
	my @reply;
	while (my $num = shift @nums) {
		if (++$count > 5) {
			push @reply, "You can only read 5 memos at a time.";
			last;
		}
		$get_memo_full->execute($root, $num-1);
		unless(($from, $chan, $time, $flag, $msg) = $get_memo_full->fetchrow_array) {
			push @reply, "Memo \002$num\002 not found.";
			next;
		}
		$set_flag->execute(1, $from, $root, $chan, $time);
		push @reply, "Memo \002$num\002 from \002$from\002 ".
			($chan ? "to \002$chan\002 " : "to \002$root\002 ").
			"at ".gmtime2($time), ' ', '  '.$msg, ' --';
	}
	notice($user, @reply);
}

sub ms_list($) {
	my ($user) = @_;
	my ($i, @data, $mnlen, $mclen);
	my $src = get_user_nick($user);

	my $root = auth($user) or return;

	$get_memo_list->execute($root);
	while(my ($from, $chan, $time, $flag, $msg) = $get_memo_list->fetchrow_array) {
		$i++;
		
		push @data, [
			($flag ? '' : "\002") . $i,
			$from, $chan, gmtime2($time),
			(length($msg) > 20 ? substr($msg, 0, 17) . '...' : $msg)
		];
	}

	unless(@data) {
		notice($user, "You have no memos.");
		return;
	}

	notice($user, columnar( { TITLE => "Memo list for \002$root\002.  To read, type \002/ms read <num>\002",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT) }, @data));
}

sub ms_delete($@) {
	my ($user, @args) = @_;
	my $src = get_user_nick($user);

	my $root = auth($user) or return;

	if(scalar(@args) == 1 and lc($args[0]) eq 'all') {
		$delete_all_memos->execute($root);
		notice($user, 'All of your memos have been deleted.');
		return;
	}
	my (@deleted, @notDeleted);
	foreach my $num (reverse makeSeqList(@args)) {
		if(int($num) ne $num) { # can this happen, given makeSeqList?
			notice($user, "\002$num\002 is not an integer number");
			next;
		}
		my ($from, $chan, $time);
		$get_memo->execute($root, $num-1);
		if(my ($from, $chan, $time) = $get_memo->fetchrow_array) {
			$delete_memo->execute($from, $root, $chan, $time);
			push @deleted, $num;
		} else {
			push @notDeleted, $num;
		}
	}
	if(scalar(@deleted)) {
		my $plural = (scalar(@deleted) == 1);
		my $msg = sprintf("Memo%s deleted: ".join(', ', seqifyList @deleted), ($plural ? '' : 's'));
		notice($user, $msg);
	}
	if(scalar(@notDeleted)) {
		my $msg = sprintf("Memos not found: ".join(', ', seqifyList @notDeleted));
		notice($user, $msg);
	}
}

sub ms_ignore_add($$) {
	my ($user, $nick) = @_;
	my $src = get_user_nick($user);

	unless(is_identified($user, $src) or adminserv::can_do($user, 'SERVOP')) {
		notice($user, $err_deny);
		return;
	}

	my $nickroot = nickserv::get_root_nick($nick);
	unless ($nickroot) {
		notice($user, "$nick is not registered");
		return;
	}

	my $srcroot = nickserv::get_root_nick($src);

	$add_ignore->execute($srcroot, $nickroot);

	notice($user, "\002$nick\002 (\002$nickroot\002) added to \002$src\002 (\002$srcroot\002) memo ignore list.");
}

sub ms_ignore_del($$) {
	my ($user, $entry) = @_;
	my $src = get_user_nick($user);
	
	unless(is_identified($user, $src) or adminserv::can_do($user, 'SERVOP')) {
		notice($user, $err_deny);
		return;
	}
	my $srcroot = nickserv::get_root_nick($src);

	my $ignorenick;
	if (misc::isint($entry)) {
		$get_ignore_num->execute($srcroot, $entry - 1);
		($ignorenick) = $get_ignore_num->fetchrow_array();
		$get_ignore_num->finish();
	}
	my $ret = $del_ignore_nick->execute($srcroot, ($ignorenick ? $ignorenick : $entry));
	if($ret == 1) {
		notice($user, "Delete succeeded for ($srcroot): $entry");
	}
	else {
		notice($user, "Delete failed for ($srcroot): $entry. entry does not exist?");
	}
}

sub ms_ignore_list($) {
	my ($user) = @_;
	my $src = get_user_nick($user);
	
	unless(is_identified($user, $src) or adminserv::can_do($user, 'SERVOP')) {
		notice($user, $err_deny);
		return;
	}
	my $srcroot = nickserv::get_root_nick($src);

	my @data;
	$list_ignore->execute($srcroot);
	while (my ($nick, $time) = $list_ignore->fetchrow_array) {
		push @data, [$nick, '('.gmtime2($time).')'];
	}

	notice($user, columnar({TITLE => "Memo ignore list for \002$src\002:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data));
}

sub notify($;$) {
	my ($user, $root) = @_;
	my (@nicks);

	unless(ref($user) eq "HASH") {
		$user = { NICK => $user };
	}

	if($root) { @nicks = ($root) }
	else { @nicks = nickserv::get_id_nicks($user) }

	my $hasmemos;
	foreach my $n (@nicks) {
		$get_unread_memo_count->execute($n);
		my ($c) = $get_unread_memo_count->fetchrow_array;
		next unless $c;
		notice($user, "You have \002$c\002 unread memo(s). " . (@nicks > 1 ? "(\002$n\002) " : ''));
		$hasmemos = 1;
	}

	notice($user, "To view them, type: \002/ms list\002") if $hasmemos;
}

### DATABASE UTILITY FUNCTIONS ###

sub send_memo($$$) {
	my ($src, $dst, $msg) = @_;

	# This construct is intended to allow agents to send memos.
	# Unfortunately this is raceable against %nickserv::enforcers.
	# I don't want to change the %nickserv::enforcers decl tho, s/my/our/
	$src = (is_agent($src) ? $src : nickserv::get_root_nick($src));
	$dst = nickserv::get_root_nick($dst);

	$send_memo->execute($src, $msg, $dst);
	notice_all_nicks($dst, "You have a new memo from \002$src\002.  To read it, type: \002/ms read last\002");
}

sub send_chan_memo($$$$) {
	my ($src, $chan, $msg, $level) = @_;
	my $cn = $chan->{CHAN};
	$src = (is_agent($src) ? $src : nickserv::get_root_nick($src));

	$send_chan_memo->execute($src, $cn, time(), $msg, $cn, $level);
	# "INSERT INTO memo SELECT ?, nick, ?, ?, 0, ? FROM chanacc WHERE chan=? AND level >= ?"
	
	$get_chan_recipients->execute($cn, $level);
	while(my ($u) = $get_chan_recipients->fetchrow_array) {
		notice({ NICK => $u, AGENT => $msuser }, 
			"You have a new memo from \002$src\002 to \002$cn\002.  To read it, type: \002/ms read last\002");
	}
}

sub notice_all_nicks($$) {
	my ($nick, $msg) = @_;

	foreach my $u (get_nick_user_nicks $nick) {
		notice({ NICK => $u, AGENT => $msuser }, $msg);
	}
}

sub auth($) {
	my ($user) = @_;
	my $src = get_user_nick($user);
	
	my $root = nickserv::get_root_nick($src);
        unless($root) {
                notice($user, "Your nick is not registered.");
                return 0;
        }

        unless(is_identified($user, $root)) {
                notice($user, $err_deny);
                return 0;
        }

	return $root;
}

### IRC EVENTS ###

1;
