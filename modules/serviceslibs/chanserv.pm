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
package chanserv;

use strict;

use SrSv::Timer qw(add_timer);
use Data::Dumper;
use SrSv::Message qw(current_message);
use SrSv::IRCd::State qw($ircline synced initial_synced %IRCd_capabilities);
use SrSv::Message qw(message current_message);
use SrSv::HostMask qw(normalize_hostmask make_hostmask parse_mask);
#FIXME: This needs to be abstracted into a proper SrSv::IRCd module
use SrSv::Unreal::Modes qw(@opmodes %opmodes $scm $ocm $acm sanitize_mlockable);
use SrSv::IRCd::Validate qw( valid_nick validate_chmodes validate_ban );
use SrSv::Agent;

use SrSv::Shared qw(%enforcers $chanuser_table);

#use SrSv::Conf qw(services);
use SrSv::Conf2Consts qw( services sql main );

use SrSv::Time;
use SrSv::Text::Format qw( columnar enum );
use SrSv::Errors;

use SrSv::Log;

use SrSv::User qw(
	get_user_nick get_user_agent get_user_id
	is_online :user_flags get_host get_vhost
	:flags :flood
	);
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::ChanReg::Flags;

use SrSv::NickReg::Flags;
use SrSv::NickReg::NickText;
use SrSv::NickReg::User qw(is_identified get_nick_users get_nick_user_nicks);

use SrSv::MySQL qw( $dbh :sql_types );
use SrSv::MySQL::Glob;

use SrSv::Util qw( makeSeqList );

use constant {
	UOP => 1,
	VOP => 2,
	HOP => 3,
	AOP => 4,
	SOP => 5,
	COFOUNDER => 6,
	FOUNDER => 7,

	# Maybe this should be a config option
	DEFAULT_BANTYPE => 10,

	CRT_TOPIC => 1,
	CRT_AKICK => 2,
};

*get_root_nick = \&nickserv::get_root_nick;

our @levels = ("no", "UOp", "VOp", "HOp", "AOp", "SOp", "co-founder", "founder");
our @ops;
if(!ircd::PREFIXAQ_DISABLE()) {
	@ops = (0, 0, 1, 2, 4, 8, 16, 16);  # PREFIX_AQ
} else { # lame IRC scripts and admins who don't enable PREFIX_AQ
	@ops = (0, 0, 1, 2, 4, 12, 20, 20);  # normal
}
our @plevels = ('AKICK', 'anyone', 'UOp', 'VOp', 'HOp', 'AOp', 'SOp', 'co-founder', 'founder', 'disabled');
our $plzero = 1;

our @override = (
	['SERVOP',
		{
			ACCCHANGE => 1,
			SET => 1,
			MEMO => 1,
			SETTOPIC => 1,
			AKICK => 1,
			LEVELS => 1,
			COPY => 1,
			WELCOME => 1,
		}
	],
	['SUPER',
		{
			BAN => 1,
			UNBANSELF => 1,
			UNBAN => 1,
			KICK => 1,
			VOICE => 1,
			HALFOP => 1,
			OP => 1,
			ADMIN => 1,
			OWNER => 1,
			SETTOPIC => 1,
			INVITE => 1,
			INVITESELF => 1,
			CLEAR => 1,
			AKICKENFORCE => 1,
			UPDOWN => 1,
			MODE => 1,
		}
	],
	['HELP',
		{
			JOIN => 1,
			ACCLIST => 1,
			LEVELSLIST => 1,
			AKICKLIST => 1,
			INFO => 1,
			GETKEY => 1
		}
	],
	['BOT',
		{
			BOTSAY => 1,
			BOTASSIGN => 1
		}
	]
);

$chanuser_table = 0;

our $csnick_default = 'ChanServ';
our $csnick = $csnick_default;

our ($cur_lock, $cnt_lock);

our (
	$get_joinpart_lock, $get_modelock_lock, $get_update_modes_lock,
	
	$chanjoin, $chanpart, $chanpart2, $chop, $chdeop, $get_op, $get_user_chans, $get_user_chans_recent,
	$get_all_closed_chans, $get_user_count,

	$is_in_chan,
	
	#$lock_chanuser, $get_all_chan_users,
	$unlock_tables,
	$get_chan_users, $get_chan_users_noacc, $get_chan_users_mask, $get_chan_users_mask_noacc,

	$get_users_nochans, $get_users_nochans_noid,

	$get_using_nick_chans,

	$get_lock, $release_lock, $is_free_lock,

	$chan_create, $chan_delete, $get_chanmodes, $set_chanmodes,

	$is_registered, $get_modelock, $set_modelock, $set_descrip,

	$get_topic, $set_topic1, $set_topic2,

	$get_acc, $set_acc1, $set_acc2, $del_acc, $get_acc_list, $get_acc_list2, $get_acc_list_mask, $get_acc_list2_mask,
	$wipe_acc_list,
	$get_best_acc, $get_all_acc, $get_highrank, $get_acc_count,
	$copy_acc, $copy_acc_rank,

	$get_eos_lock, $get_status_all, $get_status_all_server, $get_modelock_all,

	$get_akick, $get_akick_allchan, $get_akick_alluser, $get_akick_all, $add_akick, $del_akick,
	$get_akick_list, $get_akick_by_num,

	$add_nick_akick, $del_nick_akick, $get_nick_akick, $drop_nick_akick,
	$copy_akick,
	
	$is_level, $get_level, $get_levels, $add_level, $set_level, $reset_level, $clear_levels, $get_level_max,
	$copy_levels,

	$get_founder, $get_successor,
	$set_founder, $set_successor, $del_successor,

	$get_nick_own_chans, $delete_successors,

	$get_info,

	$register, $drop_acc, $drop_lvl, $drop_akick, $drop,
	$copy_chanreg,

	$get_expired,

	$get_close, $set_close, $del_close,

	$add_welcome, $del_welcome, $list_welcome, $get_welcomes, $drop_welcome,
	$count_welcome, $consolidate_welcome,

	$add_ban, $delete_bans, $delete_ban,
	$get_all_bans, $get_ban_num,
	$find_bans, $list_bans, $wipe_bans,
	$find_bans_chan_user, $delete_bans_chan_user,

	$add_auth, $list_auth_chan, $get_auth_nick, $get_auth_num, $find_auth,

	$set_bantype, $get_bantype,

	$drop_chantext, $drop_nicktext,
	$get_host,
	$get_host_inchan,
	$get_expired_bans,
);

sub init() {
	#$chan_create = $dbh->prepare("INSERT IGNORE INTO chan SET id=(RAND()*294967293)+1, chan=?");
	$get_joinpart_lock = $dbh->prepare("LOCK TABLES chan WRITE, chanuser WRITE");
	$get_modelock_lock = $dbh->prepare("LOCK TABLES chanreg READ LOCAL, chan WRITE");
	$get_update_modes_lock = $dbh->prepare("LOCK TABLES chan WRITE");
	
	$chanjoin = $dbh->prepare("REPLACE INTO chanuser (seq,nickid,chan,op,joined) VALUES (?, ?, ?, ?, 1)");
	$chanpart = $dbh->prepare("UPDATE chanuser SET joined=0, seq=?
		WHERE nickid=? AND chan=? AND (seq <= ? OR seq > ?)");
	$chanpart2 = $dbh->prepare("UPDATE chanuser SET joined=0 WHERE nickid=? AND chan=?");
	#$chop = $dbh->prepare("UPDATE chanuser SET op=op+? WHERE nickid=? AND chan=?");
	$chop = $dbh->prepare("UPDATE chanuser SET op=IF(op & ?, op, op ^ ?) WHERE nickid=? AND chan=?");
	$chdeop = $dbh->prepare("UPDATE chanuser SET op=IF(op & ?, op ^ ?, op) WHERE nickid=? AND chan=?");
	$get_op = $dbh->prepare("SELECT op FROM chanuser WHERE nickid=? AND chan=?");
	$get_user_chans = $dbh->prepare("SELECT chan, op FROM chanuser WHERE nickid=? AND joined=1 AND (seq <= ? OR seq > ?)");
	$get_user_chans_recent = $dbh->prepare("SELECT chan, joined, op FROM chanuser WHERE nickid=?");

	$get_all_closed_chans = $dbh->prepare("SELECT chanclose.chan, chanclose.type, chanclose.reason, chanclose.nick, chanclose.time FROM chanreg, chanuser, chanclose WHERE chanreg.chan=chanuser.chan AND chanreg.chan=chanclose.chan AND chanreg.flags & ? GROUP BY chanclose.chan ORDER BY NULL");
	$get_user_count = $dbh->prepare("SELECT COUNT(*) FROM chanuser WHERE chan=? AND joined=1");

	$is_in_chan = $dbh->prepare("SELECT 1 FROM chanuser WHERE nickid=? AND chan=? AND joined=1");

	#$lock_chanuser = $dbh->prepare("LOCK TABLES chanuser READ, user READ");
	#$get_all_chan_users = $dbh->prepare("SELECT user.nick, chanuser.nickid, chanuser.chan FROM chanuser, user WHERE user.id=chanuser.nickid AND chanuser.joined=1");
	$unlock_tables = $dbh->prepare("UNLOCK TABLES");

	$get_chan_users = $dbh->prepare("SELECT user.nick, user.id FROM chanuser, user
		WHERE chanuser.chan=? AND user.id=chanuser.nickid AND chanuser.joined=1");
	my $chan_users_noacc_tables = 'user '.
		'JOIN chanuser ON (chanuser.nickid=user.id AND chanuser.joined=1 AND user.online=1) '.
		'LEFT JOIN nickid ON (chanuser.nickid=nickid.id) '.
		'LEFT JOIN chanacc ON (nickid.nrid=chanacc.nrid AND chanuser.chan=chanacc.chan)';
	$get_chan_users_noacc = $dbh->prepare("SELECT user.nick, user.id FROM $chan_users_noacc_tables
		WHERE chanuser.chan=?
		GROUP BY user.id HAVING MAX(IF(chanacc.level IS NULL, 0, chanacc.level)) <= 0
		ORDER BY NULL");
	my $check_mask = "((user.nick LIKE ?) AND (user.ident LIKE ?)
		AND ((user.vhost LIKE ?) OR (user.host LIKE ?) OR (user.cloakhost LIKE ?)))";
	$get_chan_users_mask = $dbh->prepare("SELECT user.nick, user.id FROM chanuser, user
		WHERE chanuser.chan=? AND user.id=chanuser.nickid AND chanuser.joined=1 AND $check_mask");
	$get_chan_users_mask_noacc = $dbh->prepare("SELECT user.nick, user.id FROM $chan_users_noacc_tables
		WHERE chanuser.chan=? AND $check_mask
		GROUP BY user.id HAVING MAX(IF(chanacc.level IS NULL, 0, chanacc.level)) <= 0
		ORDER BY NULL");

	$get_users_nochans = $dbh->prepare("SELECT user.nick, user.id 
		FROM user LEFT JOIN chanuser ON (chanuser.nickid=user.id AND chanuser.joined=1)
		WHERE chanuser.chan IS NULL AND user.online=1");
	$get_users_nochans_noid = $dbh->prepare("SELECT user.nick, user.id
		FROM user LEFT JOIN chanuser ON (chanuser.nickid=user.id AND chanuser.joined=1)
		LEFT JOIN nickid ON (nickid.id=user.id)
		WHERE chanuser.chan IS NULL AND nickid.id IS NULL
		AND user.online=1");

	$get_using_nick_chans = $dbh->prepare("SELECT user.nick FROM user, nickid, nickreg, chanuser
		WHERE user.id=nickid.id AND user.id=chanuser.nickid AND nickid.nrid=nickreg.id AND chanuser.joined=1
		AND nickreg.nick=? AND chanuser.chan=?");

	$get_lock = $dbh->prepare("SELECT GET_LOCK(?, 3)");
	$release_lock = $dbh->prepare("DO RELEASE_LOCK(?)");
	$is_free_lock = $dbh->prepare("SELECT IS_FREE_LOCK(?)");

	$chan_create = $dbh->prepare("INSERT IGNORE INTO chan SET seq=?, chan=?");
	$chan_delete = $dbh->prepare("DELETE FROM chan WHERE chan=?");
	$get_chanmodes = $dbh->prepare("SELECT modes FROM chan WHERE chan=?");
	$set_chanmodes = $dbh->prepare("REPLACE INTO chan SET modes=?, chan=?");

	$is_registered = $dbh->prepare("SELECT 1 FROM chanreg WHERE chan=?");
	$get_modelock = $dbh->prepare("SELECT modelock FROM chanreg WHERE chan=?");
	$set_modelock = $dbh->prepare("UPDATE chanreg SET modelock=? WHERE chan=?");

	$set_descrip = $dbh->prepare("UPDATE chanreg SET descrip=? WHERE chan=?");

	$get_topic = $dbh->prepare("SELECT chantext.data, topicer, topicd FROM chanreg, chantext
		WHERE chanreg.chan=chantext.chan AND chantext.chan=?");
	$set_topic1 = $dbh->prepare("UPDATE chanreg SET chanreg.topicer=?, chanreg.topicd=?
		WHERE chanreg.chan=?");
	$set_topic2 = $dbh->prepare("REPLACE INTO chantext SET chan=?, type=".CRT_TOPIC().", data=?");

	$get_acc = $dbh->prepare("SELECT chanacc.level FROM chanacc, nickalias
		WHERE chanacc.chan=? AND chanacc.nrid=nickalias.nrid AND nickalias.alias=?");
	$set_acc1 = $dbh->prepare("INSERT IGNORE INTO chanacc SELECT ?, nrid, ?, NULL, UNIX_TIMESTAMP(), 0
		FROM nickalias WHERE alias=?");
	$set_acc2 = $dbh->prepare("UPDATE chanacc, nickalias
		SET chanacc.level=?, chanacc.adder=?, chanacc.time=UNIX_TIMESTAMP()
		WHERE chanacc.chan=? AND chanacc.nrid=nickalias.nrid AND nickalias.alias=?");
	$del_acc = $dbh->prepare("DELETE FROM chanacc USING chanacc, nickalias
		WHERE chanacc.chan=? AND chanacc.nrid=nickalias.nrid AND nickalias.alias=?");
	$wipe_acc_list = $dbh->prepare("DELETE FROM chanacc WHERE chan=? AND level=?");
	$get_acc_list = $dbh->prepare("SELECT nickreg.nick, chanacc.adder, chanacc.time,
		chanacc.last, nickreg.ident, nickreg.vhost
		FROM chanacc, nickreg
		WHERE chanacc.chan=? AND chanacc.level=? AND chanacc.nrid=nickreg.id AND chanacc.level > 0 ORDER BY nickreg.nick");
	$get_acc_list2 = $dbh->prepare("SELECT nickreg.nick, chanacc.adder, chanacc.level, chanacc.time,
		chanacc.last, nickreg.ident, nickreg.vhost
		FROM chanacc, nickreg
		WHERE chanacc.chan=? AND chanacc.nrid=nickreg.id AND chanacc.level > 0 ORDER BY nickreg.nick");
	$get_acc_list_mask = $dbh->prepare("SELECT IF (nickreg.nick LIKE ?, nickreg.nick, nickalias.alias), chanacc.adder, chanacc.time,
		chanacc.last, nickreg.ident, nickreg.vhost, COUNT(nickreg.id) as c
		FROM chanacc, nickalias, nickreg
		WHERE chanacc.chan=? AND chanacc.level=? AND chanacc.nrid=nickalias.nrid AND nickreg.id=nickalias.nrid
		AND chanacc.level > 0
		AND nickalias.alias LIKE ? AND nickreg.ident LIKE ? AND nickreg.vhost LIKE ?
		GROUP BY nickreg.id
		ORDER BY nickalias.alias");
	$get_acc_list2_mask = $dbh->prepare("SELECT IF (nickreg.nick LIKE ?, nickreg.nick, nickalias.alias),
		chanacc.adder, chanacc.level, chanacc.time,
		chanacc.last, nickreg.ident, nickreg.vhost, COUNT(nickreg.id) as c
		FROM chanacc, nickalias, nickreg
		WHERE chanacc.chan=? AND chanacc.nrid=nickalias.nrid AND nickreg.id=nickalias.nrid
		AND chanacc.level > 0
		AND nickalias.alias LIKE ? AND nickreg.ident LIKE ? AND nickreg.vhost LIKE ?
		GROUP BY nickreg.id
		ORDER BY nickalias.alias");

	$get_best_acc = $dbh->prepare("SELECT nickreg.nick, chanacc.level
		FROM nickid, nickalias, nickreg, chanacc 
		WHERE nickid.nrid=nickreg.id AND nickalias.nrid=nickreg.id AND nickid.id=?
		AND chanacc.nrid=nickreg.id AND chanacc.chan=? ORDER BY chanacc.level DESC LIMIT 1");
	$get_all_acc = $dbh->prepare("SELECT nickreg.nick, chanacc.level
		FROM nickid, nickreg, chanacc
		WHERE nickid.nrid=nickreg.id AND nickid.id=? AND chanacc.nrid=nickreg.id
		AND chanacc.chan=? ORDER BY chanacc.level");
	$get_highrank = $dbh->prepare("SELECT user.nick, chanacc.level FROM chanuser, nickid, chanacc, user WHERE chanuser.chan=? AND chanuser.joined=1 AND chanuser.chan=chanacc.chan AND chanuser.nickid=nickid.id AND user.id=nickid.id AND nickid.nrid=chanacc.nrid ORDER BY chanacc.level DESC LIMIT 1");
	$get_acc_count = $dbh->prepare("SELECT COUNT(*) FROM chanacc WHERE chan=? AND level=?");
	$copy_acc = $dbh->prepare("REPLACE INTO chanacc
		(   chan, nrid, level, adder, time)
 		SELECT ?, nrid, level, adder, time FROM chanacc JOIN nickreg ON (chanacc.nrid=nickreg.id)
		WHERE chan=? AND nickreg.nick!=? AND chanacc.level!=7");
	$copy_acc_rank = $dbh->prepare("REPLACE INTO chanacc
		(   chan, nrid, level, adder, time)
 		SELECT ?, nrid, level, adder, time FROM chanacc
		WHERE chan=? AND chanacc.level=?");

	$get_eos_lock = $dbh->prepare("LOCK TABLES akick READ LOCAL, welcome READ LOCAL, chanuser WRITE, user WRITE,
		user AS u1 READ, user AS u2 READ, chan WRITE, chanreg WRITE, nickid READ LOCAL, nickreg READ LOCAL,
		nickalias READ LOCAL, chanacc READ LOCAL, chanban WRITE, svsop READ");
	my $get_status_all_1 = "SELECT chanuser.chan, chanreg.flags, chanreg.bot, user.nick, user.id, user.flags, MAX(chanacc.level), chanuser.op, MAX(nickreg.flags & ".NRF_NEVEROP().")
		FROM user, chanreg, chanuser
		LEFT JOIN nickid ON(nickid.id=chanuser.nickid)
		LEFT JOIN nickreg ON(nickid.nrid=nickreg.id)
		LEFT JOIN chanacc ON(chanacc.chan=chanuser.chan AND chanacc.nrid=nickid.nrid AND (nickreg.flags & ".NRF_NEVEROP().")=0)
		WHERE";
	my $get_status_all_2 = "(user.flags & ".UF_FINISHED().")=0 AND chanuser.joined=1 AND (chanreg.flags & ".(CRF_CLOSE|CRF_DRONE).") = 0 AND chanreg.chan=chanuser.chan AND user.id=chanuser.nickid AND (nickid.nrid IS NULL OR nickreg.id IS NOT NULL)
		GROUP BY chanuser.chan, chanuser.nickid ORDER BY NULL";
	$get_status_all = $dbh->prepare("$get_status_all_1 $get_status_all_2");
	$get_status_all_server = $dbh->prepare("$get_status_all_1 user.server=? AND $get_status_all_2");

	$get_modelock_all = $dbh->prepare("SELECT chanuser.chan, chan.modes, chanreg.modelock FROM chanreg, chan, chanuser WHERE chanuser.joined=1 AND chanreg.chan=chan.chan AND chanreg.chan=chanuser.chan GROUP BY chanreg.chan ORDER BY NULL");

	my $akick_rows = "user.nick, akick.nick, akick.ident, akick.host, akick.reason";
	my $akick_no_zerolen = "(akick.ident != '' AND akick.host != '')";
	my $akick_single_cond = "$akick_no_zerolen AND user.nick LIKE akick.nick AND user.ident LIKE akick.ident ".
		"AND ( (user.host LIKE akick.host) OR (user.vhost LIKE akick.host) OR ".
		"(IF((user.ip IS NOT NULL) AND (user.ip != 0), INET_NTOA(user.ip) LIKE akick.host, 0)) OR ".
		"(IF(user.cloakhost IS NOT NULL, user.cloakhost LIKE akick.host, 0)) )";
	my $akick_multi_cond = "chanuser.chan=akick.chan AND $akick_single_cond";

	$get_akick = $dbh->prepare("SELECT $akick_rows FROM akick, user ".
		"WHERE user.id=? AND akick.chan=? AND $akick_single_cond LIMIT 1");
	$get_akick_allchan = $dbh->prepare("SELECT $akick_rows FROM $chan_users_noacc_tables
		JOIN akick ON($akick_multi_cond)
		WHERE akick.chan=?
		GROUP BY user.id HAVING MAX(IF(chanacc.level IS NULL, 0, chanacc.level)) <= 0
		ORDER BY NULL");
	$get_akick_alluser = $dbh->prepare("SELECT akick.chan, $akick_rows FROM $chan_users_noacc_tables
		JOIN akick ON($akick_multi_cond)
		WHERE chanuser.nickid=?
		GROUP BY user.id HAVING MAX(IF(chanacc.level IS NULL, 0, chanacc.level)) <= 0
		ORDER BY NULL");
	$get_akick_all = $dbh->prepare("SELECT akick.chan, $akick_rows FROM $chan_users_noacc_tables
		JOIN akick ON($akick_multi_cond)
		GROUP BY akick.chan, user.id HAVING MAX(IF(chanacc.level IS NULL, 0, chanacc.level)) <= 0
		ORDER BY NULL");
	
	$add_akick = $dbh->prepare("INSERT INTO akick SET chan=?, nick=?, ident=?, host=?, adder=?, reason=?, time=UNIX_TIMESTAMP()");
	$add_akick->{PrintError} = 0;
	$del_akick = $dbh->prepare("DELETE FROM akick WHERE chan=? AND nick=? AND ident=? AND host=?");
	$get_akick_list = $dbh->prepare("SELECT nick, ident, host, adder, reason, time FROM akick WHERE chan=? ORDER BY time");

	$add_nick_akick = $dbh->prepare("INSERT INTO akick SELECT ?, nickalias.nrid, '', '', ?, ?, UNIX_TIMESTAMP()
		FROM nickalias WHERE alias=?");
	$del_nick_akick = $dbh->prepare("DELETE FROM akick USING akick, nickalias
		WHERE akick.chan=? AND akick.nick=nickalias.nrid AND akick.ident='' AND akick.host='' AND nickalias.alias=?");
	$get_nick_akick = $dbh->prepare("SELECT reason FROM akick, nickalias
		WHERE akick.chan=? AND akick.nick=nickalias.nrid AND akick.ident='' AND akick.host='' AND nickalias.alias=?");
	$drop_nick_akick = $dbh->prepare("DELETE FROM akick USING akick, nickreg
		WHERE akick.nick=nickreg.id AND akick.ident='' AND akick.host='' AND nickreg.nick=?");
	$copy_akick = $dbh->prepare("REPLACE INTO akick
		(   chan, nick, ident, host, adder, reason, time)
		SELECT ?, nick, ident, host, adder, reason, time FROM akick WHERE chan=?");
	$get_akick_by_num = $dbh->prepare("SELECT akick.nick, akick.ident, akick.host FROM akick WHERE chan=?
		ORDER BY time LIMIT 1 OFFSET ?");
	$get_akick_by_num->bind_param(2, 0, SQL_INTEGER);

	$is_level = $dbh->prepare("SELECT 1 FROM chanperm WHERE chanperm.name=?");
	$get_level = $dbh->prepare("SELECT IF(chanlvl.level IS NULL, chanperm.level, chanlvl.level), chanlvl.level
		FROM chanperm LEFT JOIN chanlvl ON chanlvl.perm=chanperm.id AND chanlvl.chan=?
		WHERE chanperm.name=?");
	$get_levels = $dbh->prepare("SELECT chanperm.name, chanperm.level, chanlvl.level FROM chanperm LEFT JOIN chanlvl ON chanlvl.perm=chanperm.id AND chanlvl.chan=? ORDER BY chanperm.name");
	$add_level = $dbh->prepare("INSERT IGNORE INTO chanlvl SELECT ?, chanperm.id, chanperm.level FROM chanperm WHERE chanperm.name=?");
	$set_level = $dbh->prepare("UPDATE chanlvl, chanperm SET chanlvl.level=? WHERE chanlvl.chan=? AND chanperm.id=chanlvl.perm AND chanperm.name=?");
	$reset_level = $dbh->prepare("DELETE FROM chanlvl USING chanlvl, chanperm WHERE chanperm.name=? AND chanlvl.perm=chanperm.id AND chanlvl.chan=?");
	$clear_levels = $dbh->prepare("DELETE FROM chanlvl WHERE chan=?");
	$get_level_max = $dbh->prepare("SELECT max FROM chanperm WHERE name=?");
	$copy_levels = $dbh->prepare("REPLACE INTO chanlvl
		(   chan, perm, level)
		SELECT ?, perm, level FROM chanlvl WHERE chan=?");

	$get_founder = $dbh->prepare("SELECT nickreg.nick FROM chanreg, nickreg WHERE chanreg.chan=? AND chanreg.founderid=nickreg.id");
	$get_successor = $dbh->prepare("SELECT nickreg.nick FROM chanreg, nickreg WHERE chanreg.chan=? AND chanreg.successorid=nickreg.id");
	$set_founder = $dbh->prepare("UPDATE chanreg, nickreg SET chanreg.founderid=nickreg.id WHERE nickreg.nick=? AND chanreg.chan=?");
	$set_successor = $dbh->prepare("UPDATE chanreg, nickreg SET chanreg.successorid=nickreg.id WHERE nickreg.nick=? AND chanreg.chan=?");
	$del_successor = $dbh->prepare("UPDATE chanreg SET chanreg.successorid=NULL WHERE chanreg.chan=?");

	$get_nick_own_chans = $dbh->prepare("SELECT chanreg.chan FROM chanreg, nickreg WHERE nickreg.nick=? AND chanreg.founderid=nickreg.id");
	$delete_successors = $dbh->prepare("UPDATE chanreg, nickreg SET chanreg.successorid=NULL WHERE nickreg.nick=? AND chanreg.successorid=nickreg.id");


	$get_info = $dbh->prepare("SELECT chanreg.descrip, chanreg.regd, chanreg.last, chantext.data, 
		chanreg.topicer, chanreg.modelock, foundernick.nick, successornick.nick, chanreg.bot, chanreg.bantype, chanreg.bantime
		FROM nickreg AS foundernick, chanreg
		LEFT JOIN nickreg AS successornick ON(successornick.id=chanreg.successorid)
		LEFT JOIN chantext ON (chanreg.chan=chantext.chan AND chantext.type=".CRT_TOPIC().")
		WHERE chanreg.chan=? AND foundernick.id=chanreg.founderid");

	$register = $dbh->prepare("INSERT INTO chanreg
		SELECT ?, ?, UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), NULL, NULL,
		NULL, id, NULL, NULL, NULL, ".DEFAULT_BANTYPE().",0 FROM nickreg WHERE nick=?");
	$register->{PrintError} = 0;
	$copy_chanreg = $dbh->prepare("INSERT INTO chanreg
		(      chan, descrip, regd,             last,             modelock, founderid, successorid, bot, flags, bantype,bantime)
		SELECT ?,    descrip, UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), modelock, founderid, successorid, bot, flags, bantype,bantime
		FROM chanreg WHERE chan=?");
	$drop_acc = $dbh->prepare("DELETE FROM chanacc WHERE chan=?");
	$drop_lvl = $dbh->prepare("DELETE FROM chanlvl WHERE chan=?");
	$drop_akick = $dbh->prepare("DELETE FROM akick WHERE chan=?");
	$drop = $dbh->prepare("DELETE FROM chanreg WHERE chan=?");

	$get_expired = $dbh->prepare("SELECT chanreg.chan, nickreg.nick FROM nickreg, chanreg
	    LEFT JOIN chanuser ON(chanreg.chan=chanuser.chan AND chanuser.op!=0)
	    WHERE chanreg.founderid=nickreg.id AND chanuser.chan IS NULL AND chanreg.last<? AND
	    !(chanreg.flags & " . CRF_HOLD . ")");

	$get_close = $dbh->prepare("SELECT reason, nick, time FROM chanclose WHERE chan=?");
	$set_close = $dbh->prepare("REPLACE INTO chanclose SET chan=?, reason=?, nick=?, time=UNIX_TIMESTAMP(), type=?");
	$del_close = $dbh->prepare("DELETE FROM chanclose WHERE chan=?");

	$add_welcome = $dbh->prepare("REPLACE INTO welcome SET chan=?, id=?, adder=?, time=UNIX_TIMESTAMP(), msg=?");
	$del_welcome = $dbh->prepare("DELETE FROM welcome WHERE chan=? AND id=?");
	$list_welcome = $dbh->prepare("SELECT id, time, adder, msg FROM welcome WHERE chan=? ORDER BY id");
	$get_welcomes = $dbh->prepare("SELECT msg FROM welcome WHERE chan=? ORDER BY id");
	$drop_welcome = $dbh->prepare("DELETE FROM welcome WHERE chan=?");
	$count_welcome = $dbh->prepare("SELECT COUNT(*) FROM welcome WHERE chan=?");
	$consolidate_welcome = $dbh->prepare("UPDATE welcome SET id=id-1 WHERE chan=? AND id>?");
	$add_ban = $dbh->prepare("INSERT IGNORE INTO chanban SET chan=?, mask=?, setter=?, type=?, time=UNIX_TIMESTAMP()");
	$delete_bans = $dbh->prepare("DELETE FROM chanban WHERE chan=? AND ? LIKE mask AND type=?");
	# likely need a better name for this or for the above.
	$delete_ban = $dbh->prepare("DELETE FROM chanban WHERE chan=? AND mask=? AND type=?");
	$find_bans = $dbh->prepare("SELECT mask FROM chanban WHERE chan=? AND ? LIKE mask AND type=?");
	$get_all_bans = $dbh->prepare("SELECT mask FROM chanban WHERE chan=? AND type=?");
	$get_ban_num = $dbh->prepare("SELECT mask FROM chanban WHERE chan=? AND type=? ORDER BY time, mask LIMIT 1 OFFSET ?");
	$get_ban_num->bind_param(3, 0, SQL_INTEGER);
	$list_bans = $dbh->prepare("SELECT mask, setter, time FROM chanban WHERE chan=? AND type=? ORDER BY time, mask");
	$wipe_bans = $dbh->prepare("DELETE FROM chanban WHERE chan=?");

	my $chanban_mask = "((CONCAT(user.nick, '!', user.ident, '\@', user.host) LIKE chanban.mask) ".
			"OR (CONCAT(user.nick , '!' , user.ident , '\@' , user.vhost) LIKE chanban.mask) ".
			"OR IF(user.cloakhost IS NOT NULL, ".
				"(CONCAT(user.nick , '!' , user.ident , '\@' , user.cloakhost) LIKE chanban.mask), 0))";
	$find_bans_chan_user = $dbh->prepare("SELECT mask FROM chanban,user
		WHERE chan=? AND user.id=? AND type=? AND $chanban_mask");
	$delete_bans_chan_user = $dbh->prepare("DELETE FROM chanban USING chanban,user
		WHERE chan=? AND user.id=? AND type=? AND $chanban_mask");

	$add_auth = $dbh->prepare("REPLACE INTO nicktext
		SELECT nickalias.nrid, (".NTF_AUTH()."), 1, ?, ? FROM nickalias WHERE nickalias.alias=?");
	$list_auth_chan = $dbh->prepare("SELECT nickreg.nick, nicktext.data FROM nickreg, nicktext
		WHERE nickreg.id=nicktext.nrid AND nicktext.type=(".NTF_AUTH().") AND nicktext.chan=?");
	$get_auth_nick = $dbh->prepare("SELECT nicktext.data FROM nickreg, nickalias, nicktext
		WHERE nickreg.id=nicktext.nrid AND nickreg.id=nickalias.nrid AND nicktext.type=(".NTF_AUTH().")
		AND nicktext.chan=? AND nickalias.alias=?");
	$get_auth_num = $dbh->prepare("SELECT nickreg.nick, nicktext.data FROM nickreg, nickalias, nicktext
		WHERE nickreg.id=nicktext.nrid AND nickreg.id=nickalias.nrid AND nicktext.type=(".NTF_AUTH().")
		AND nicktext.chan=? LIMIT 1 OFFSET ?");
	$get_auth_num->bind_param(2, 0, SQL_INTEGER);
	$find_auth = $dbh->prepare("SELECT 1 FROM nickalias, nicktext
		WHERE nickalias.nrid=nicktext.nrid AND nicktext.type=(".NTF_AUTH().")
		AND nicktext.chan=? AND nickalias.alias=?");

	$set_bantype = $dbh->prepare("UPDATE chanreg SET bantype=? WHERE chan=?");
	$get_bantype = $dbh->prepare("SELECT bantype FROM chanreg WHERE chan=?");

	$drop_chantext = $dbh->prepare("DELETE FROM chantext WHERE chan=?");
	$drop_nicktext = $dbh->prepare("DELETE nicktext.* FROM nicktext WHERE nicktext.chan=?");
	$get_host = $dbh->prepare ("SELECT user.host from user where user.nick=?");
	$get_host_inchan = $dbh->prepare ("SELECT clonedUsers.nick FROM user AS curUser
		JOIN user AS clonedUsers ON (curUser.host=clonedUsers.host)
		JOIN chanuser ON (chanuser.nickid=clonedUsers.id)
		WHERE clonedUsers.id!=curUser.id AND curUser.id=? AND chanuser.chan=? AND chanuser.joined=1");
	$get_expired_bans = $dbh->prepare("SELECT channel, banmask, expiry, timeset FROM tmpban
		WHERE expiry < UNIX_TIMESTAMP()");

}

use SrSv::MySQL::Stub {
	set_lastop => ['NULL', "UPDATE chanreg SET last=UNIX_TIMESTAMP() WHERE chan=?"],
	set_lastused => ['NULL', "UPDATE chanacc, nickid SET chanacc.last=UNIX_TIMESTAMP() WHERE 
		chanacc.chan=? AND nickid.id=? AND chanacc.nrid=nickid.nrid AND chanacc.level > 0"],
	get_recent_private_chans => ['COLUMN', "SELECT DISTINCT chanuser.chan FROM chanuser
		JOIN chanacc ON (chanuser.chan=chanacc.chan AND chanuser.joined=0)
		JOIN chanlvl ON (chanlvl.level <= chanacc.level AND chanlvl.level > 0 AND chanuser.chan=chanlvl.chan)
		JOIN chanperm ON (chanlvl.perm=chanperm.id)
		JOIN nickid ON (chanuser.nickid=nickid.id AND chanacc.nrid=nickid.nrid)
		WHERE chanperm.name='Join'
		AND nickid.id=?"],
	add_tempban => ['INSERT', "INSERT INTO tmpban values (?,?,UNIX_TIMESTAMP()+?,UNIX_TIMESTAMP())"],
	del_tempban  => ['NULL', "DELETE FROM tmpban WHERE channel=? AND banmask = ?"],
	__get_bantime => ['SCALAR', "SELECT bantime FROM chanreg WHERE chan=?"],
	set_bantime => ['NULL', "UPDATE chanreg SET bantime=? WHERE chan=?"],
};


sub get_bantime($) {
	my ($chan) = @_;
	my $cn;
	if(ref $chan) {
		if(exists $chan->{BANTIME}) {
			return $chan->{BANTIME};
		}
		$cn = $chan->{CHAN};
	} else {
		$cn = $chan;
	}
	my $bantime = __get_bantime($cn);
	if(ref $chan) {
		$chan->{BANTIME} = $bantime;
	}
	return $bantime;
}

### CHANSERV COMMANDS ###

our %high_priority_cmds = (
	kick => 1,
	mode => 1,
	kb => 1,
	kickban => 1,
	kickb => 1,
	kban => 1,
	down => 1,
);
sub check_expired_bans() {
	add_timer('ChanServ Expire', 10, __PACKAGE__, 'chanserv::check_expired_bans');
	$get_expired_bans->execute();

	while (my ($cn, $ban) = $get_expired_bans->fetchrow_array()) {
		my $chan = { CHAN => $cn };
		ircd::setmode(agent($chan), $cn, '-b', $ban);
	}
	ircd::flushmodes();
}
sub tempban($@) {
	my ($chan, @bans) = @_;

	my $cn = $chan->{CHAN};
	return unless scalar(@bans);

	foreach my $ban (@bans) {
		my ($mask, $expiry);
		if(ref($ban)) {
			($mask, $expiry) = @$ban;
		} else {
			$mask = $ban;
		}
		if($expiry) {
			add_tempban($cn, $mask, $expiry);
		}
	}

	ircd::ban_list(agent($chan), $cn, +1, 'b', map { ref($_) ? $_->[0] : $_ } @bans);
}
sub clones_exist ($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	unless(cr_chk_flag($chan, CRF_NOCLONES)) {
		return;
	}

	my $nick = $user->{NICK};
	$get_host_inchan->execute(get_user_id($user), $cn);
	my ($joined) = $get_host_inchan->fetchrow_array;
	$get_host_inchan->finish();

	if ($joined) {
		return $joined;
	}

	return 0;
}
sub dispatch($$$) {
	my ($src, $dst, $msg) = @_;

	$msg =~ s/^\s+//;
	my @args = split(/\s+/, $msg);
	my $cmd = shift @args;

	my $user = { NICK => $src, AGENT => $dst };

	return if flood_check($user);

	if(!defined($high_priority_cmds{lc $cmd}) &&
		!adminserv::is_svsop($user) &&
		$SrSv::IRCd::State::queue_depth > main_conf_queue_highwater) 
	{
		notice($user, get_user_agent($user)." is too busy right now. Please try your command again later.");
		return;
	}

	if($cmd =~ /^register$/i) {
		if(@args >= 1) {
			my @args = split(/\s+/, $msg, 4);
			cs_register($user, { CHAN => $args[1] }, $args[2], $args[3]);
		} else {
			notice($user, 'Syntax: REGISTER <#channel> [password] [description]');
		}
	}
	elsif ($cmd =~ /^t((e)?mp)?b(an)?$/i) {
		my @args = split (/\s+/, $msg, 2);

		cs_tempban ($user, $args[1]);
	}
	elsif($cmd =~ /^(?:[uvhas]op|co?f(ounder)?)$/i) {
		my ($cn, $cmd2) = splice(@args, 0, 2);
		my $chan = { CHAN => $cn };

		if($cmd2 =~ /^add$/i) {
			if(@args == 1) {
				cs_xop_add($user, $chan, $cmd, $args[0]);
			} else {
				notice($user, 'Syntax: '.uc $cmd.' <#channel> ADD <nick>');
			}
		}
		elsif($cmd2 =~ /^del(ete)?$/i) {
			if(@args == 1) {
				cs_xop_del($user, $chan, $cmd, $args[0]);
			} else {
				notice($user, 'Syntax: '.uc $cmd.' <#channel> DEL <nick>');
			}
		}
		elsif($cmd2 =~ /^list$/i) {
			if(@args >= 0) {
				cs_xop_list($user, $chan, $cmd, $args[0]);
			} else {
				notice($user, 'Syntax: '.uc $cmd.' <#channel> LIST [mask]');
			}
		}
		elsif($cmd2 =~ /^(wipe|clear)$/i) {
			if(@args == 0) {
				cs_xop_wipe($user, $chan, $cmd);
			} else {
				notice($user, 'Syntax: '.uc $cmd.' <#channel> WIPE');
			}
		}
		else {
			notice($user, 'Syntax: '.uc $cmd.' <#channel> <ADD|DEL|LIST|WIPE>');
		}
	}
	elsif($cmd =~ /^levels$/i) {
		if(@args < 2) {
			notice($user, 'Syntax: LEVELS <#channel> <SET|RESET|LIST|CLEAR>');
			return;
		}

		my $cmd2 = lc(splice(@args, 1, 1));

		if($cmd2 eq 'set') {
			if(@args == 3) {
				cs_levels_set($user, { CHAN => $args[0] }, $args[1], $args[2]);
			} else {
				notice($user, 'Syntax: LEVELS <#channel> SET <permission> <level>');
			}
		}
		elsif($cmd2 eq 'reset') {
			if(@args == 2) {
				cs_levels_set($user, { CHAN => $args[0] }, $args[1]);
			} else {
				notice($user, 'Syntax: LEVELS <#channel> RESET <permission>');
			}
		}
		elsif($cmd2 eq 'list') {
			if(@args == 1) {
				cs_levels_list($user, { CHAN => $args[0] });
			} else {
				notice($user, 'Syntax: LEVELS <#channel> LIST');
			}
		}
		elsif($cmd2 eq 'clear') {
			if(@args == 1) {
				cs_levels_clear($user, { CHAN => $args[0] });
			} else {
				notice($user, 'Syntax: LEVELS <#channel> CLEAR');
			}
		}
		else {
			notice($user, 'Syntax: LEVELS <#channel> <SET|RESET|LIST|CLEAR>');
		}
	}
	elsif($cmd =~ /^akick$/i) {
		if(@args < 2) {
			notice($user, 'Syntax: AKICK <#channel> <ADD|DEL|LIST|WIPE|CLEAR>');
			return;
		}
		
		#my $cmd2 = lc($args[1]);
		my $cmd2 = lc(splice(@args, 1, 1));

		if($cmd2 eq 'add') {
			if(@args >= 2) {
				my @args = split(/\s+/, $msg, 5);
				cs_akick_add($user, { CHAN => $args[1] }, $args[3], $args[4]);
			} else {
				notice($user, 'Syntax: AKICK <#channel> ADD <nick|mask> <reason>');
			}
		}
		elsif($cmd2 eq 'del') {
			if(@args >= 2) {
				cs_akick_del($user, { CHAN => $args[0] }, $args[1]);
			} else {
				notice($user, 'Syntax: AKICK <#channel> DEL <nick|mask|num|seq>');
			}
		}
		elsif($cmd2 eq 'list') {
			if(@args == 1) {
				cs_akick_list($user, { CHAN => $args[0] });
			} else {
				notice($user, 'Syntax: AKICK <#channel> LIST');
			}
		}
		elsif($cmd2 =~ /^(wipe|clear)$/i) {
			if(@args == 1) {
				cs_akick_wipe($user, { CHAN => $args[0] });
			} else {
				notice($user, 'Syntax: AKICK <#channel> WIPE');
			}
		}
		elsif($cmd2 =~ /^enforce$/i) {
			if(@args == 1) {
				cs_akick_enforce($user, { CHAN => $args[0] });
			} else {
				notice($user, 'Syntax: AKICK <#channel> ENFORCE');
			}
		}
		else {
			notice($user, 'Syntax: AKICK <#channel> <ADD|DEL|LIST|WIPE|CLEAR>');
		}
	}
	elsif($cmd =~ /^info$/i) {
		if(@args == 1) {
			cs_info($user, { CHAN => $args[0] });
		} else {
			notice($user, 'Syntax: INFO <channel>');
		}
	}
	elsif($cmd =~ /^set$/i) {
		if(@args == 2 and lc($args[1]) eq 'unsuccessor') {
			cs_set($user, { CHAN => $args[0] }, $args[1]);
		}
		elsif(@args >= 3 and (
			$args[1] =~ /m(?:ode)?lock/i or
			lc($args[1]) eq 'desc'
		)) {
			my @args = split(/\s+/, $msg, 4);
			cs_set($user, { CHAN => $args[1] }, $args[2], $args[3]);
		}
		elsif(@args == 3) {
			cs_set($user, { CHAN => $args[0] }, $args[1], $args[2]);
		}
		else {
			notice($user, 'Syntax: SET <channel> <option> <value>');
		}
	}
	elsif($cmd =~ /^why$/i) {
		if(@args == 1) {
			cs_why($user, { CHAN => shift @args }, $src);
		}
		elsif(@args >= 2) {
			cs_why($user, { CHAN => shift @args }, @args);
		} else {
			notice($user, 'Syntax: WHY <channel> <nick> [nick [nick ...]]');
			return;
		}
	}
	elsif($cmd =~ /^(de)?(voice|h(alf)?op|op|protect|admin|owner)$/i) {
		if(@args >= 1) {
			cs_setmodes($user, $cmd, { CHAN => shift(@args) }, @args);
		} else {
			notice($user, 'Syntax: '.uc($cmd).' <channel> [nick [nick ...]]');
		}
	}
	elsif($cmd =~ /^(up|down)$/i) {
		cs_updown($user, $cmd, @args);
	}
	elsif($cmd =~ /^drop$/i) {
		if(@args == 1) {
			cs_drop($user, { CHAN => $args[0] });
		} else {
			notice($user, 'Syntax: DROP <channel>');
		}
	}
	elsif($cmd =~ /^help$/i) {
		sendhelp($user, 'chanserv', @args)
	}
	elsif($cmd =~ /^count$/i) {
		if(@args == 1) {
			cs_count($user, { CHAN => $args[0] });
		} else {
			notice($user, 'Syntax: COUNT <channel>');
		}
	}
	elsif($cmd =~ /^k(?:ick)?$/i) {
		my @args = split(/\s+/, $msg, 4); shift @args;
		if(@args >= 2) {
			cs_kick($user, { CHAN => $args[0] }, $args[1], 0, $args[2])
		}
		else {
			notice($user, 'Syntax: KICK <channel> <nick> [reason]');
		}
	}
	elsif($cmd =~ /^(k(ick)?b(an)?|b(an)?k(ick)?)$/i) {
		my @args = split(/\s+/, $msg, 4); shift @args;
		if(@args >= 2) {
			cs_kick($user, { CHAN => $args[0] }, $args[1], 1, $args[2]);
		} else {
			notice($user, 'Syntax: KICKBAN <channel> <nick> [reason]');
		}
	}
	elsif($cmd =~ /^k(ick)?m(ask)?$/i) {
		my @args = split(/\s+/, $msg, 4); shift @args;
		if(@args >= 2) {
			cs_kickmask($user, { CHAN => $args[0] }, $args[1], 0, $args[2])
		}
		else {
			notice($user, 'Syntax: KICKMASK <channel> <mask> [reason]');
		}
	}
	elsif($cmd =~ /^(k(ick)?b(an)?|b(an)?k(ick)?)m(ask)?$/i) {
		my @args = split(/\s+/, $msg, 4); shift @args;
		if(@args >= 2) {
			cs_kickmask($user, { CHAN => $args[0] }, $args[1], 1, $args[2]);
		} else {
			notice($user, 'Syntax: KICKBANMASK <channel> <mask> [reason]');
		}
	}
	elsif($cmd =~ /^invite$/i) {
		my $chan = shift @args;
		if(@args == 0) {
			cs_invite($user, { CHAN => $chan }, $src)
		}
		elsif(@args >= 1) {
			cs_invite($user, { CHAN => $chan }, @args)
		}
		else {
			notice($user, 'Syntax: INVITE <channel> <nick>');
		}
	}
	elsif($cmd =~ /^(close|forbid)$/i) {
		if(@args > 1) {
			my @args = split(/\s+/, $msg, 3);
			cs_close($user, { CHAN => $args[1] }, $args[2], CRF_CLOSE);
		}
		else {
			notice($user, 'Syntax: CLOSE <chan> <reason>');
		}
	}
	elsif($cmd =~ /^drone$/i) {
		if(@args > 1) {
			my @args = split(/\s+/, $msg, 3);
			cs_close($user, { CHAN => $args[1] }, $args[2], CRF_DRONE);
		}
		else {
			notice($user, 'Syntax: DRONE <chan> <reason>');
		}
	}
	elsif($cmd =~ /^clear$/i) {
		my ($cmd, $chan, $clearcmd, $reason) = split(/\s+/, $msg, 4);
		unless ($chan and $clearcmd) {
			notice($user, 'Syntax: CLEAR <channel> <MODES|OPS|USERS|BANS> [reason]');
			return;
		}
		if($clearcmd =~ /^modes$/i) {
			cs_clear_modes($user, { CHAN => $chan }, $reason);
		}
		elsif($clearcmd =~ /^ops$/i) {
			cs_clear_ops($user, { CHAN => $chan }, $reason);
		}
		elsif($clearcmd =~ /^users$/i) {
			cs_clear_users($user, { CHAN => $chan }, $reason);
		}
		elsif($clearcmd =~ /^bans?$/i) {
			cs_clear_bans($user, { CHAN => $chan }, 0, $reason);
		}
		elsif($clearcmd =~ /^excepts?$/i) {
			cs_clear_bans($user, { CHAN => $chan }, 128, $reason);
		}
		else {
			notice($user, "Unknown CLEAR command \002$clearcmd\002", 
				'Syntax: CLEAR <channel> <MODES|OPS|USERS|BANS> [reason]');
		}
	}
	elsif($cmd =~ /^mkick$/i) {
		my ($cmd, $chan, $reason) = split(/\s+/, $msg, 3);
		if($chan) {
			cs_clear_users($user, { CHAN => $chan }, $reason);
		}
		else {
			notice($user, 'Syntax: MKICK <chan> [reason]');
		}
	}
	elsif($cmd =~ /^mdeop$/i) {
		my ($cmd, $chan, $reason) = split(/\s+/, $msg, 3);
		if($chan) {
			cs_clear_ops($user, { CHAN => $chan }, $reason);
		}
		else {
			notice($user, 'Syntax: MDEOP <chan> [reason]');
		}
	}
	elsif($cmd =~ /^welcome$/i) {
		my $wcmd = splice(@args, 1, 1);
		if(lc($wcmd) eq 'add') {
			my ($chan, $wmsg) = (splice(@args, 0, 1), join(' ', @args));
			unless ($chan and $wmsg) {
				notice($user, 'Syntax: WELCOME <channel> ADD <message>');
				return;
			}
			cs_welcome_add($user, { CHAN => $chan }, $wmsg);
		}
		elsif(lc($wcmd) eq 'del') {
			if (@args != 2 or !misc::isint($args[1])) {
				notice($user, 'Syntax: WELCOME <channnel> DEL <number>');
				return;
			}
			cs_welcome_del($user, { CHAN => $args[0] }, $args[1]);
		}
		elsif(lc($wcmd) eq 'list') {
			if (@args != 1) {
				notice($user, 'Syntax: WELCOME <channel> LIST');
				return;
			}
			cs_welcome_list($user, { CHAN => $args[0] });
		}
		else {
			notice($user, 'Syntax: WELCOME <channel> <ADD|DEL|LIST>');
		}
	}
	elsif($cmd =~ /^alist$/i) {
		if(@args >= 1) {
			cs_alist($user, { CHAN => shift @args }, shift @args);
		} else {
			notice($user, 'Syntax: ALIST <channel> [mask]');
		}
	}
	elsif($cmd =~ /^unban$/i) {
		if(@args == 1) {
			cs_unban($user, { CHAN => shift @args }, $src);
		}
		elsif(@args >= 2) {
			cs_unban($user, { CHAN => shift @args }, @args);
		} else {
			notice($user, 'Syntax: UNBAN <channel> [nick]');
		}
	}
	elsif($cmd =~ /^getkey$/i) {
		if(@args == 1) {
			cs_getkey($user, { CHAN => $args[0] });
		} else {
			notice($user, 'Syntax: GETKEY <channel>');
		}
	}
	elsif($cmd =~ /^auth$/i) {
		if (@args == 0) {
			notice($user, 'Syntax: AUTH <channel> <LIST|DELETE> [param]');
		} else {
			cs_auth($user, { CHAN => shift @args }, shift @args, @args);
		}
	}
	elsif($cmd =~ /^dice$/i) {
		notice($user, botserv::get_dice($args[0]));
	}
	elsif($cmd =~ /^(q|n)?ban$/i) {
		my $type = $1;
		my $chan = shift @args;
		if(@args >= 1) {
			cs_ban($user, { CHAN => $chan }, $type, @args)
		}
		else {
			notice($user, 'Syntax: BAN <channel> <nick|mask>');
		}
	}
	elsif($cmd =~ /^banlist$/i) {
		my $chan = shift @args;
		if(@args == 0) {
			cs_banlist($user, { CHAN => $chan });
		}
		else {
			notice($user, 'Syntax: BANLIST <channel>');
		}
	}
	elsif($cmd =~ /^assign$/i) {
		my $chan = shift @args;
		notice($user, "$csnick ASSIGN is deprecated. Please use $botserv::bsnick ASSIGN");
		if(@args == 2) {
			botserv::bs_assign($user, { CHAN => shift @args }, shift @args);
		}
		else {
			notice($user, 'Syntax: ASSIGN <#channel> <bot>');
		}
	}
	elsif($cmd =~ /^mode$/i) {
		my $chan = shift @args;
		if(@args >= 1) {
			cs_mode($user, { CHAN => $chan }, @args)
		}
		else {
			notice($user, 'Syntax: MODE <channel> <modes> [parms]');
		}
	}
	elsif($cmd =~ /^copy$/i) {
		my $chan = shift @args;
		if(@args >= 1) {
			cs_copy($user, { CHAN => $chan }, @args)
		}
		else {
			notice($user, 'Syntax: COPY #chan1 [type] #chan2');
		}
	}
	elsif($cmd =~ /^m(?:ode)?lock$/i) {
		my $chan = shift @args;
		if(@args >= 1) {
			cs_mlock($user, { CHAN => $chan }, @args)
		}
		else {
			notice($user, 'Syntax: MLOCK <channel> <ADD|DEL|SET|RESET> <modes> [parms]');
		}
	}
	elsif($cmd =~ /^resync$/i) {
		if (@args == 0) {
			notice($user, 'Syntax: RESYNC <chan1> [chan2 [chan3 [..]]]');
		} else {
			cs_resync($user, @args);
		}
	}
	elsif($cmd =~ /^JOIN$/i) {
		if (@args == 0) {
			notice($user, 'Syntax: JOIN <chan1> [chan2 [chan3 [..]]]');
		} else {
			cs_join($user, @args);
		}
	}
	elsif($cmd =~ /^topic$/i) {
		my $chan = shift @args;
		if (@args == 0) {
			notice($user, 'Syntax: TOPIC <#channel> <message|NONE>');
		} else {
			$msg =~ s/^topic #(?:\S+)? //i;
			cs_topic($user, { CHAN => $chan }, $msg);
		}
	}
	elsif($cmd =~ /^topicappend$/i) {
		my $chan = shift @args;
		if (@args == 0) {
			notice($user, 'Syntax: TOPICAPPEND <#channel> <message>');
		} else {
			$msg =~ s/^topicappend #(?:\S+)? //i;
			cs_topicappend($user, $chan, $msg);
		}
	}
	elsif($cmd =~ /^topicprepend$/i) {
		my $chan = shift @args;
		if (@args == 0) {
			notice($user, 'Syntax: TOPICPREPEND <#channel> <message>');
		} else {
			$msg =~ s/^topicprepend #(?:\S+)? //i;
			cs_topicprepend($user, $chan, $msg);
		}
	}
	else {
		notice($user, "Unrecognized command \002$cmd\002.", "For help, type: \002/msg chanserv help\002");
		wlog($csnick, LOG_DEBUG(), "$src tried to use $csnick $msg");
	}
}

sub cs_register($$;$$) {
	my ($user, $chan, $pass, $desc) = @_;
	# $pass is still passed in, but never used!
	my $src = get_user_nick($user);
	my $cn = $chan->{CHAN};

	unless(is_identified($user, $src)) {
		notice($user, 'You must register your nickname first.', "Type \002/msg NickServ HELP\002 for information on registering nicknames.");
		return;
	}

	unless(is_in_chan($user, $chan)) {
	        notice($user, "You are not in \002$cn\002.");
	        return;
	}

	if(services_conf_chanreg_needs_oper && !adminserv::is_svsop($user)) {
		notice($user, "You must be network staff to register a channel\n");
		return;
	}
	unless(get_op($user, $chan) & ($opmodes{o} | $opmodes{a} | $opmodes{q})) {
	# This would be preferred to be a 'opmode_mask' or something
	# However that might be misleading due to hop not being enough to register
		notice($user, "You must have channel operator status to register \002$cn\002.");
		return;
	}

	my $root = get_root_nick($src);

	if($desc) {
		my $dlength = length($desc);
		if($dlength >= 350) {
			notice($user, 'Channel description is too long by '. $dlength-350 .' character(s). Maximum length is 350 characters.');
			return;
		}
	}

	if($register->execute($cn, $desc, $root)) {
		notice($user, "\002Your channel is now registered. Thank you.\002");
		notice($user, ' ', "\002NOTICE:\002 Channel passwords are not used, as a security precaution.")
			if $pass;
		set_acc($root, $user, $chan, FOUNDER);
		$set_modelock->execute(services_conf_default_channel_mlock, $cn);
		do_modelock($chan);
		services::ulog($csnick, LOG_INFO(), "registered $cn", $user, $chan);
		botserv::bs_assign($user, $chan, services_conf_default_chanbot) if services_conf_default_chanbot;
	} else {
		notice($user, 'That channel has already been registered.');
	}
}

=cut
cs_command new SrSv::AgentUI::Simple {
	COMMAND => [qw(uop vop hop aop sop cf cofounder cof cfounder)],
	SYNTAX => '#chan add/del/list/wipe/clear [nick/mask]',
	CALL => \&cs_xop_dispatch,
	CMD_TOO => 1,
};
=cut
sub cs_xop_dispatch {
	my ($user, $cmd, $chan, $cmd2, @args) = @_;
	$cmd = uc $cmd;

	if($cmd2 =~ /^add$/i) {
		if(@args == 1) {
			cs_xop_add($user, $chan, $cmd, $args[0]);
		} else {
			notice($user, 'Syntax: '.uc $cmd.' <#channel> ADD <nick>');
		}
	}
	elsif($cmd2 =~ /^del(ete)?$/i) {
		if(@args == 1) {
			cs_xop_del($user, $chan, $cmd, $args[0]);
		} else {
			notice($user, 'Syntax: '.uc $cmd.' <#channel> DEL <nick>');
		}
	}
	elsif($cmd2 =~ /^list$/i) {
		if(@args >= 0) {
			cs_xop_list($user, $chan, $cmd, $args[0]);
		} else {
			notice($user, 'Syntax: '.uc $cmd.' <#channel> LIST [mask]');
		}
	}
	elsif($cmd2 =~ /^(wipe|clear)$/i) {
		if(@args == 0) {
			cs_xop_wipe($user, $chan, $cmd);
		} else {
			notice($user, 'Syntax: '.uc $cmd.' <#channel> WIPE');
		}
	}
	else {
		notice($user, 'Syntax: '.uc $cmd.' <#channel> <ADD|DEL|LIST|WIPE>');
	}
}

sub cs_xop_ad_pre($$$$$) {
	my ($user, $chan, $nick, $level, $del) = @_;
	
	my $old = get_acc($nick, $chan); $old = 0 unless $old;
	my $slevel = get_best_acc($user, $chan);
	
	unless(($del and is_identified($user, $nick)) or adminserv::can_do($user, 'SERVOP')) {
		unless($level < $slevel and $old < $slevel) {
			notice($user, $err_deny);
			return undef;
		}
		my $cn = $chan->{CHAN};
		my $overrideMsg = "$levels[$level] $cn ".($del ? 'DEL' : 'ADD')." $nick";
		can_do($chan, 'ACCCHANGE', $user, { OVERRIDE_MSG => $overrideMsg }) or return undef;
	}

	nickserv::chk_registered($user, $nick) or return undef;
	if (nr_chk_flag($nick, NRF_NOACC()) and !adminserv::can_do($user, 'SERVOP') and !$del) {
		notice($user, "\002$nick\002 is not able to be added to access lists.");
		return undef;
	}

	return $old;
}

sub cs_xop_list($$$;$) {
	my ($user, $chan, $cmd, $mask) = @_;
	chk_registered($user, $chan) or return;
	my $cn = $chan->{CHAN};
	my $level = xop_byname($cmd);

	my $overrideMsg = "$cmd $cn LIST";
	can_do($chan, 'ACCLIST', $user, { OVERRIDE_MSG => $overrideMsg }) or return;

	my @reply;
	if($mask) {
		my ($mnick, $mident, $mhost) = glob2sql(parse_mask($mask));
		$mnick = '%' if($mnick eq '');
		$mident = '%' if($mident eq '');
		$mhost = '%' if($mhost eq '');
		
		$get_acc_list_mask->execute($mnick, $cn, $level, $mnick, $mident, $mhost);
		while(my ($n, $a, $t, $lu, $id, $vh) = $get_acc_list_mask->fetchrow_array) {
			push @reply, "*) $n ($id\@$vh)" . ($a ? ' Added by: '.$a : '');
			push @reply, '      '.($t ? 'Date/time added: '. gmtime2($t).' ' : '').
				($lu ? 'Last used '.time_ago($lu).' ago' : '') if ($t or $lu);
		}
		$get_acc_list_mask->finish();
	} else {
		$get_acc_list->execute($cn, $level);
		while(my ($n, $a, $t, $lu, $id, $vh) = $get_acc_list->fetchrow_array) {
			push @reply, "*) $n ($id\@$vh)" . ($a ? ' Added by: '.$a : '');
			push @reply, '      '.($t ? 'Date/time added: '. gmtime2($t).' ' : '').
				($lu ? 'Last used '.time_ago($lu).' ago' : '') if ($t or $lu);
		}
		$get_acc_list->finish();
	}

	notice($user, "$levels[$level] list for \002$cn\002:", @reply);

	return;
}

sub cs_xop_wipe($$$) {
	my ($user, $chan, $cmd, $nick) = @_;
	chk_registered($user, $chan) or return;
	
	my $slevel = get_best_acc($user, $chan);
	my $level = xop_byname($cmd);

	unless($level < $slevel) {
		notice($user, $err_deny);
		return;
	}
	my $cn = $chan->{CHAN};
	my $overrideMsg = "$cmd $cn WIPE";
	my $srcnick = can_do($chan, 'ACCCHANGE', $user, { ACC => $slevel, OVERRIDE_MSG => $overrideMsg }) or return;

	$wipe_acc_list->execute($cn, $level);

	my $log_str = "wiped the $cmd list of \002$cn\002.";
	my $src = get_user_nick($user);
	notice($user, "You have $log_str");
	ircd::notice(agent($chan), '%'.$cn, "\002$src\002 has $log_str")
		if cr_chk_flag($chan, CRF_VERBOSE);
	services::ulog($csnick, LOG_INFO(), $log_str, $user, $chan);

	memolog($chan, "\002$srcnick\002 $log_str");
}

sub cs_xop_add($$$$) {
	my ($user, $chan, $cmd, $nick) = @_;
	
	chk_registered($user, $chan) or return;
	my $level = xop_byname($cmd);
	my $old = cs_xop_ad_pre($user, $chan, $nick, $level, 0);
	return unless defined($old);

	my $cn = $chan->{CHAN};
	
	if($old == $level) {
		notice($user, "\002$nick\002 already has $levels[$level] access to \002$cn\002.");
		return;
	}

	if($old == FOUNDER) {
		notice($user, "\002$nick\002 is the founder of \002$cn\002 and cannot be added to access lists.",
			"For more information, type: \002/msg chanserv help set founder\002");
		return;
	}

	my $root = get_root_nick($nick);
	my $auth = nr_chk_flag($root, NRF_AUTH());
	my $src = get_user_nick($user);

	if($auth) {
		$add_auth->execute($cn, "$src:".($old ? $old : 0 ).":$level:".time(), $root);
		del_acc($root, $chan) if $level < $old;
	}
	else {
		set_acc($root, $user, $chan, $level);
	}

	if($old < 0) {
		$del_nick_akick->execute($cn, $root);
		my $log_str = "moved $root from the AKICK list to the ${levels[$level]} list of \002$cn\002".
			($auth ? ' (requires authorization)' : '');
			
		my $src = get_user_nick($user);
		notice_all_nicks($user, $root, "\002$src\002 $log_str");
		ircd::notice(agent($chan), '%'.$cn, "\002$src\002 $log_str")
			if cr_chk_flag($chan, CRF_VERBOSE);
		services::ulog($csnick, LOG_INFO(), $log_str, $user, $chan);
		my $srcnick = can_do($chan, 'ACCLIST', $user);
		memolog($chan, "\002$srcnick\002 $log_str");
	} else {
		my $log_str = ($old?'moved':'added')." \002$root\002" 
			. ($old ? " from the ${levels[$old]}" : '') .
			" to the ${levels[$level]} list of \002$cn\002" .
			($auth ? ' (requires authorization)' : '');
		my $src = get_user_nick($user);
		notice_all_nicks($user, $root, "\002$src\002 $log_str");
		ircd::notice(agent($chan), '%'.$cn, "\002$src\002 $log_str")
			if cr_chk_flag($chan, CRF_VERBOSE);
		services::ulog($csnick, LOG_INFO(), $log_str, $user, $chan);
		my $srcnick = can_do($chan, 'ACCLIST', $user);
		memolog($chan, "\002$srcnick\002 $log_str");
	}
}

sub cs_xop_del($$$) {
	my ($user, $chan, $cmd, $nick) = @_;

	chk_registered($user, $chan) or return;
	my $level = xop_byname($cmd);
	my $old = cs_xop_ad_pre($user, $chan, $nick, $level, 1);
	return unless defined($old);

	my $cn = $chan->{CHAN};
	
	unless($old == $level) {
		notice($user, "\002$nick\002 is not on the ${levels[$level]} list of \002$cn\002.");
		return;
	}

	my $root = get_root_nick($nick);
	my $srcnick = can_do($chan, 'ACCLIST', $user);

	del_acc($root, $chan);

	my $src = get_user_nick($user);
	my $log_str = "removed \002$root\002 ($nick) from the ${levels[$level]} list of \002$cn\002";
	notice_all_nicks($user, $root, "\002$src\002 $log_str");
	ircd::notice(agent($chan), '%'.$cn, "\002$src\002 $log_str")
		if cr_chk_flag($chan, CRF_VERBOSE);
	services::ulog($csnick, LOG_INFO(), $log_str, $user, $chan);
	memolog($chan, "\002$srcnick\002 $log_str");
}

sub cs_count($$) {
	my ($user, $chan) = @_;

	chk_registered($user, $chan) or return;

	my $cn = $chan->{CHAN};
	my $overrideMsg = "COUNT $cn";
	if(can_do($chan, 'ACCLIST', $user, { OVERRIDE_MSG => $overrideMsg })) {
	} else {
		return;
	}

	my $reply = '';
	for (my $level = $plzero + 1; $level < COFOUNDER + 2; $level++) {
		$get_acc_count->execute($cn, $level - 1);
		my ($num_recs) = $get_acc_count->fetchrow_array;
		$reply = $reply." $plevels[$level]: ".$num_recs;
	}
	notice($user, "\002$cn Count:\002 ".$reply);
}

sub cs_levels_pre($$$;$) {
	my($user, $chan, $cmd, $listonly) = @_;

	chk_registered($user, $chan) or return 0;
	my $cn = $chan->{CHAN};
	my $overrideMsg = "LEVELS $cn $cmd";
	return can_do($chan, ($listonly ? 'LEVELSLIST' : 'LEVELS'), $user, { OVERRIDE_MSG => $overrideMsg });
}

sub cs_levels_set($$$;$) {
	my ($user, $chan, $perm, $level) = @_;

	cs_levels_pre($user, $chan, "$perm $level") or return;
	my $cn = $chan->{CHAN};

	unless(is_level($perm)) {
		notice($user, "$perm is not a valid permission.");
		return;
	}

	if(defined($level)) {
		$level = xop_byname($level);
		unless(defined($level) and $level >= 0) {
			notice($user, 'You must specify one of the following levels: '.
				'any, uop, vop, hop, aop, sop, cofounder, founder, nobody');
			return;
		}

		$get_level_max->execute($perm);
		my ($max) = $get_level_max->fetchrow_array;
		$get_level_max->finish();

		if($max and $level > $max) {
			notice($user, "\002$perm\002 cannot be set to " . $plevels[$level+$plzero] . '.');
			return;
		}
		
		$add_level->execute($cn, $perm);
		$set_level->execute($level, $cn, $perm);
		
		if($level == 8) {
			notice($user, "\002$perm\002 is now disabled in \002$cn\002.");
		} else {
			notice($user, "\002$perm\002 now requires " . $levels[$level] . " access in \002$cn\002.");
		}
	} else {
		$reset_level->execute($perm, $cn);

		notice($user, "\002$perm\002 has been reset to default.");
	}
}

sub cs_levels_list($$) {
	my ($user, $chan) = @_;

	cs_levels_pre($user, $chan, 'LIST', 1) or return;
	my $cn = $chan->{CHAN};

	$get_levels->execute($cn);
	my @data;
	while(my ($name, $def, $lvl) = $get_levels->fetchrow_array) {
		push @data, [$name,
			(defined($lvl) ? $plevels[$lvl+$plzero] : $plevels[$def+$plzero]),
			(defined($lvl) ? '' : '(default)')];
	}

	notice($user, columnar { TITLE => "Permission levels for \002$cn\002:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT) }, @data);
}

sub cs_levels_clear($$) {
	my ($user, $chan) = @_;

	cs_levels_pre($user, $chan, 'CLEAR') or return;
	my $cn = $chan->{CHAN};

	$clear_levels->execute($cn);

	notice($user, "All permissions have been reset to default.");
}

sub cs_akick_pre($$$;$) {
	my ($user, $chan, $overrideMsg, $list) = @_;
	
	chk_registered($user, $chan) or return 0;

	return can_do($chan, ($list ? 'AKICKLIST' : 'AKICK'), $user, { OVERRIDE_MSG => $overrideMsg });
}

sub cs_akick_add($$$$) {
	my ($user, $chan, $mask, $reason) = @_;
	my $cn = $chan->{CHAN};

	my $adder = cs_akick_pre($user, $chan, "ADD $mask $reason") or return;

	my ($nick, $ident, $host) = parse_mask($mask);

	if(($ident eq '' or $host eq '') and not ($ident eq '' and $host eq '')) {
		notice($user, 'Invalid hostmask.');
		return;
	}

	if($ident eq '') {
		$nick = $mask;

		unless(valid_nick($nick)) {
			$mask = normalize_hostmask($mask);
			($nick, $ident, $host) = parse_mask($mask);
		}
	}

	if ($ident eq '' and $host eq '' and !nickserv::is_registered($nick)) {
		notice($user, "\002$nick\002 is not registered");
		return;
	}

	my $rlength = length($reason);
	if($rlength >= 350) {
		notice($user, 'AKick reason is too long by '. $rlength-350 .' character(s). Maximum length is 350 characters.');
		return;
	}

	my $log_str;
	my $src = get_user_nick($user);
	if($ident eq '' and $host eq '' and my $old = get_acc($nick, $chan)) {
		if ($old == -1) {
			notice($user, "\002$nick\002 is already on the AKick list in \002$cn\002");
			return;
		}
		if($old < get_best_acc($user, $chan) or adminserv::can_do($user, 'SERVOP')) {
			if ($old == FOUNDER()) {
			# This is a fallthrough for the override case.
			# It shouldn't happen otherwise.
			# I didn't make it part of the previous conditional
			# b/c just $err_deny is a bit undescriptive in the override case.
				notice($user, "You can't akick the founder!", $err_deny);
				return;
			}
			
			my $root = get_root_nick($nick);
			$add_nick_akick->execute($cn, $src, $reason, $nick); $add_nick_akick->finish();
			set_acc($nick, $user, $chan, -1);
			$log_str = "moved \002$nick\002 (root: \002$root\002) from the $levels[$old] list".
				" to the AKick list of \002$cn\002";
			notice_all_nicks($user, $root, "\002$src\002 $log_str");
		} else {
			notice($user, $err_deny);
			return;
		}
	} else {
		if($ident eq '' and $host eq '') {
			$add_nick_akick->execute($cn, $src, $reason, $nick); $add_nick_akick->finish();
			if (find_auth($cn, $nick)) { 
			# Don't allow a pending AUTH entry to potentially override an AKick entry
			# Believe it or not, it almost happened with #animechat on SCnet.
			# This would also end up leaving an orphan entry in the akick table.
				$nickserv::del_auth->execute($nick, $cn);
				$nickserv::del_auth->finish();
			}
			set_acc($nick, $user, $chan, -1);
			my $root = get_root_nick($nick);
			$log_str = "added \002$nick\002 (root: \002$root\002) to the AKick list of \002$cn\002.";
		} else {
			($nick, $ident, $host) = glob2sql($nick, $ident, $host);
			unless($add_akick->execute($cn, $nick, $ident, $host, $adder, $reason)) {
				notice($user, "\002$mask\002 is already on the AKick list of \002$cn\002.");
				return;
			}
			$log_str = "added \002$mask\002 to the AKick list of \002$cn\002.";
		}
		
	}
	notice($user, "You have $log_str");
	ircd::notice(agent($chan), '%'.$cn, "\002$src\002 $log_str")
		if cr_chk_flag($chan, CRF_VERBOSE);
	services::ulog($csnick, LOG_INFO(), $log_str, $user, $chan);
	memolog($chan, "\002$adder\002 $log_str");

	akick_allchan($chan);
}

sub get_akick_by_num($$) {
	my ($chan, $num) = @_;
	my $cn = $chan->{CHAN};

	$get_akick_by_num->execute($cn, $num);
	my ($nick, $ident, $host) = $get_akick_by_num->fetchrow_array();
	($nick, $ident, $host) = sql2glob($nick, $ident, $host);
	$get_akick_by_num->finish();
	if(!$nick) {
		return undef;
	} elsif($ident eq '' and $host eq '') {
		# nick based akicks don't use nicks but nickreg.id
		# so we have to get the nickreg.nick back
		$nick = nickserv::get_id_nick($nick);
	}
	return ($nick, $ident, $host);
}

sub cs_akick_del($$$) {
	my ($user, $chan, $mask) = @_;
	my $cn = $chan->{CHAN};

	my $adder = cs_akick_pre($user, $chan, "DEL $mask") or return;

	my @masks;
	if ($mask =~ /^[0-9\.,-]+$/) {
		foreach my $num (makeSeqList($mask)) {
			my ($nick, $ident, $host) = get_akick_by_num($chan, $num - 1) or next;
			if($ident eq '' and $host eq '') {
				push @masks, $nick;
			} else {
				push @masks, "$nick!$ident\@$host";
			}
		}
	} else {
		@masks = ($mask);
	}
	foreach my $mask (@masks) {
		my ($nick, $ident, $host) = parse_mask($mask);

		if(($ident eq '' or $host eq '') and not ($ident eq '' and $host eq '')) {
			notice($user, 'Invalid hostmask.');
			return;
		}

		if($ident eq '') {
			$nick = $mask;

			unless(valid_nick($nick)) {
				$mask = normalize_hostmask($mask);
				($nick, $ident, $host) = parse_mask($mask);
			}
		}

		if ($ident eq '' and $host eq '' and !nickserv::is_registered($nick)) {
			notice($user, "\002$nick\002 is not registered");
			return;
		}

		my ($success, $log_str) = do_akick_del($chan, $mask, $nick, $ident, $host);
		my $src = get_user_nick($user);
		if($success) {
			notice($user, "\002$src\002 $log_str");
			services::ulog($csnick, LOG_INFO(), $log_str, $user, $chan);
			ircd::notice(agent($chan), '%'.$cn, "\002$src\002 $log_str") if cr_chk_flag($chan, CRF_VERBOSE);
			memolog($chan, "\002$adder\002 $log_str");
		} else {
			notice($user, $log_str);
		}
	}
}

sub do_akick_del($$$$$) {
	my ($chan, $mask, $nick, $ident, $host) = @_;
	my $cn = $chan->{CHAN};

	my $log_str;
	if($ident eq '' and $host eq '') {
		if(get_acc($nick, $chan) == -1) {
			del_acc($nick, $chan);
			$del_nick_akick->execute($cn, $nick); $del_nick_akick->finish();
			my $root = get_root_nick($nick);
			return (1, "deleted \002$nick\002 (root: \002$root\002) from the AKick list of \002$cn\002.")
		} else {
			return (undef, "\002$mask\002 was not on the AKick list of \002$cn\002.");
		}
	} else {
		($nick, $ident, $host) = glob2sql($nick, $ident, $host);
		if($del_akick->execute($cn, $nick, $ident, $host) != 0) {
			return (1, "deleted \002$mask\002 from the AKick list of \002$cn\002.");
		} else {
			return (undef, "\002$mask\002 was not on the AKick list of \002$cn\002.");
		}
	}
}

sub cs_akick_list($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	cs_akick_pre($user, $chan, 'LIST', 1) or return;

	my @data;
	
	$get_akick_list->execute($cn);
	my $i = 0;
	while(my ($nick, $ident, $host, $adder, $reason, $time) = $get_akick_list->fetchrow_array) {
		if($ident ne '') {
			($nick, $ident, $host) = sql2glob($nick, $ident, $host);
		}

		if($ident eq '' and $host eq '') {
			$nick = nickserv::get_id_nick($nick);
		} else {
			$nick = "$nick!$ident\@$host";
		}

		push @data, ["\002".++$i."\002", $nick, $adder, ($time ? gmtime2($time) : ''), $reason];
	}

	notice($user, columnar {TITLE => "AKICK list of \002$cn\002:", DOUBLE=>1,
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data);
}

sub cs_akick_wipe($$$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	my $adder = cs_akick_pre($user, $chan, 'WIPE') or return;

	$drop_akick->execute($cn);
	$wipe_acc_list->execute($cn, -1);
	my $log_str = "wiped the AKICK list of \002$cn\002.";
	my $src = get_user_nick($user);
	notice($user, "You have $log_str");
	ircd::notice(agent($chan), '%'.$cn, "\002$src\002 $log_str") if cr_chk_flag($chan, CRF_VERBOSE);
	services::ulog($csnick, LOG_INFO(), $log_str, $user, $chan);
	memolog($chan, "\002$adder\002 $log_str");
}

sub cs_akick_enforce($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	chk_registered($user, $chan) or return;

	can_do($chan, 'AKickEnforce', $user, { OVERRIDE_MSG => "AKICK $cn ENFORCE" }) or return;

	akick_allchan($chan);
}

=cut
cs_command new SrSv::AgentUI::Simple {
	COMMAND => [qw(info)],
	SYNTAX => 'LIST:#chan',
	CALL => \&cs_info,
	NO_WRAPPER => 1,
};
=cut
sub cs_info($@) {
	my ($user, @chanList) = @_;

	my @reply;
	foreach my $cn (@chanList) {
		if(ref($cn) eq 'HASH') {
			$cn = $cn->{CHAN};
		}
		elsif($cn =~ /,/) {
			push @chanList, split(',', $cn);
			next;
		}
		my $chan = { CHAN => $cn };
		unless(__can_do($chan, 'INFO', undef, 0)) {
			can_do($chan, 'INFO', $user, { OVERRIDE_MSG => "INFO $cn" })
				or next;
		}

		$get_info->execute($cn);
		my @result = $get_info->fetchrow_array;
		unless(@result) {
			push @reply, "The channel \002$cn\002 is not registered.";
			next;
		}

		my ($descrip, $regd, $last, $topic, $topicer, $modelock, $founder, $successor, $bot, $bantype,$bantime) = @result;

		$modelock = modes::sanitize($modelock) unless can_do($chan, 'GETKEY', $user, { NOREPLY => 1 });

		my @opts;

		my $topiclock = get_level($chan, 'SETTOPIC');
		push @opts, "Topic Lock ($levels[$topiclock])" if $topiclock;

		if(cr_chk_flag($chan, (CRF_CLOSE | CRF_DRONE))) {
			push @reply, "\002$cn\002 is closed and cannot be used: ". get_close($chan);
			next;
		}

		my @extra;
		push @extra, 'Will not expire' if cr_chk_flag($chan, CRF_HOLD);
		push @extra, 'Channel is frozen and access suspended' if cr_chk_flag($chan, CRF_FREEZE);

		push @opts, 'OpGuard' if cr_chk_flag($chan, CRF_OPGUARD);
		push @opts, 'BotStay' if cr_chk_flag($chan, CRF_BOTSTAY);
		push @opts, 'SplitOps' if cr_chk_flag($chan, CRF_SPLITOPS);
		push @opts, 'Verbose' if cr_chk_flag($chan, CRF_VERBOSE);
		push @opts, 'NeverOp' if cr_chk_flag($chan, CRF_NEVEROP);
		push @opts, 'Ban type '.$bantype if $bantype;
		push @opts, 'Ban time '.$bantime . ' seconds'  if $bantype;
		my $opts = join(', ', @opts);

		my @data;

		push @data,	['Founder:', $founder];
		push @data, 	['Successor:', $successor] if $successor;
		push @data, 	['Description:', $descrip] if $descrip;
		push @data,	['Mode lock:',	$modelock];
		push @data, 	['Settings:',	$opts] if $opts;
		push @data,	['ChanBot:',	$bot] if $bot and $bot ne '';
		#FIXME: memo level
		push @data,	['Registered:', gmtime2($regd)],
				['Last opping:', gmtime2($last)],
				['Time now:', gmtime2(time)];

		push @reply, columnar {TITLE => "ChanServ info for \002$cn\002:", NOHIGHLIGHT => 1}, @data,
			{COLLAPSE => \@extra, BULLET => 1};
	}
	notice($user, @reply);
}

sub cs_set_pre($$$$) {
	my ($user, $chan, $set, $parm) = @_;
	my $cn = $chan->{CHAN};
	my $override = 0;

	my %valid_set = ( 
		'founder' => 1, 'successor' => 1, 'unsuccessor' => 1,
		#'mlock' => 1, 'modelock' => 1,
		'desc' => 1,
		'topiclock' => 1, 'greet' => 1, 'opguard' => 1,
		'freeze' => 1, 'botstay' => 1, 'verbose' => 1, 
		'splitops' => 1, 'bantype' => 1, 'dice' => 1,
		'welcomeinchan' => 1, 'log' => 1, 

		'hold' => 1, 'noexpire' => 1, 'no-expire' => 1,

		'autovoice' => 1, 'avoice' => 1,
		'neverop' => 1, 'noop' => 1,
		'noclones' => 1,
		'bantime' => 1,
	);
	my %override_set = (
		'hold' => 'SERVOP', 'noexpire' => 'SERVOP', 'no-expire' => 'SERVOP',
		'freeze' => 'FREEZE', 'botstay' => 'BOT', 'log' => 'LOG',
	);

	chk_registered($user, $chan) or return 0;
	if($set =~ /m(?:ode)?lock/) {
		notice($user, "CS SET MLOCK is deprecated and replaced with CS MLOCK",
			"For more information, please /CS HELP MLOCK");
		return 0;
	}
	unless($valid_set{lc $set}) {
		notice($user, "$set is not a valid ChanServ setting.");
		return 0;
	}

	if($override_set{lc($set)}) {
		if(adminserv::can_do($user, $override_set{lc($set)}) ) {
			if(services_conf_log_overrides) {
				my $src = get_user_nick($user);
				wlog($csnick, LOG_INFO(), "\002$src\002 used override CS SET $cn $set $parm");
			}
			$override = 1;
		} else {
			notice($user, $err_deny);
			return 0;
		}
	}
	else {
		can_do($chan, 'SET', $user) or return 0;
	}

	return 1;
}

sub cs_set($$$;$) {
	my ($user, $chan, $set, $parm) = @_;
	my $cn = $chan->{CHAN};
	$set = lc $set;

	cs_set_pre($user, $chan, $set, $parm) or return;

	if($set =~ /^founder$/i) {
		my $override;
		unless(get_best_acc($user, $chan) == FOUNDER) {
			if(adminserv::can_do($user, 'SERVOP')) {
				$override = 1;
			} else {
				notice($user, $err_deny);
				return;
			}
		}

		my $root;
		unless($root = get_root_nick($parm)) {
			notice($user, "The nick \002$parm\002 is not registered.");
			return;
		}
		
		$get_founder->execute($cn);
		my ($prev) = $get_founder->fetchrow_array;
		$get_founder->finish();

		if(lc($root) eq lc($prev)) {
			notice($user, "\002$parm\002 is already the founder of \002$cn\002.");
			return;
		}
		
		set_acc($prev, $user, $chan, COFOUNDER);

		$set_founder->execute($root, $cn); $set_founder->finish();
		set_acc($root, $user, $chan, FOUNDER);

		notice($user, ($override ? "The previous founder, \002$prev\002, has" : "You have") . " been moved to the co-founder list of \002$cn\002.");
		notice_all_nicks($user, $root, "\002$root\002 has been set as the founder of \002$cn\002.");
		services::ulog($csnick, LOG_INFO(), "set founder of \002$cn\002 to \002$root\002", $user, $chan);

		$get_successor->execute($cn);
		my $suc = $get_successor->fetchrow_array; $get_successor->finish();
		if(lc($suc) eq lc($root)) {
			$del_successor->execute($cn); $del_successor->finish();
			notice($user, "Successor has been removed from \002$cn\002.");
		}

		return;
	}

	if($set eq 'successor') {
		unless(get_best_acc($user, $chan) == FOUNDER or adminserv::can_do($user, 'SERVOP')) {
			notice($user, $err_deny);
			return;
		}

		if(get_acc($parm, $chan) == 7) {
			notice($user, "The channel founder may not be the successor.");
			return;
		}

		my $root;
		unless($root = get_root_nick($parm)) {
			notice($user, "The nick \002$parm\002 is not registered.");
			return;
		}

		$set_successor->execute($root, $cn); $set_successor->finish();

		notice($user, "\002$parm\002 is now the successor of \002$cn\002");
		services::ulog($csnick, LOG_INFO(), "set successor of \002$cn\002 to \002$root\002", $user, $chan);
		return;
	}

	if($set eq 'unsuccessor') {
		unless(get_best_acc($user, $chan) == FOUNDER or adminserv::can_do($user, 'SERVOP')) {
			notice($user, $err_deny);
			return;
		}

		$del_successor->execute($cn); $del_successor->finish();

		notice($user, "Successor has been removed from \002$cn\002.");
		services::ulog($csnick, LOG_INFO(), "removed successor from \002$cn\002", $user, $chan);
		return;
	}

	if($set =~ /m(?:ode)?lock/) {
		my $modes = modes::merge($parm, '+r', 1);
		$modes = sanitize_mlockable($modes);
		$set_modelock->execute($modes, $cn);

		notice($user, "Mode lock for \002$cn\002 has been set to: \002$modes\002");
		do_modelock($chan);
		return;
	}

	if($set eq 'desc') {
		$set_descrip->execute($parm, $cn);

		notice($user, "Description of \002$cn\002 has been changed.");
		return;
	}

	if($set eq 'topiclock') {
		my $perm = xop_byname($parm);
		if($parm =~ /^(?:no|off|false|0)$/i) {
			cs_levels_set($user, $chan, 'SETTOPIC');
			cs_levels_set($user, $chan, 'TOPIC');
		} elsif($perm >= 0 and defined($perm)) {
			cs_levels_set($user, $chan, 'SETTOPIC', $parm);
			cs_levels_set($user, $chan, 'TOPIC', $parm);
		} else {
			notice($user, 'Syntax: SET <#chan> TOPICLOCK <off|any|uop|vop|hop|aop|sop|cf|founder>');
		}
		return;
	}

	if($set =~ /^bantype$/i) {
		unless (misc::isint($parm) and ($parm >= 0 and $parm <= 10)) {
			notice($user, 'Invalid bantype');
			return;
		}

		$set_bantype->execute($parm, $cn);

		notice($user, "Ban-Type for \002$cn\002 now set to \002$parm\002.");

		return;
	}
	if($set =~ /^bantime$/i) {
		if ( ( my $p = substr($parm, 0, 1) ) != '+' ) {
			$parm = '+' . $parm;
		}
		my $time = $parm;
		unless ($time == 0) {
			$time = parse_time ($parm);
			if(!$time) {
				notice ($user, "Invalid bantime. See /msg chanserv help set bantime for examples.");
				return;
			}
		}
		set_bantime($time, $cn);
		notice($user, "Ban time for \002$cn\002 now set to \002$time\002 seconds.");
		return;
	}
	my $val;
	if($parm =~ /^(?:no|off|false|0)$/i) { $val = 0; }
	elsif($parm =~ /^(?:yes|on|true|1)$/i) { $val = 1; }
	else {
		notice($user, "Please say \002on\002 or \002off\002.");
		return;
	}
	if ($set =~ /^(?:noclones)$/i) {
		cr_set_flag($chan, CRF_NOCLONES, $val);
		if($val) {
			notice($user,
				"Noclones is now \002ON\002.",
				"Clones will be kicked out of \002$cn\002."
			);
		} else {
			notice($user,
				"Noclones is now \002OFF\002.",
				"People are allowed to bring clones in \002$cn\002."
			);
		}
	}
	if($set =~ /^(?:opguard|secureops)$/i) {
		cr_set_flag($chan, CRF_OPGUARD, $val);

		if($val) {
			notice($user,
				"OpGuard is now \002ON\002.",
				"Channel status may not be granted by unauthorized users in \002$cn\002."#,
				#"Note that you must change the $csnick LEVELS settings for VOICE, HALFOP, OP, and/or ADMIN for this setting to have any effect."
			);
		} else {
			notice($user,
				"OpGuard is now \002OFF\002.",
				"Channel status may be given freely in \002$cn\002."
			);
		}

		return;
	}

	if($set =~ /^(?:splitops)$/i) {
		cr_set_flag($chan, CRF_SPLITOPS, $val);

		if($val) {
			notice($user, "SplitOps is now \002ON\002.");
		} else {
			notice($user, "SplitOps is now \002OFF\002.");
		}

		return;
	}

	if($set =~ /^(hold|no-?expire)$/i) {
		cr_set_flag($chan, CRF_HOLD, $val);

		if($val) {
			notice($user, "\002$cn\002 will not expire");
			services::ulog($csnick, LOG_INFO(), "has held \002$cn\002", $user, $chan);
		} else {
			notice($user, "\002$cn\002 is no longer held from expiration");
			services::ulog($csnick, LOG_INFO(), "has removed \002$cn\002 from hold", $user, $chan);
		}

		return;
	}

	if($set =~ /^freeze$/i) {
		cr_set_flag($chan, CRF_FREEZE, $val);

		if($val) {
			notice($user, "\002$cn\002 is now frozen and access suspended");
			services::ulog($csnick, LOG_INFO(), "has frozen \002$cn\002", $user, $chan);
		} else {
			notice($user, "\002$cn\002 is now unfrozen and access restored");
			services::ulog($csnick, LOG_INFO(), "has unfrozen \002$cn\002", $user, $chan);
		}

		return;
	}

	if($set =~ /^botstay$/i) {
		cr_set_flag($chan, CRF_BOTSTAY, $val);

		if($val) {
			notice($user, "Bot will now always stay in \002$cn");
			botserv::bot_join($chan, undef);
		} else {
			notice($user, "Bot will now part if less than one user is in \002$cn");
			botserv::bot_part_if_needed(undef, $chan, "Botstay turned off");
		}

		return;
	}
	if($set =~ /^verbose$/i) {
		cr_set_flag($chan, CRF_VERBOSE, $val);

		if($val) {
			notice($user, "Verbose mode enabled on \002$cn");
		}
		else {
			notice($user, "Verbose mode disabled on \002$cn");
		}
		return;
	}

	if($set =~ /^greet$/i) {
		if($val) {
			notice($user, "$csnick SET $cn GREET ON is deprecated.", 
				"Please use $csnick LEVELS $cn SET GREET <rank>");
		} else {
			cs_levels_set($user, $chan, 'GREET', 'nobody');
		}

		return;
	}

	if($set =~ /^dice$/i) {
		if($val) {
			notice($user, "$csnick SET $cn DICE ON is deprecated.", 
				"Please use $csnick LEVELS $cn SET DICE <rank>");
		} else {
			cs_levels_set($user, $chan, 'DICE', 'nobody');
		}

		return;
	}

	if($set =~ /^welcomeinchan$/i) {
		cr_set_flag($chan, CRF_WELCOMEINCHAN(), $val);

		if($val) {
			notice($user, "WELCOME messages will be put in the channel.");
		} else {
			notice($user, "WELCOME messages will be sent privately.");
		}

		return;
	}

	if($set =~ /^log$/i) {
		unless(module::is_loaded('logserv')) {
			notice($user, "module logserv is not loaded, logging is not available.");
			return;
		}

		if($val) {
			logserv::addchan($user, $cn) and cr_set_flag($chan, CRF_LOG, $val);
		}
		else {
			logserv::delchan($user, $cn) and cr_set_flag($chan, CRF_LOG, $val);
		}
		return;
	}

	if($set =~ /^a(?:uto)?voice$/i) {
		cr_set_flag($chan, CRF_AUTOVOICE(), $val);

		if($val) {
			notice($user, "All users w/o access will be autovoiced on join.");
		} else {
			notice($user, "AUTOVOICE disabled.");
		}

		return;
	}

	if($set =~ /^(?:never|no)op$/i) {
		cr_set_flag($chan, CRF_NEVEROP(), $val);

		if($val) {
			notice($user, "Users will not be automatically opped on join.");
		} else {
			notice($user, "Users with access will now be automatically opped on join.");
		}

		return;
	}
}

sub cs_why($$@) {
	my ($user, $chan, @tnicks) = @_;

	chk_registered($user, $chan) or return;

	my $cn = $chan->{CHAN};

	my ($candoNick, $override) = can_do($chan, 'ACCLIST', $user, { OVERRIDE_MSG => "WHY $cn @tnicks" });
	return unless $candoNick;

	my @reply;
	foreach my $tnick (@tnicks) {
		my $tuser = { NICK => $tnick };
		unless(get_user_id($tuser)) {
			push @reply, "\002$tnick\002: No such user.";
			next;
		}

		my $has;
		if(is_online($tnick)) {
			$has = 'has';
		} else {
			$has = 'had';
		}

		my $n;
		$get_all_acc->execute(get_user_id($tuser), $cn);
		while(my ($rnick, $acc) = $get_all_acc->fetchrow_array) {
			$n++;
			push @reply, "\002$tnick\002 $has $plevels[$acc+$plzero] access to \002$cn\002 due to identification to the nick \002$rnick\002.";
		}
		$get_all_acc->finish();

		unless($n) {
			push @reply, "\002$tnick\002 has no access to \002$cn\002.";
		}
	}
	notice($user, @reply);
}

sub cs_setmodes($$$@) {
	my ($user, $cmd, $chan, @args) = @_;
	no warnings 'void';
	my $agent = $user->{AGENT} or $csnick;
	my $src = get_user_nick($user);
	my $cn = $chan->{CHAN};
	my $self;
	
	if (cr_chk_flag($chan, CRF_FREEZE())) {
		notice($user, "\002$cn\002 is frozen and access suspended.");
		return;
	}
	
	if(scalar(@args) == 0) {
		@args = ($src);
		$self = 1;
	} elsif($args[0] =~ /^#/) {
		foreach my $chn ($cn, @args) {
			next unless $chn =~ /^#/;
			no warnings 'prototype'; # we call ourselves
			cs_setmodes($user, $cmd, { CHAN => $chn });
		}
		return;
	} elsif((scalar(@args) == 1) and (lc($args[0]) eq lc($src))) {
		$self = 1;
	}

	# PROTECT is deprecated. remove it in a couple versions.
	# It should be called ADMIN under PREFIX_AQ
	my @mperms = ('VOICE', 'HALFOP', 'OP', 'ADMIN', 'OWNER');
	my @l = ('v', 'h', 'o', 'a', 'q');
	my ($level, @modes, $count);
	
	if($cmd =~ /voice$/i) { $level = 0 }
	elsif($cmd =~ /h(alf)?op$/i) { $level = 1 }
	elsif($cmd =~ /op$/i) { $level = 2 }
	elsif($cmd =~ /(protect|admin)$/i) { $level = 3 }
	elsif($cmd =~ /owner$/i) { $level = 4 }
	my $de = 1 if($cmd =~ s/^de//i);
	#$cmd =~ s/^de//i;

	my $acc = get_best_acc($user, $chan);
	
	# XXX I'm not sure this is the best way to do it.
	unless(
		($de and $self) or ($self and ($level + 2) <= $acc) or
		can_do($chan, $mperms[$level], $user, { ACC => $acc, NOREPLY => 1, OVERRIDE_MSG => "$cmd $cn @args" }) )
	{
		notice($user, "$cn: $err_deny");
		return;
	}

	my ($override, $check_override);

	foreach my $target (@args) {
		my ($tuser);
		
		$tuser = ($self ? $user : { NICK => $target } );
		
		unless(is_in_chan($tuser, $chan)) {
			notice($user, "\002$target\002 is not in \002$cn\002.");
			next;
		}

		my $top = get_op($tuser, $chan);
		
		if($de) {
			unless($top & (2**$level)) {
				notice($user, "\002$target\002 has no $cmd in \002$cn\002.");
				next;
			}

			if(!$override and get_best_acc($tuser, $chan) > $acc) {
				unless($check_override) {
					$override = adminserv::can_do($user, 'SUPER');
					$check_override = 1;
				}
				if($check_override and !$override) {
					notice($user, "\002$target\002 outranks you in \002$cn\002.");
					next;
				}
			}
		} else {
			if($top & (2**$level)) {
				if($self) {
					notice($user, "You already have $cmd in \002$cn\002.");
				} else {
					notice($user, "\002$target\002 already has $cmd in \002$cn\002.");
				}
				next;
			}
			if (cr_chk_flag($chan, CRF_OPGUARD()) and
				!can_keep_op($user, $chan, $tuser, $l[$level]))
			{
				notice($user, "$target may not hold ops in $cn because OpGuard is enabled. ".
					"Please respect the founders wishes.");
				next;
			}
		}

		push @modes, [($de ? '-' : '+').$l[$level], $target];
		$count++;

	}

	ircd::setmode2(agent($chan), $cn, @modes) if scalar @modes;
	ircd::notice(agent($chan), '%'.$cn, "$src used ".($de ? "de$cmd" : $cmd).' '.join(' ', @args))
		if !$self and (lc $user->{AGENT} eq lc $csnick) and cr_chk_flag($chan, CRF_VERBOSE);
}

sub cs_drop($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	chk_registered($user, $chan) or return;

	unless(get_best_acc($user, $chan) == FOUNDER or adminserv::can_do($user, 'SERVOP')) {
		notice($user, $err_deny);
		return;
	}

	drop($chan);
	notice($user, $cn.' has been dropped.');
	services::ulog($csnick, LOG_INFO(), "dropped $cn", $user, $chan);

	undef($enforcers{lc $cn});
	botserv::bot_part_if_needed(undef(), $chan, "Channel dropped.");
}

#my ($bansref, $unbansref, $expires) = parse_bans ($user, $chan, '', @targets, 1, $default_expiry);
#my ($bansref, $unbansref, $expires) = parse_bans ($user, $chan, '', @targets, 1, $expiry);
sub parse_bans($$$$;$$) {
	my ($user, $chan, $type, $targetsref, $temp, $expiry) = (@_);
	my (@bans, @unbans);
	my ($nick, $override);

	my @targets = @$targetsref;
	my $cn = $chan->{CHAN};
	my $src = get_user_nick($user);
	my $srclevel = get_best_acc($user, $chan);

	($nick, $override) = can_do($chan, 'BAN', $user, { ACC => $srclevel });	
	return unless $nick;

	my @errors = (
		["I'm sorry, $src, I'm afraid I can't do that."],
		["They are not in \002$cn\002."],
		[$err_deny],
		["User not found"],
	);

	foreach my $target (@targets) {
		my $tuser;

		if ($target =~ /^\+/ && $temp) {
			$expiry = $target;
			next;
		}
		elsif(ref($target)) {
			$tuser = $target;
		}
		elsif($target =~ /\,/) {
			push @targets, split(',', $target);
			next;
		}
		elsif($target eq '') {
			# Should never happen
			# but it could, given the split above
			next;
		}
		elsif($target =~ /^-/) {
			$target =~ s/^-//;
			push @unbans, $target;
			next;
		}
		elsif($target =~ /[!@]+/) {
			$target = normalize_hostmask($target);
			if ($temp) {
				push @bans, [$target, $expiry];
			} else {
				push @bans, $target;
			}
			next;
		}
		elsif(valid_nick($target)) {
			$tuser = { NICK => $target };
		}
		elsif($target = validate_ban($target)) {
			if ($temp) {
				push @bans, [$target, $expiry];
			} else {
				push @bans, $target;
			}
			next;
		} else {
			notice($user, "Not a valid ban target: $target");
			next;
		}

		my $targetlevel = get_best_acc($tuser, $chan);

		if(lc $target eq lc agent($chan) or adminserv::is_service($tuser)) {
			push @{$errors[0]}, get_user_nick($tuser);
			next;
		}

		unless(get_user_id($tuser)) {
			push @{$errors[1]}, get_user_nick($tuser);
			next;
		}

		if( $srclevel <= $targetlevel and not ($override && check_override($user, 'BAN', "BAN $cn $target")) ) {
			push @{$errors[2]}, $target;
			next;
		}

		if ($temp) {
			push @bans, [make_banmask($chan, $tuser, $type), $expiry];
		} else {
			push @bans, make_banmask($chan, $tuser, $type);
		}
	}

	if (!is_registered($chan)) {
		notice ($user,
			"$cn is not registered"
		);
		return;
	}

	foreach my $errlist (@errors) {
		if(@$errlist > 1) {
			my $msg = shift @$errlist;

			foreach my $e (@$errlist) { $e = "\002$e\002" }

			notice($user,
				"Cannot ban ".
				enum("or", @$errlist).
				": $msg"
			);
		}
	}

	return (\@bans, \@unbans);
}

sub cs_tempban($$) {
	my ($user, $argstring) = @_;
	my ( $expiry, $cn, $chan );

	my @args = split(/ /, $argstring);
	my $numargs = scalar @args;

	for (my $i = 0; $i < $numargs; $i++) {
		if ($args[$i] =~ /\#/) {
			$cn = $args[$i];
			$chan = { CHAN => $cn };
			splice (@args, $i, 1);
		}
	}

	if (!defined($cn) or !length($cn)) {
		notice ($user, "No channel given. The channel name \002must\002 include the # character.");
		return;
	}

	if ($args[-1] =~ /\+/) { #expire time is last arguement
		$expiry = pop @args;
		$expiry = parse_time($expiry);
	} else { #expire time is somewhere else (if given), get default expiry for now. 
		$expiry = get_bantime($chan);
	}

	my @targets;

	foreach my $arg (@args) {
		if ($arg =~ /\,/) {
			push @targets, split(/\,/, $arg);
			next;
		} else {
			push @targets, $arg;
		}
	}

	my $src = get_user_nick($user);

	my ($bansref, $unbansref) = parse_bans ($user, $chan, '', \@targets, 1, $expiry);

	if ((!$bansref || !scalar @$bansref) && (!$unbansref || !scalar @$unbansref)) {
		return;
	}

	if(scalar @$bansref) {
		tempban ($chan, @$bansref);

		ircd::notice(agent($chan), $cn, "$src used TEMPBAN ".join(' ', @$bansref))
			if (lc $user->{AGENT} eq lc $csnick) and (cr_chk_flag($chan, CRF_VERBOSE) and scalar(@$bansref));
	}
	cs_unban($user, $chan, @$unbansref) if scalar(@$unbansref);
}

sub cs_kick($$$;$$) {
	my ($user, $chan, $target, $ban, $reason) = @_;

	my $cmd = ($ban ? 'KICKBAN' : 'KICK');
	my $perm = ($ban ? 'BAN' : 'KICK');

	if(ref($chan) ne 'HASH' || !defined($chan->{CHAN})) {
		notice($user, "Invalid $cmd command, no channel specified");
		return;
	}

	my $srclevel = get_best_acc($user, $chan);

	my ($nick, $override) = can_do($chan, ($ban ? 'BAN' : 'KICK'), $user, { ACC => $srclevel });
	return unless $nick;

	my $src = get_user_nick($user);
	my $cn = $chan->{CHAN};

	$reason = "Requested by $src".($reason?": $reason":'');

	my @errors = (
		["I'm sorry, $src, I'm afraid I can't do that."],
		["They are not in \002$cn\002."],
		[$err_deny],
		["User not found"],
	);
	my @notinchan = ();
	my $peace = ({modes::splitmodes(get_modelock($chan))}->{Q}->[0] eq '+');

	my @targets = split(/\,/, $target);
	foreach $target (@targets) {
		my $tuser = { NICK => $target };
		my $targetlevel = get_best_acc($tuser, $chan);

		if(lc $target eq lc agent($chan) or adminserv::is_service($tuser)) {
			push @{$errors[0]}, $target;
			next;
		}

		if(get_user_id($tuser)) {
			unless(is_in_chan($tuser, $chan)) {
				if ($ban) {
					push @notinchan, $tuser;
				} else {
					push @{$errors[1]}, $target;
				}
				next;
			}
		} else {
			push @{$errors[3]}, $target;
			next;
		}

		if( ( ($peace and $targetlevel > 0) or ($srclevel <= $targetlevel) ) 
			and not ($override && check_override($user, ($ban ? 'BAN' : 'KICK'), "$cmd $cn $target")) )
		{
			push @{$errors[2]}, $target;
			next;
		}

		if($ban) {
			kickban($chan, $tuser, undef, $reason, 1);
		} else {
			ircd::kick(agent($chan), $cn, $target, $reason) unless adminserv::is_service($user);
		}
	}
	ircd::flushmodes() if($ban);

	foreach my $errlist (@errors) {
		if(@$errlist > 1) {
			my $msg = shift @$errlist;
	
			foreach my $e (@$errlist) { $e = "\002$e\002" }

			notice($user,
				"Cannot $cmd ".
				enum("or", @$errlist).
				": $msg"
			);
		}
	}
	cs_ban($user, $chan, '', @notinchan) if ($ban and scalar (@notinchan));
}

sub cs_kickmask($$$;$$) {
	my ($user, $chan, $mask, $ban, $reason) = @_;

	my $srclevel = get_best_acc($user, $chan);
	my $src = get_user_nick($user);
	my $cn = $chan->{CHAN};

	my $candoOpts = { ACC => $srclevel, OVERRIDE_MSG => 'KICK'.($ban ? 'BAN' : '')."MASK $cn $mask $reason" };
	my ($nick, $override) = can_do($chan, ($ban ? 'BAN' : 'KICK'), $user, $candoOpts);
	return unless $nick;


	$reason = "Requested by $src".($reason?": $reason":'');

	my $count = kickmask_noacc($chan, $mask, $reason, $ban);
	notice($user, ($count ? "Users kicked from \002$cn\002: $count." : "No users in \002$cn\002 matched $mask."))
}

sub cs_ban($$$@) {
	my ($user, $chan, $type, @targets) = @_;

	my $src = get_user_nick ($user);

	my $cn = $chan->{CHAN};

	my ($bansref, $unbansref) = parse_bans ($user, $chan, $type, \@targets);

	if ((!$bansref || !scalar @$bansref) && (!$unbansref || !scalar @$unbansref)) {
		return;
	}

	#ircd::ban_list(agent($chan), $cn, +1, 'b', @bans) if (scalar(@bans));
	tempban($chan, map { [ $_, get_bantime($chan)] } @$bansref);
	ircd::notice(agent($chan), $cn, "$src used BAN ".join(' ', @$bansref))
		if (lc $user->{AGENT} eq lc $csnick) and (cr_chk_flag($chan, CRF_VERBOSE) and scalar(@$bansref));
	cs_unban($user, $chan, @$unbansref) if scalar(@$unbansref);
}

sub cs_invite($$@) {
	my ($user, $chan, @targets) = @_;
	my $src = get_user_nick($user);
	my $cn = $chan->{CHAN};
	my $srclevel = get_best_acc($user, $chan);

	my @errors = (
		["They are not online."],
		["They are already in \002$cn\002."],
		[$err_deny]
	);

	my @invited;
	foreach my $target (@targets) {
		my $tuser;
		my $tnick;
		if(ref($target)) {
			$tuser = $target;
			$tnick = get_user_nick($tuser);
		} elsif(lc($src) eq lc($target)) {
			$tuser = $user;
			$tnick = $src;
		} elsif($target =~ /\,/) {
			push @targets, split(',', $target);
			next;
		} elsif($target eq '') {
			# Should never happen
			# but it could, given the split above
			next;
		} else {
			$tuser = { NICK => $target };
			$tnick = $target;
		}

		my $candoOpts = { ACC => $srclevel, NOREPLY => 1, OVERRIDE_MSG => "INVITE $cn $target" };
		if(lc($src) eq lc($tnick)) {
			unless(can_do($chan, 'InviteSelf', $user, $candoOpts)) {
				push @{$errors[2]}, $tnick;
				next;
			}
		}
		else {
			unless(can_do($chan, 'INVITE', $user, $candoOpts)) {
				push @{$errors[2]}, $tnick;
				next;
			}

			unless(nickserv::is_online($tnick)) {
				push @{$errors[0]}, $tnick;
				next;
			}

			# invite is annoying, so punish them mercilessly
			return if flood_check($user, 2);
		}

		if(is_in_chan($tuser, $chan)) {
			push @{$errors[1]}, $tnick;
			next;
		}

		ircd::invite(agent($chan), $cn, $tnick); push @invited, $tnick;
		ircd::notice(agent($chan), $tnick, "\002$src\002 has invited you to \002$cn\002.")
			unless(lc($src) eq lc($tnick));
	}

	foreach my $errlist (@errors) {
		if(@$errlist > 1) {
			my $msg = shift @$errlist;
			
			foreach my $e (@$errlist) { $e = "\002$e\002" }
			
			notice($user,
				"Cannot invite ".
				enum("or", @$errlist).
				": $msg"
			);
		}
	}

	ircd::notice(agent($chan), $cn, "$src used INVITE ".join(' ', @invited))
		if (lc $user->{AGENT} eq lc $csnick)and cr_chk_flag($chan, CRF_VERBOSE) and scalar(@invited);
}

sub cs_close($$$) {
	my ($user, $chan, $reason, $type) = @_;
	# $type is a flag, either CRF_CLOSE or CRF_DRONE
	my $cn = $chan->{CHAN};
	my $oper;

	unless($oper = adminserv::can_do($user, 'SERVOP')) {
		notice($user, $err_deny);
		return;
	}

	my $rlength = length($reason);
	if($rlength >= 350) {
		notice($user, 'Close reason is too long by '. $rlength-350 .' character(s). Maximum length is 350 characters.');
		return;
	}

	if(is_registered($chan)) {
		$drop_acc->execute($cn);
		$drop_lvl->execute($cn);
		$del_close->execute($cn);
		$drop_akick->execute($cn);
		$drop_welcome->execute($cn);
		$drop_chantext->execute($cn);
		$drop_nicktext->execute($cn); # Leftover channel auths

		$set_founder->execute($oper, $cn);
	}
	else {
		$register->execute($cn, $reason, $oper);
	}
	$set_modelock->execute('+rsnt', $cn);
	do_modelock($chan);
	set_acc($oper, undef, $chan, FOUNDER);

	$set_close->execute($cn, $reason, $oper, $type);
	cr_set_flag($chan, (CRF_FREEZE | CRF_CLOSE | CRF_DRONE), 0); #unset flags
	cr_set_flag($chan, CRF_HOLD, 1); #set flags

	my $src = get_user_nick($user);
	my $time = gmtime2(time);
	my $cmsg = "is closed [$src $time]: $reason";

	if ($type == CRF_CLOSE) {
		cr_set_flag($chan, CRF_CLOSE, 1); #set flags
		clear_users($chan, "Channel $cmsg");
		ircd::settopic(agent($chan), $cn, $src, time(), "Channel $cmsg")
	}
	elsif ($type == CRF_DRONE) {
		cr_set_flag($chan, CRF_DRONE, 1); #set flags
		chan_kill($chan, "$cn $cmsg");
	}

	notice($user, "The channel \002$cn\002 is now closed.");
	services::ulog($csnick, LOG_INFO(), "closed $cn with reason: $reason", $user, $chan);
}

sub cs_clear_pre($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	my $srclevel = get_best_acc($user, $chan);

	my ($cando, $override) = can_do($chan, 'CLEAR', $user, { ACC => $srclevel });
	return 0 unless($cando);

	$get_highrank->execute($cn);
	my ($highrank_nick, $highrank_level) = $get_highrank->fetchrow_array();
	$get_highrank->finish();

	if($highrank_level > $srclevel && !$override) {
		notice($user, "$highrank_nick outranks you in $cn (level: $levels[$highrank_level])");
		return 0;
	}

	return 1;
}

sub cs_clear_users($$;$) {
	my ($user, $chan, $reason) = @_;
	my $src = get_user_nick($user);

	cs_clear_pre($user, $chan) or return;

	my $rlength = length($reason);
	if($rlength >= 350) {
		notice($user, 'Clear reason is too long by '. $rlength-350 .' character(s). Maximum length is 350 characters.');
		return;
	}

	clear_users($chan, "CLEAR USERS by \002$src\002".($reason?" reason: $reason":''));
}

sub cs_clear_modes($$;$) {
	my ($user, $chan, $reason) = @_;
	my $cn = $chan->{CHAN};
	my $src = get_user_nick($user);

	cs_clear_pre($user, $chan) or return;

	my $rlength = length($reason);
	if($rlength >= 350) {
		notice($user, 'Clear reason is too long by '. $rlength-350 .' character(s). Maximum length is 350 characters.');
		return;
	}

	my $agent = agent($chan);
	ircd::notice($agent, $cn, "CLEAR MODES by \002$src\002".($reason?" reason: $reason":''));

	$get_chanmodes->execute($cn);
	my ($curmodes) = $get_chanmodes->fetchrow_array;
	my $ml = get_modelock($chan);

	# This method may exceed the 12-mode limit
	# But it seems to succeed anyway, even with more than 12.
	my ($modes, $parms) = split(/ /, modes::merge(modes::invert($curmodes), $ml, 1). ' * *', 2);
	# we split this separately,
	# as otherwise it insists on taking the result of the split as a scalar quantity
	ircd::setmode($agent, $cn, $modes, $parms);
	do_modelock($chan);
}

sub cs_clear_ops($$;$) {
	my ($user, $chan, $reason) = @_;
	my $cn = $chan->{CHAN};
	my $src = get_user_nick($user);

	cs_clear_pre($user, $chan) or return;

	my $rlength = length($reason);
	if($rlength >= 350) {
		notice($user, 'Clear reason is too long by '. $rlength-350 .' character(s). Maximum length is 350 characters.');
		return;
	}

	clear_ops($chan);

	ircd::notice(agent($chan), $cn, "CLEAR OPS by \002$src\002".($reason?" reason: $reason":''));
	return 1;
}

sub cs_clear_bans($$;$$) {
	my ($user, $chan, $type, $reason) = @_;
	my $cn = $chan->{CHAN};
	my $src = get_user_nick($user);
	$type = 0 unless defined $type;

	cs_clear_pre($user, $chan) or return;

	my $rlength = length($reason);
	if($rlength >= 350) {
		notice($user, 'Clear reason is too long by '. $rlength-350 .' character(s). Maximum length is 350 characters.');
		return;
	}

	clear_bans($chan, $type);

	ircd::notice(agent($chan), $cn, "CLEAR BANS by \002$src\002".($reason?" reason: $reason":''));
}

sub cs_welcome_pre($$) {
	my ($user, $chan) = @_;

	return can_do($chan, 'WELCOME', $user);
}

sub cs_welcome_add($$$) {
	my ($user, $chan, $msg) = @_;
	my $src = get_best_acc($user, $chan, 1);
	my $cn = $chan->{CHAN};

	cs_welcome_pre($user, $chan) or return;

	my $mlength = length($msg);
	if($mlength >= 350) {
		notice($user, 'Welcome Message is too long by '. $mlength-350 .' character(s). Maximum length is 350 characters.');
		return;
	}

	$count_welcome->execute($cn);
	my $count = $count_welcome->fetchrow_array;
	if ($count >= 5) {
		notice($user, 'There is a maximum of five (5) Channel Welcome Messages.');
		return;
	}

	$add_welcome->execute($cn, ++$count, $src, $msg);

	notice($user, "Welcome message number $count for \002$cn\002 set to:", "  $msg");
}

sub cs_welcome_list($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	cs_welcome_pre($user, $chan) or return;

	$list_welcome->execute($cn);
	
	my @data;
	
	while(my ($id, $time, $adder, $msg) = $list_welcome->fetchrow_array) {
		push @data, ["$id.", $adder, gmtime2($time), $msg];
	}
	$list_welcome->finish();

	notice($user, columnar {TITLE => "Welcome message list for \002$cn\002:", DOUBLE=>1,
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data);
}

sub cs_welcome_del($$$) {
	my ($user, $chan, $id) = @_;
	my $cn = $chan->{CHAN};

	cs_welcome_pre($user, $chan) or return;

	if ($del_welcome->execute($cn, $id) == 1) {
		notice($user, "Welcome Message \002$id\002 deleted from \002$cn\002");
		$consolidate_welcome->execute($cn, $id);
	}
	else {
		notice($user,
			"Welcome Message number $id for \002$cn\002 does not exist.");
	}
}

sub cs_alist($$;$) {
	my ($user, $chan, $mask) = @_;
	my $cn = $chan->{CHAN};

	chk_registered($user, $chan) or return;

	my $slevel = get_best_acc($user, $chan);

	can_do($chan, 'ACCLIST', $user, { ACC => $slevel }) or return;

	my @reply;

	if($mask) {
		my ($mnick, $mident, $mhost) = glob2sql(parse_mask($mask));
		$mnick = '%' if($mnick eq '');
		$mident = '%' if($mident eq '');
		$mhost = '%' if($mhost eq '');

		$get_acc_list2_mask->execute($mnick, $cn, $mnick, $mident, $mhost);
		while(my ($nick, $adder, $level, $time, $last_used, $ident, $vhost) = $get_acc_list2_mask->fetchrow_array) {
			push @reply, "*) $nick ($ident\@$vhost) Rank: ".$levels[$level] . ($adder ? ' Added by: '.$adder : '');
			push @reply, '      '.($time ? 'Date/time added: '. gmtime2($time).' ' : '').
				($last_used ? 'Last used '.time_ago($last_used).' ago' : '') if ($time or $last_used);
		}
		$get_acc_list2_mask->finish();
	} else {
		$get_acc_list2->execute($cn);
		while(my ($nick, $adder, $level, $time, $last_used, $ident, $vhost) = $get_acc_list2->fetchrow_array) {
			push @reply, "*) $nick ($ident\@$vhost) Rank: ".$levels[$level] . ($adder ? ' Added by: '.$adder : '');
			push @reply, '      '.($time ? 'Date/time added: '. gmtime2($time).' ' : '').
				($last_used ? 'Last used '.time_ago($last_used).' ago' : '') if ($time or $last_used);
		}
		$get_acc_list2->finish();
	}

	notice($user, "Access list for \002$cn\002:", @reply);

	return;
}

sub cs_banlist($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};
	can_do($chan, 'UnbanSelf', $user, { NOREPLY => 1 }) or can_do($chan, 'BAN', $user) or return;

	my $i = 0; my @data;
	$list_bans->execute($cn, 0);
	while(my ($mask, $setter, $time) = $list_bans->fetchrow_array()) {
		push @data, ["\002".++$i."\002", sql2glob($mask), $setter, ($time ? gmtime2($time) : '')];
	}

	notice($user, columnar {TITLE => "Ban list of \002$cn\002:", DOUBLE=>1,
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data);
}

sub cs_unban($$@) {
	my ($user, $chan, @parms) = @_;
	my $cn = $chan->{CHAN};

	my $self;
	$self = 1 if ( (scalar(@parms) == 1) and ( lc($parms[0]) eq lc(get_user_nick($user)) ) );
	if ($parms[0] eq '*') {
		cs_clear_bans($user, $chan);
		return;
	}
	else {
		can_do($chan, ($self ? 'UnbanSelf' : 'UNBAN'), $user) or return;
	}

	my (@userlist, @masklist);
	foreach my $parm (@parms) {
		if(valid_nick($parm)) {
			my $tuser = ($self ? $user : { NICK => $parm });
			unless(get_user_id($tuser)) {
				notice($user, "No such user: \002$parm\002");
				next;
			}
			push @userlist, $tuser;
		} elsif($parm =~ /^[0-9\.,-]+$/) {
			foreach my $num (makeSeqList($parm)) {
				push @masklist, get_ban_num($chan, $num);
			}
		} else {
			push @masklist, $parm;
		}
	}

	if(scalar(@userlist)) {
		unban_user($chan, @userlist);
		notice($user, "All bans affecting " .
			( $self ? 'you' : enum( 'and', map(get_user_nick($_), @userlist) ) ) .
			" on \002$cn\002 have been removed.");
	}
	if(scalar(@masklist)) {
		ircd::ban_list(agent($chan), $cn, -1, 'b', @masklist);
		notice($user, "The following bans have been removed: ".join(' ', @masklist))
			if scalar(@masklist);
	}
}

sub cs_updown($$@) {
	my ($user, $cmd, @chans) = @_;
	return cs_updown2($user, $cmd, { CHAN => shift @chans }, @chans)
		if (defined($chans[1]) and $chans[1] !~ "^\#" and $chans[0] =~ "^\#");
	
	@chans = get_user_chans($user) 
		unless (@chans);

	if (uc($cmd) eq 'UP') {
		foreach my $cn (@chans) {
			next unless ($cn =~ /^\#/);
			my $chan = { CHAN => $cn };
			next if cr_chk_flag($chan, (CRF_DRONE | CRF_CLOSE | CRF_FREEZE), 1);
			chanserv::set_modes($user, $chan, chanserv::get_best_acc($user, $chan));
		}
	}
	elsif (uc($cmd) eq 'DOWN') {
		foreach my $cn (@chans) {
			next unless ($cn =~ /^\#/);
			chanserv::unset_modes($user, { CHAN => $cn });
		}
	}
}

sub cs_updown2($$$@) {
	my ($user, $cmd, $chan, @targets) = @_;
	no warnings 'void';
	my $agent = $user->{AGENT} or $csnick;
	my $cn = $chan->{CHAN};

	return unless chk_registered($user, $chan);
	if (cr_chk_flag($chan, CRF_FREEZE())) {
		notice($user, "\002$cn\002 is frozen and access suspended.");
		return;
	}

	my $acc = get_best_acc($user, $chan);
	return unless(can_do($chan, 'UPDOWN', $user, { ACC => $acc }));

	my $updown = ((uc($cmd) eq 'UP') ? 1 : 0);

	my ($override, $check_override);
	my (@list, $count);
	foreach my $target (@targets) {

		my $tuser = { NICK => $target };

		unless(is_in_chan($tuser, $chan)) {
			notice($user, "\002$target\002 is not in \002$cn\002.");
			next;
		}

		if($updown) {
			push @list, $target;
			chanserv::set_modes($tuser, $chan, chanserv::get_best_acc($tuser, $chan));
		}
		else {
			my $top = get_op($tuser, $chan);
			unless($top) {
				notice($user, "\002$target\002 is already deopped in \002$cn\002.");
				next;
			}

			if(!$override and get_best_acc($tuser, $chan) > $acc) {
				unless($check_override) {
					$override = adminserv::can_do($user, 'SUPER');
					$check_override = 1;
				}
				if($check_override and !$override) {
					notice($user, "\002$target\002 outranks you in \002$cn\002.");
					next;
				}
			}
			push @list, $target;
			chanserv::unset_modes($tuser, { CHAN => $cn });
		}
		$count++;
	}

	my $src = get_user_nick($user);
	ircd::notice(agent($chan), '%'.$cn, "$src used $cmd ".join(' ', @list))
		if (lc $user->{AGENT} eq lc $csnick) and cr_chk_flag($chan, CRF_VERBOSE);
}

sub cs_getkey($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	can_do($chan, 'GETKEY', $user) or return;

	$get_chanmodes->execute($cn);
	my $modes = $get_chanmodes->fetchrow_array; $get_chanmodes->finish();

	if(my $key = modes::get_key($modes)) {
		notice($user, "Channel key for \002$cn\002: $key");
	}
	else {
		notice($user, "\002$cn\002 has no channel key.");
	}
}

sub cs_auth($$$@) {
	my ($user, $chan, $cmd, @args) = @_;
	my $cn = $chan->{CHAN};
	$cmd = lc $cmd;

	return unless chk_registered($user, $chan);
	return unless can_do($chan, 'AccChange', $user);
	my $userlevel = get_best_acc($user, $chan);
	if($cmd eq 'list') {
		my @data;
		$list_auth_chan->execute($cn);
		while(my ($nick, $data) = $list_auth_chan->fetchrow_array()) {
			my ($adder, $old, $level, $time) = split(/:/, $data);
			push @data, ["\002$nick\002", $levels[$level], $adder, gmtime2($time)];
		}
		if ($list_auth_chan->rows()) {
			notice($user, columnar {TITLE => "Pending authorizations for \002$cn\002:",
				NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data);
		}
		else {
			notice($user, "There are no pending authorizations for \002$cn\002");
		}
		$list_auth_chan->finish();
	}
	elsif($cmd eq 'remove' or $cmd eq 'delete' or $cmd eq 'del') {
	my ($nick, $adder, $old, $level, $time);
	my $parm = shift @args;
		if(misc::isint($parm) and ($nick, $adder, $old, $level, $time) = get_auth_num($cn, $parm))
		{
		}
		elsif (($adder, $old, $level, $time) = get_auth_nick($cn, $parm))
		{
			$nick = $parm;
		}
		unless ($nick) {
		# This should normally be an 'else' as the elsif above should prove false
		# For some reason, it doesn't work. the unless ($nick) fixes it.
		# It only doesn't work for numbered entries
			notice($user, "There is no entry for \002$parm\002 in \002$cn\002's AUTH list");
			return;
		}
		$nickserv::del_auth->execute($nick, $cn); $nickserv::del_auth->finish();
		my $log_str = "deleted AUTH entry $cn $nick $levels[$level]";
		my $src = get_user_nick($user);
		notice($user, "You have $log_str");
		ircd::notice(agent($chan), '%'.$cn, "has \002$src\002 has $log_str")
			if cr_chk_flag($chan, CRF_VERBOSE);
		services::ulog($chanserv::csnick, LOG_INFO(), "has $log_str", $user, $chan);
	}
	else {
		notice($user, "Unknown AUTH command \002$cmd\002");
	}
}

sub cs_mode($$$@) {
	my ($user, $chan, $modes_in, @parms_in) = @_;
	can_do($chan, 'MODE', $user) or return undef;
	($modes_in, @parms_in) = validate_chmodes($modes_in, @parms_in);

	my %permhash = (
		'q' => 'OWNER',
		'a' => 'ADMIN',
		'o' => 'OP',
		'h' => 'HALFOP',
		'v' => 'VOICE',
	);
	my $sign = '+'; my $cn = $chan->{CHAN};
	my ($modes_out, @parms_out, @bans);
	foreach my $mode (split(//, $modes_in)) {
		$sign = $mode if $mode =~ /[+-]/;
		if ($permhash{$mode}) {
			my $parm = shift @parms_in;
			cs_setmodes($user, ($sign eq '-' ? 'de' : '').$permhash{$mode}, $chan, $parm);
		}
		elsif ($mode eq 'b') {
			my $parm = shift @parms_in;
			if($sign eq '-') {
				$parm = '-'.$parm;
			}
			push @bans, $parm;
		}
		elsif($mode =~ /[eIlLkjf]/) {
			$modes_out .= $mode;
			push @parms_out, shift @parms_in;
		} else {
			$modes_out .= $mode;
		}
	}

	if(scalar(@bans)) {
		cs_ban($user, $chan, undef, @bans);
	}
	return if $modes_out =~ /^[+-]*$/;
	ircd::setmode(agent($chan), $chan->{CHAN}, $modes_out, join(' ', @parms_out));
	do_modelock($chan, $modes_out.' '.join(' ', @parms_out));

	$modes_out =~ s/^[+-]*([+-].*)$/$1/;
	ircd::notice(agent($chan), '%'.$cn, get_user_nick($user).' used MODE '.join(' ', $modes_out, @parms_out))
		if (lc $user->{AGENT} eq lc $csnick) and cr_chk_flag($chan, CRF_VERBOSE);
}

sub cs_copy($$@) {
	my ($user, $chan1, @args) = @_;
	my $cn1 = $chan1->{CHAN};
	my $cn2;
	my $type;
	if($args[0] =~ /^#/) {
		$cn2 = shift @args;
		$type = 'all';
	}
	if($args[0] =~ /(?:acc(?:ess)?|akick|levels|all)/i) {
		$type = shift @args;
		$cn2 = shift @args unless $cn2;
	}
	my $rank;
	if($type =~ /^acc(?:ess)?/i) {
		if($cn2 =~ /^#/) {
			$rank = shift @args;
		} else {
			$rank = $cn2;
			$cn2 = shift @args;
		}
	}
	unless(defined $cn2 and defined $type) {
		notice($user, 'Unknown COPY command', 'Syntax: COPY #chan1 [type] #chan2');
	}
	my $chan2 = { CHAN => $cn2 };
	if(lc($cn1) eq lc($cn2)) {
		notice($user, "You cannot copy a channel onto itself.");
	}
	unless(is_registered($chan1)) {
		notice($user, "Source channel \002$cn1\002 must be registered.");
		return;
	}
	can_do($chan1, 'COPY', $user) or return undef;
	if(lc $type eq 'all') {
		if(is_registered($chan2)) {
			notice($user, "When copying all channel details, destination channel cannot be registered.");
			return;
		} elsif(!(get_op($user, $chan2) & ($opmodes{o} | $opmodes{a} | $opmodes{q}))) {
			# This would be preferred to be a 'opmode_mask' or something
			# However that might be misleading due to hop not being enough to register
			notice($user, "You must have channel operator status to register \002$cn2\002.");
			return;
		} else {
			cs_copy_chan_all($user, $chan1, $chan2);
			return;
		}
	} else {
		unless(is_registered($chan2)) {
			notice($user, "When copying channel lists, destination channel must be registered.");
			return;
		}
		can_do($chan2, 'COPY', $user) or return undef;
	}
	if(lc $type eq 'akick') {
		cs_copy_chan_akick($user, $chan1, $chan2);
	} elsif(lc $type eq 'levels') {
		cs_copy_chan_levels($user, $chan1, $chan2);
	} elsif($type =~ /^acc(?:ess)?/i) {
		cs_copy_chan_acc($user, $chan1, $chan2, xop_byname($rank));
	}
}

sub cs_copy_chan_all($$$) {
	my ($user, $chan1, $chan2) = @_;
	cs_copy_chan_chanreg($user, $chan1, $chan2);
	cs_copy_chan_levels($user, $chan1, $chan2);
	cs_copy_chan_acc($user, $chan1, $chan2);
	cs_copy_chan_akick($user, $chan1, $chan2);
	return;
}

sub cs_copy_chan_chanreg($$$) {
	my ($user, $chan1, $chan2) = @_;
	my $cn1 = $chan1->{CHAN};
	my $cn2 = $chan2->{CHAN};

	copy_chan_chanreg($cn1, $cn2);
	botserv::bot_join($chan2) unless (lc(agent($chan2)) eq lc($csnick) );
	do_modelock($chan2);
	notice($user, "Registration for \002$cn1\002 copied to \002$cn2\002");

	my $log_str = "copied the channel registration for \002$cn1\002 to \002$cn2\002";
	services::ulog($chanserv::csnick, LOG_INFO(), "$log_str", $user, $chan1);

	my $src = get_user_nick($user);
	ircd::notice(agent($chan1), '%'.$cn1, "\002$src\002 $log_str")
		if cr_chk_flag($chan1, CRF_VERBOSE);
	ircd::notice(agent($chan2), '%'.$cn2, "\002$src\002 $log_str")
		if cr_chk_flag($chan2, CRF_VERBOSE);
}

sub cs_copy_chan_acc($$$;$) {
	my ($user, $chan1, $chan2, $level) = @_;
	my $cn1 = $chan1->{CHAN};
	my $cn2 = $chan2->{CHAN};

	copy_chan_acc($cn1, $cn2, $level);

	unless(cr_chk_flag($chan2, CRF_NEVEROP)) {
		$get_chan_users->execute($cn2); my @targets;
		while (my ($nick, $uid) = $get_chan_users->fetchrow_array()) {
			push @targets, $nick unless nr_chk_flag_user({ NICK => $nick, ID => $uid }, NRF_NEVEROP);
		}
		cs_updown2($user, 'UP', $chan2, @targets);
	}

	notice($user, "Access list for \002$cn1\002 ".
		($level ? "(rank: \002".$plevels[$level + $plzero]."\002) " : '').
		"copied to \002$cn2\002");

	my $log_str = "copied the channel access list for \002$cn1\002 ".
		($level ? "(rank: \002".$plevels[$level + $plzero]."\002) " : '').
		"to \002$cn2\002";
	services::ulog($chanserv::csnick, LOG_INFO(), "$log_str", $user, $chan1);

	my $src = get_user_nick($user);
	ircd::notice(agent($chan1), '%'.$cn1, "\002$src\002 $log_str")
		if cr_chk_flag($chan1, CRF_VERBOSE);
	ircd::notice(agent($chan2), '%'.$cn2, "\002$src\002 $log_str")
		if cr_chk_flag($chan2, CRF_VERBOSE);
}

sub cs_copy_chan_levels($$$) {
	my ($user, $chan1, $chan2) = @_;
	my $cn1 = $chan1->{CHAN};
	my $cn2 = $chan2->{CHAN};

	copy_chan_levels($cn1, $cn2);
	notice($user, "LEVELS for \002$cn1\002 copied to \002$cn2\002");

	my $log_str = "copied the LEVELS list for \002$cn1\002 to \002$cn2\002";
	services::ulog($chanserv::csnick, LOG_INFO(), "$log_str", $user, $chan1);

	my $src = get_user_nick($user);
	ircd::notice(agent($chan1), '%'.$cn1, "\002$src\002 $log_str")
		if cr_chk_flag($chan1, CRF_VERBOSE);
	ircd::notice(agent($chan2), '%'.$cn2, "\002$src\002 $log_str")
		if cr_chk_flag($chan2, CRF_VERBOSE);
}

sub cs_copy_chan_akick($$$) {
	my ($user, $chan1, $chan2) = @_;
	my $cn1 = $chan1->{CHAN};
	my $cn2 = $chan2->{CHAN};

	copy_chan_akick($cn1, $cn2);
	notice($user, "Channel AKick list for \002$cn1\002 copied to \002$cn2\002");

	my $log_str = "copied the AKick list for \002$cn1\002 to \002$cn2\002";
	services::ulog($chanserv::csnick, LOG_INFO(), "$log_str", $user, $chan1);

	my $src = get_user_nick($user);
	ircd::notice(agent($chan1), '%'.$cn1, "\002$src\002 $log_str")
		if cr_chk_flag($chan1, CRF_VERBOSE);
	ircd::notice(agent($chan2), '%'.$cn2, "\002$src\002 $log_str")
		if cr_chk_flag($chan2, CRF_VERBOSE);
}

sub cs_mlock($$$@) {
	my ($user, $chan, $cmd, @args) = @_;
	my $cn = $chan->{CHAN};
	# does this need its own privilege now?
	can_do($chan, 'SET', $user) or return;
	my $modes;
	if(scalar(@args)) {
		my ($modes_in, @parms_in) = validate_chmodes(shift @args, @args);
		$modes = $modes_in.' '.join(' ', @parms_in);
		@args = undef;
	}

	my $cur_modelock = get_modelock($chan);
	if(lc $cmd eq 'add') {
		$modes = modes::merge($cur_modelock, $modes, 1);
		$modes = sanitize_mlockable($modes);
		$set_modelock->execute($modes, $cn);
	}
	elsif(lc $cmd eq 'del') {
		$modes =~ s/[+-]//g;
		$modes = modes::add($cur_modelock, "-$modes", 1);
		$set_modelock->execute($modes, $cn);
	}
	elsif(lc $cmd eq 'set') {
		$modes = modes::merge($modes, "+r", 1);
		$set_modelock->execute($modes, $cn);
	}
	elsif(lc $cmd eq 'reset') {
		$set_modelock->execute(services_conf_default_channel_mlock, $cn);
	} else {
		notice($user, "Unknown MLOCK command \"$cmd\"");
		return;
	}

	notice($user, "Mode lock for \002$cn\002 has been set to: \002$modes\002");
	do_modelock($chan);

=cut
	notice($user, columnar {TITLE => "Ban list of \002$cn\002:", DOUBLE=>1,
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data);
=cut
}

use SrSv::MySQL::Stub {
	getChanUsers => ['COLUMN', "SELECT user.nick FROM chanuser JOIN user ON (user.id=chanuser.nickid)
		WHERE chanuser.chan=? AND chanuser.joined=1"]
};

sub cs_resync($@) {
	my ($user, @cns) = @_;
	foreach my $cn (@cns) {
		my $chan = { CHAN => $cn };
		next unless cs_clear_ops($user, $chan, 'Resync');
		cs_updown2($user, 'up', $chan, getChanUsers($cn));
		if(can_do($chan, 'AKickEnforce', $user, { OVERRIDE_MSG => "AKICK $cn ENFORCE", NOREPLY => 1 })) {
			cs_akick_enforce($user, $chan);
		}
	}
}

sub cs_join($@) {
	my ($user, @cns) = @_;
	my @reply;
	my @out_cns;
	foreach my $cn (@cns) {
		if($cn =~ /,/) {
			push @cns, split(',', $cn);
		}
		elsif($cn eq '') {
			next;
		}
		my $chan = { CHAN => $cn };
		my $cando_opts = { NOREPLY => 1 };
		if(check_akick($user, $chan, 1)) {
			push @reply, "You are banned from $cn";
			next;
		} elsif(!can_do($chan, 'JOIN', $user, $cando_opts)) {
			push @reply, "$cn is a private channel.";
			next;
		}
		if(is_in_chan($user, $chan)) {
			next;
		}
		if(can_do($chan, 'InviteSelf', $user, $cando_opts)) {
			cs_invite($user, $chan, $user);
		}
		push @out_cns, $cn;
		
	}
	ircd::svsjoin(get_user_agent($user), get_user_nick($user), @out_cns) if scalar @out_cns;
	notice($user, @reply) if scalar @reply;
}

sub cs_topic($$@) {
	my ($user, $cn, @args) = @_;
	my ($chan, $msg) = ($cn->{CHAN}, join(" ", @args));
	can_do($cn, 'SETTOPIC', $user) or return undef;
	ircd::settopic(agent($cn), $chan, get_user_nick($user), time, ($msg =~ /^none/i ? "" : $msg));
}   

### MISCELLANEA ###

# these are helpers and do NOT check if $cn1 or $cn2 is reg'd
sub copy_chan_acc($$;$) {
	my ($cn1, $cn2, $level) = @_;
	if($level) {
		$copy_acc_rank->execute($cn2, $cn1, $level);
		$copy_acc_rank->finish();
	} else {
		$get_founder->execute($cn2);
		my ($founder) = $get_founder->fetchrow_array;
		$get_founder->finish();

		$copy_acc->execute($cn2, $cn1, $founder);
		$copy_acc->finish();
	}
}

sub copy_chan_akick($$;$) {
	my ($cn1, $cn2) = @_;
	$copy_akick->execute($cn2, $cn1);
	$copy_akick->finish();
	copy_chan_acc($cn1, $cn2, -1);
}

sub copy_chan_levels($$) {
	my ($cn1, $cn2) = @_;
	$copy_levels->execute($cn2, $cn1);
	$copy_levels->finish();
}

sub copy_chan_chanreg($$) {
	my ($cn1, $cn2) = @_;
	$get_founder->execute($cn1);
	my ($founder) = $get_founder->fetchrow_array;
	$get_founder->finish();
	set_acc($founder, undef, { CHAN => $cn2 }, FOUNDER);
	$copy_chanreg->execute($cn2, $cn1);
	$copy_chanreg->finish();
}

sub do_welcome($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};
	
	$get_welcomes->execute($cn);
	if($get_welcomes->rows) {
		my @welcomes;
		while(my ($msg) = $get_welcomes->fetchrow_array) {
			push @welcomes, (cr_chk_flag($chan, CRF_WELCOMEINCHAN) ? '' : "[$cn] " ).$msg;
		}
		if(cr_chk_flag($chan, CRF_WELCOMEINCHAN)) {
			ircd::privmsg(agent($chan), $cn, @welcomes);
		} else {
			notice($user, @welcomes);
		}
	}
	$get_welcomes->finish();
}

sub do_greet($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};

	if(can_do($chan, 'GREET', $user)) {
		my $src = get_user_nick($user);
		$nickserv::get_greet->execute(get_user_id($user));
		my ($greet) = $nickserv::get_greet->fetchrow_array();
		$nickserv::get_greet->finish();
		ircd::privmsg(agent($chan), $cn, "[\002$src\002] $greet") if $greet;
	}
}

sub chk_registered($$) {
	my ($user, $chan) = @_;

	unless(is_registered($chan)) {
		my $cn = $chan->{CHAN};
		
		notice($user, "The channel \002$cn\002 is not registered.");
		return 0;
	}

	return 1;
}

sub make_banmask($$;$) {
	my ($chan, $tuser, $type) = @_;
	my $nick = get_user_nick($tuser);

	my ($ident, $vhost) = get_vhost($tuser);
	no warnings 'misc';
	my ($nick, $ident, $vhost) = make_hostmask(get_bantype($chan), $nick, $ident, $vhost);
	if($type eq 'q') {
		$type = '~q:';
	} elsif($type eq 'n') {
		$type = '~n:';
	} else {
		$type = '';
	}
	return $type."$nick!$ident\@$vhost";
}

sub kickban($$$$;$$) {
	my ($chan, $user, $mask, $reason, $noflush) = @_;

	my $cn = $chan->{CHAN};
	my $nick;
	$nick = get_user_nick($user) if ($user);

	if (!$user && !$mask) {
		return;
	}

	return 0 if $user && adminserv::is_service($user);

	my $agent = agent($chan);

	unless($mask) {
		$mask = make_banmask($chan, $user);
	}

	enforcer_join($chan) if (get_user_count($chan) <= 1);
	#ircd::setmode($agent, $cn, '+b', $mask);
	tempban($chan, [$mask, get_bantime($chan)]);

	ircd::flushmodes() unless $noflush;
	ircd::kick($agent, $cn, $nick, $reason) if ($nick);
	return 1;
}

sub kickban_multi($$$) {
	my ($chan, $users, $reason) = @_;
	my $cn = $chan->{CHAN};
	my $agent = agent($chan);

	enforcer_join($chan);
	ircd::setmode($agent, $cn, '+b', '*!*@*');
	ircd::flushmodes();

	foreach my $user (@$users) {
		next if adminserv::is_ircop($user) or adminserv::is_svsop($user, adminserv::S_HELP());
		ircd::kick($agent, $cn, get_user_nick($user), $reason);
	}
}

sub clear_users($$)  {
	my ($chan, $reason) = @_;
	my $cn = $chan->{CHAN};
	my $agent = agent($chan);
	my $i;

	enforcer_join($chan);
	ircd::setmode($agent, $cn, '+b', '*!*@*');
	ircd::flushmodes();
	$get_chan_users->execute($cn);
	while(my ($nick, $uid) = $get_chan_users->fetchrow_array) {
		my $user = { NICK => $nick, ID => $uid };
		ircd::kick($agent, $cn, $nick, $reason)
			unless adminserv::is_ircop($user) or adminserv::is_svsop($user, adminserv::S_HELP());
		$i++;
	}

	return $i;
}

sub kickmask($$$$)  {
	my ($chan, $mask, $reason, $ban) = @_;
	my $cn = $chan->{CHAN};
	my $agent = agent($chan);

	my ($nick, $ident, $host) = glob2sql(parse_mask($mask));
	$nick = '%' if ($nick eq '');
	$ident = '%' if ($ident eq '');
	$host = '%' if ($host eq '');

	if ($ban) {
		my $banmask = $nick.'!'.$ident.'@'.$host;
		$banmask =~ tr/%_/*?/;
		ircd::setmode($agent, $cn, '+b', $banmask);
		ircd::flushmodes();
	}

	my $i;
	$get_chan_users_mask->execute($cn, $nick, $ident, $host, $host, $host);
	while(my ($nick, $uid) = $get_chan_users_mask->fetchrow_array) {
		my $user = { NICK => $nick, ID => $uid };
		ircd::kick($agent, $cn, $nick, $reason)
			unless adminserv::is_service($user);
		$i++;
	}
	$get_chan_users_mask->finish();

	return $i;
}

sub kickmask_noacc($$$$)  {
	my ($chan, $mask, $reason, $ban) = @_;
	my $cn = $chan->{CHAN};
	my $agent = agent($chan);

	my ($nick, $ident, $host) = glob2sql(parse_mask($mask));
	$nick = '%' if ($nick eq '');
	$ident = '%' if ($ident eq '');
	$host = '%' if ($host eq '');

	if ($ban) {
		my $banmask = $nick.'!'.$ident.'@'.$host;
		$banmask =~ tr/%_/*?/;
		ircd::setmode($agent, $cn, '+b', $banmask);
		ircd::flushmodes();
	}

	my $i;
	$get_chan_users_mask_noacc->execute($cn, $nick, $ident, $host, $host, $host);
	while(my ($nick, $uid) = $get_chan_users_mask_noacc->fetchrow_array) {
		my $user = { NICK => $nick, ID => $uid };
		ircd::kick($agent, $cn, $nick, $reason)
			unless adminserv::is_service($user);
		$i++;
	}
	$get_chan_users_mask_noacc->finish();

	return $i;
}

sub clear_ops($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};
	my @modelist;
	my $agent = agent($chan);

	$get_chan_users->execute($cn);
	while(my ($nick, $uid) = $get_chan_users->fetchrow_array) {
		my $user = { NICK => $nick, ID => $uid };
		my $opmodes = get_op($user, $chan);
		for(my $i; $i < 5; $i++) {
			if($opmodes & 2**$i) {
				push @modelist, ['-'.$opmodes[$i], $nick];
			}
		}
	}

	ircd::setmode2($agent, $cn, @modelist);
}

sub clear_bans($;$) {
	my ($chan, $type) = @_;
	my $cn = $chan->{CHAN};
	my @args = ();
	my $agent = agent($chan);
	$type = 0 unless defined $type;
	my $mode = ($type == 128 ? 'e' : 'b');

	my @banlist = ();
	$get_all_bans->execute($cn, $type);
	while(my ($mask) = $get_all_bans->fetchrow_array) {
		$mask =~ tr/\%\_/\*\?/;
		push @banlist, $mask;
	}

	ircd::ban_list($agent, $cn, -1, $mode, @banlist);
	ircd::flushmodes();
}

sub unban_user($@) {
	my ($chan, @userlist) = @_;
	my $cn = $chan->{CHAN};
	my $count;
	if (defined(&ircd::unban_nick)) {
		my @nicklist;
		foreach my $tuser (@userlist) {
			push @nicklist, get_user_nick($tuser);
		}
		ircd::unban_nick(agent($chan), $cn, @nicklist);
		return scalar(@nicklist);
	}

	foreach my $tuser (@userlist) {
		my $tuid;
		unless($tuid = get_user_id($tuser)) {
			next;
		}

		my (@bans);
		# We don't handle extended bans. Yet.
		$find_bans_chan_user->execute($cn, $tuid, 0);
		while (my ($mask) = $find_bans_chan_user->fetchrow_array) {
			$mask =~ tr/\%\_/\*\?/;
			push @bans, $mask;
		}
		$find_bans_chan_user->finish();

		ircd::ban_list(agent($chan), $cn, -1, 'b', @bans) if scalar(@bans);
		$delete_bans_chan_user->execute($cn, $tuid, 0); $delete_bans_chan_user->finish();
		$count++;
	}
	return $count;
}

sub chan_kill($$;$)  {
	my ($chan, $reason, $tusers) = @_;
	my $cn = $chan->{CHAN};
	my $agent = agent($chan);
	my $i;
	
	enforcer_join($chan);
	if ($tusers) {
		foreach my $tuser (@$tusers) {
			$tuser->{ID} = $tuser->{__ID} if defined($tuser->{__ID}); # user_join_multi does this.
			nickserv::kline_user($tuser, services_conf_chankilltime, $reason)
				unless adminserv::is_ircop($tuser) or adminserv::is_svsop($tuser, adminserv::S_HELP());
			$i++;
		}
	}
	else {
		$get_chan_users->execute($cn);
		while(my ($nick, $uid) = $get_chan_users->fetchrow_array) {
			my $tuser = { NICK => $nick, ID => $uid, AGENT => $agent };
			nickserv::kline_user($tuser, services_conf_chankilltime, $reason)
				unless adminserv::is_ircop($tuser) or adminserv::is_svsop($tuser, adminserv::S_HELP());
			$i++;
		}
	}

	return $i;
}

sub do_nick_akick($$;$) {
	my ($tuser, $chan, $root) = @_;
	my $cn = $chan->{CHAN};
	unless(defined($root)) {
		(undef, $root) = get_best_acc($tuser, $chan, 2);
	}

	$get_nick_akick->execute($cn, $root);
	my ($reason) = $get_nick_akick->fetchrow_array(); $get_nick_akick->finish();

	return 0 if adminserv::is_svsop($tuser, adminserv::S_HELP());
	if(defined($reason) && $reason =~ /\|/) {
		($reason, undef) = split(/ ?\| ?/, $reason, 2);
	}
	kickban($chan, $tuser, undef, "User has been banned from ".$cn.($reason?": $reason":''));
}

sub check_akick($$;$) {
	my ($user, $chan, $check_only) = @_;

	if(adminserv::is_svsop($user, adminserv::S_HELP())) {
		return 0;
	}
	my ($acc, $root) = get_best_acc($user, $chan, 2);
	if ($acc == -1) {
		do_nick_akick($user, $chan, $root) unless $check_only;
		return 1;
	}
	my $cn = $chan->{CHAN};
	my $uid = get_user_id($user);
	unless($acc) {
		$get_akick->execute($uid, $cn);
		if(my @akick = $get_akick->fetchrow_array) {
			akickban($cn, @akick) unless $check_only;
			return 1;
		}
	}
	return 0;
}

sub do_status($$;$) {
	my ($user, $chan, $check_only) = @_;

	return 0 if cr_chk_flag($chan, (CRF_CLOSE | CRF_DRONE));

	my $nick = get_user_nick($user);

	if(check_akick($user, $chan, $check_only)) {
		return 0;
	}
	my ($acc, $root) = get_best_acc($user, $chan, 2);
	my ($accnick, $override) = can_do($chan, 'JOIN', $user, { ACC => $acc, NOREPLY => 1 });
	unless ($acc > 0 || $override) {
		if (clones_exist ($user, $chan) && !adminserv::is_service($user)) {
			my $mask = make_banmask($chan, $user);
			my $cn = $chan->{CHAN};

			tempban($chan, [ $mask, 60 ]);
			ircd::kick(agent($chan), $cn, $nick, "No clones allowed in this channel.");

			return 0;
		}
	}
	
	if(!$accnick && !$override) {
		kickban($chan, $user, undef, 'This is a private channel.')
			unless $check_only;
		return 0;
	}

	if( !$check_only && is_registered($chan) &&
		!cr_chk_flag($chan, (CRF_CLOSE | CRF_DRONE)) )
	{
		my $neverop = (is_neverop_user($user) || cr_chk_flag($chan, CRF_NEVEROP, 1));
		my $no_deop = cr_chk_flag($chan, CRF_SPLITOPS, 0);
		my $op_anyway = 0;
		if($neverop && cr_chk_flag($chan, CRF_AUTOVOICE, 1) && $acc > 2) {
			$acc = 2;
			$no_deop = 0;
			$op_anyway = 1;
		}
		set_modes($user, $chan, $acc,
			# $acc == 3 is +h
			# this probably needs to be configurable for ports
			# also Unreal may [optionally] set +q on join.
			$no_deop,
			!$neverop || $op_anyway,
		);
	}

	return 1;
}

sub akick_alluser($) {
	my ($user) = @_;
	my $uid = get_user_id($user);

	$get_akick_alluser->execute($uid);
	while(my @akick = $get_akick_alluser->fetchrow_array) {
		akickban(@akick);
	}
}

sub akick_allchan($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};

	$get_akick_allchan->execute($cn);
	while(my @akick = $get_akick_allchan->fetchrow_array) {
		akickban($cn, @akick);
	}
}

sub akickban(@) {
	my ($cn, $knick, $bnick, $ident, $host, $reason, $bident) = @_;

	my $target = { NICK => $knick };
	my $chan = { CHAN => $cn };
	return 0 if adminserv::is_svsop($target, adminserv::S_HELP());

	if($bident) {
		($bnick, $ident, $host) = make_hostmask(get_bantype($chan), $knick, $bident, $host);
	} elsif($host =~ /^(\d{1,3}\.){3}\d{1,3}$/) {
		($bnick, $ident, $host) = make_hostmask(4, $knick, $bident, $host);
	} else {
		$bnick =~ tr/\%\_/\*\?/;
		$ident =~ tr/\%\_/\*\?/;
		$host =~ tr/\%\_/\*\?/;
	}

	if(defined($reason) && $reason =~ /\|/) {
		($reason, undef) = split(/ ?\| ?/, $reason, 2);
	}

	return kickban($chan, $target, "$bnick!$ident\@$host", "User has been banned from ".$cn.($reason?": $reason":''));
}

sub notice_all_nicks($$$) {
	my ($user, $nick, $msg) = @_;
	my $src = get_user_nick($user);

	notice($user, $msg);
	foreach my $u (get_nick_user_nicks $nick) {
		notice({ NICK => $u, AGENT => $csnick }, $msg) unless lc $src eq lc $u;
	}
}

sub xop_byname($) {
	my ($name) = @_;
	my $level;

	if($name =~ /^uop$/i) { $level=1; }
	elsif($name =~ /^vop$/i) { $level=2; }
	elsif($name =~ /^hop$/i) { $level=3; }
	elsif($name =~ /^aop$/i) { $level=4; }
	elsif($name =~ /^sop$/i) { $level=5; }
	elsif($name =~ /^co?f(ounder)?$/i) { $level=6; }
	elsif($name =~ /^founder$/i) { $level=7; }
	elsif($name =~ /^(any|all|user)/i) { $level=0; }
	elsif($name =~ /^akick$/i) { $level=-1; }
	elsif($name =~ /^(none|disabled?|nobody)$/i) { $level=8; }

	return $level;
}

sub expire {
	return if services_conf_noexpire;

	$get_expired->execute(time() - (86400 * services_conf_chanexpire));
	while(my ($cn, $founder) = $get_expired->fetchrow_array) {
		drop({ CHAN => $cn });
		wlog($csnick, LOG_INFO(), "\002$cn\002 has expired.  Founder: $founder");
	}
}

sub enforcer_join($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};
	my $bot = agent($chan);

	return if $enforcers{lc $cn};
	$enforcers{lc $cn} = lc $bot;

	botserv::bot_join($chan);
	
	add_timer("CSEnforce $bot $cn", 60, __PACKAGE__, 'chanserv::enforcer_part');
}

sub enforcer_part($) {
	my ($cookie) = @_;
	my ($junk, $bot, $cn) = split(/ /, $cookie);

	return unless $enforcers{lc $cn};
	undef($enforcers{lc $cn});
	
	botserv::bot_part_if_needed($bot, {CHAN => $cn}, 'Enforcer Leaving');
}

sub fix_private_join_before_id($) {
	my ($user) = @_;

	my @cns = get_recent_private_chans(get_user_id($user));
	foreach my $cn (@cns) {
		my $chan = { CHAN => $cn };
		unban_user($chan, $user);
	}

	ircd::svsjoin($csnick, get_user_nick($user), @cns) if @cns;
}

### DATABASE UTILITY FUNCTIONS ###

sub get_user_count($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};

	$get_user_count->execute($cn);

	return $get_user_count->fetchrow_array;
}

sub get_lock($) {
	my ($chan) = @_;

	$chan = lc $chan;

	$chanuser_table++;

	if($cur_lock) {
		if($cur_lock ne $chan) {
			really_release_lock($chan);
			$chanuser_table--;
			die("Tried to get two locks at the same time: $cur_lock, $chan")
		}
		$cnt_lock++;
	} else {
		$cur_lock = $chan;
		$get_lock->execute(sql_conf_mysql_db.".chan.$chan");
		$get_lock->finish;
	}	
}

sub release_lock($) {
	my ($chan) = @_;

	$chan = lc $chan;

	$chanuser_table--;

	if($cur_lock and $cur_lock ne $chan) {
		really_release_lock($cur_lock);
		
		die("Tried to release the wrong lock");
	}

	if($cnt_lock) {
		$cnt_lock--;
	} else {
		really_release_lock($chan);
	}
}

sub really_release_lock($) {
	my ($chan) = @_;

	$cnt_lock = 0;
	$release_lock->execute(sql_conf_mysql_db.".chan.$chan");
	$release_lock->finish;
	undef $cur_lock;
}

#sub is_free_lock($) {
#	$is_free_lock->execute($_[0]);
#	return $is_free_lock->fetchrow_array;
#}

sub get_modelock($) {
	my ($chan) = @_;
	my $cn;
	if(ref($chan)) {
		$cn = $chan->{CHAN}
	} else {
		$cn = $chan;
	}

	$get_modelock->execute($cn);
	my ($ml) = $get_modelock->fetchrow_array;
	$get_modelock->finish();
	return $ml;
}

sub do_modelock($;$) {
	my ($chan, $modes) = @_;
	my $cn = $chan->{CHAN};

	my $seq = $ircline;

	$get_modelock_lock->execute; $get_modelock_lock->finish;

	$get_chanmodes->execute($cn);
	my ($omodes) = $get_chanmodes->fetchrow_array;
	my $ml = get_modelock($chan);

	$ml = do_modelock_fast($cn, $modes, $omodes, $ml);

	$unlock_tables->execute; $unlock_tables->finish;

	ircd::setmode(agent($chan), $cn, $ml) if($ml);
}

sub do_modelock_fast($$$$) {
	my ($cn, $modes, $omodes, $ml) = @_;
	my $nmodes = modes::add($omodes, $modes, 1);
	$ml = modes::diff($nmodes, $ml, 1);
	$set_chanmodes->execute(modes::add($nmodes, $ml, 1), $cn);

	return $ml;
}

sub update_modes($$) {
	my ($cn, $modes) = @_;

	$get_update_modes_lock->execute; $get_update_modes_lock->finish;
	$get_chanmodes->execute($cn);
	my ($omodes) = $get_chanmodes->fetchrow_array;

	$set_chanmodes->execute(modes::add($omodes, $modes, 1), $cn);
	$unlock_tables->execute; $unlock_tables->finish;
}

sub is_level($) {
	my ($perm) = @_;

	$is_level->execute($perm);

	return $is_level->fetchrow_array;
}

sub is_neverop($) {
	return nr_chk_flag($_[0], NRF_NEVEROP(), 1);
}

sub is_neverop_user($) {
	return nr_chk_flag_user($_[0], NRF_NEVEROP(), 1);
}

sub is_in_chan($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};
	my $uid = get_user_id($user);

	$is_in_chan->execute($uid, $cn);
	if($is_in_chan->fetchrow_array) {
		return 1;
	}

	return 0;
}

sub is_registered($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};

	$is_registered->execute($cn);
	if($is_registered->fetchrow_array) {
		return 1;
	} else {
		return 0;
	}
}

sub get_user_chans($) {
	my ($user) = @_;
	my $uid = get_user_id($user);
	my @chans;

	$get_user_chans->execute($uid, $ircline, $ircline+1000);
	while(my ($chan) = $get_user_chans->fetchrow_array) {
		push @chans, $chan;
	}

	return (@chans);
}

sub get_user_chans_recent($) {
	my ($user) = @_;
	my $uid = get_user_id($user);
	my (@curchans, @oldchans);

	$get_user_chans_recent->execute($uid);
	while(my ($cn, $joined, $op) = $get_user_chans_recent->fetchrow_array) {
		if ($joined) {
			push @curchans, make_op_prefix($op).$cn;
		}
		else {
			push @oldchans, $cn;
		}
	}

	return (\@curchans, \@oldchans);
}

my ($prefixes, $modes);
sub make_op_prefix($) {
	my ($op) = @_;
	return unless $op;

	unless(defined($prefixes) and defined($modes)) {
		$IRCd_capabilities{PREFIX} =~ /^\((\S+)\)(\S+)$/;
		($modes, $prefixes) = ($1, $2);
		$modes = reverse $modes;
		$prefixes = reverse $prefixes;
	}

	my $op_prefix = '';
	for(my $i = 0; $i < length($prefixes); $i++) {
		$op_prefix = substr($prefixes, $i, 1).$op_prefix if ($op & (2**$i));
	}
	return $op_prefix;
}

sub get_op($$) {
	my ($user, $chan) = @_;
	my $cn = $chan->{CHAN};
	my $uid = get_user_id($user);

	$get_op->execute($uid, $cn);
	my ($op) = $get_op->fetchrow_array;

	return $op;
}

sub get_best_acc($$;$) {
	my ($user, $chan, $retnick) = @_;
	my $uid = get_user_id($user);
	my $cn = $chan->{CHAN};

	$get_best_acc->execute($uid, $cn);
	my ($bnick, $best) = $get_best_acc->fetchrow_array;
	$get_best_acc->finish();

	if($retnick == 2) {
		return ($best, $bnick);
	} elsif($retnick == 1) {
		return $bnick;
	} else {
		return $best;
	}
}

sub get_acc($$) {
	my ($nick, $chan) = @_;
	my $cn = $chan->{CHAN};

	return undef
		if cr_chk_flag($chan, (CRF_DRONE | CRF_CLOSE | CRF_FREEZE), 1);

	$get_acc->execute($cn, $nick);
	my ($acc) = $get_acc->fetchrow_array;
	
	return $acc;
}

sub set_acc($$$$) {
	my ($nick, $user, $chan, $level) = @_;
	my $cn = $chan->{CHAN};
	my $adder;
	$adder = get_best_acc($user, $chan, 1) if $user;

	$set_acc1->execute($cn, $level, $nick);
	$set_acc2->execute($level, $adder, $cn, $nick);

	if ( ( $level > 0 and !is_neverop($nick) and !cr_chk_flag($chan, CRF_NEVEROP) )
		or $level < 0)
	{
		set_modes_allnick($nick, $chan, $level);
	}
}

sub del_acc($$) {
	my ($nick, $chan) = @_;
	my $cn = $chan->{CHAN};

	$del_acc->execute($cn, $nick);

	foreach my $user (get_nick_users $nick) {
		set_modes($user, $chan, 0, 1) if is_in_chan($user, $chan);
	}
}

sub get_auth_nick($$) {
	my ($cn, $nick) = @_;

	$get_auth_nick->execute($cn, $nick);
	my ($data) = $get_auth_nick->fetchrow_array();
	$get_auth_nick->finish();

	return split(/:/, $data);
}
sub get_auth_num($$) {
	my ($cn, $num) = @_;

	$get_auth_num->execute($cn, $num - 1);
	my ($nick, $data) = $get_auth_num->fetchrow_array();
	$get_auth_num->finish();

	return ($nick, split(/:/, $data));
}
sub find_auth($$) {
	my ($cn, $nick) = @_;

	$find_auth->execute($cn, $nick);
	my ($ret) = $find_auth->fetchrow_array();
	$find_auth->finish();

	return $ret;
}

# Only call this if you've checked the user for NEVEROP already.
sub set_modes_allchan($;$) {
	my ($user, $neverop) = @_;
	my $uid = get_user_id($user);

	$get_user_chans->execute($uid, $ircline, $ircline+1000);
	while(my ($cn) = $get_user_chans->fetchrow_array) {
		my $chan = { CHAN => $cn };
		my $acc = get_best_acc($user, $chan);
		if($acc > 0) {
			set_modes($user, $chan, $acc) unless ($neverop or cr_chk_flag($chan, CRF_NEVEROP));
		} elsif($acc < 0) {
			do_nick_akick($user, $chan);
		}
	}
}

# Only call this if you've checked for NEVEROP already.
sub set_modes_allnick($$$) {
	my ($nick, $chan, $level) = @_;
	my $cn = $chan->{CHAN};

	$get_using_nick_chans->execute($nick, $cn);
	while(my ($n) = $get_using_nick_chans->fetchrow_array) {
		my $user = { NICK => $n };
		my $l = get_best_acc($user, $chan);
		if($l > 0) {
			set_modes($user, $chan, $level, 1) if($level == $l);
		} elsif($l < 0) {
			do_nick_akick($user, $chan);
		}
	}
}

# If channel has OPGUARD, $doneg is true.
sub set_modes($$$;$$) {
	my ($user, $chan, $acc, $doneg, $dopos) = @_;
	# can you say eww?
	$dopos = 1 unless defined($dopos);
	$doneg = 0 unless defined($doneg);
	my $cn = $chan->{CHAN};


	if ($acc < 0) {
	# Do akick stuff here.
	}

	my $dst = ( $acc > 0 ? $ops[$acc] : 0 );
	my $cur = get_op($user, $chan);
	my ($pos, $neg);

	if (cr_chk_flag($chan, CRF_FREEZE)) {
		set_mode_mask($user, $chan, $cur, undef);
		return;
	}
	if (($acc == 0) and cr_chk_flag($chan, CRF_AUTOVOICE)) {
		set_mode_mask($user, $chan, $cur, 1);
		return;
	}

	$pos = $dst ^ ($dst & $cur);
	$neg = ($dst ^ $cur) & $cur if $doneg;

	if($pos or $neg) {
		set_mode_mask($user, $chan, ($doneg ? $neg : '-'), ($dopos ? $pos : '+'));
	}

	if($pos) {
		set_lastop($cn);
		set_lastused($cn, get_user_id($user));
	}
}

sub unset_modes($$) {
	my ($user, $chan) = @_;

	my $mask = get_op($user, $chan);

	set_mode_mask($user, $chan, $mask, 0);
}

sub set_mode_mask($$$$) {
	my ($user, $chan, @masks) = @_;
	my $nick = get_user_nick($user);
	my $cn = $chan->{CHAN};
	my (@args, $out);

	for(my $sign; $sign < 2; $sign++) {
		next if($masks[$sign] == 0);

		$out .= '-' if $sign == 0;
		$out .= '+' if $sign == 1;

		for(my $i; $i < 5; $i++) {
			my @l = ('v', 'h', 'o', 'a', 'q');

			if($masks[$sign] & 2**$i) {
				$out .= $l[$i];
				push @args, $nick;
			}
		}
	}

	if(@args) {
		ircd::setmode(agent($chan), $cn, $out, join(' ', @args));
	}
}

sub get_level($$) {
	my ($chan, $perm) = @_;
	my $cn = $chan->{CHAN};

	$get_level->execute($cn, $perm);
	my ($level, $isnotnull) = $get_level->fetchrow_array;
	$get_level->finish();

	if (wantarray()) {
		return ($level, $isnotnull);
	}
	else {
		return $level;
	}
}

sub check_override($$;$) {
	my ($user, $perm, $logMsg) = @_;
	$perm = uc $perm;

	#{OVERRIDE::$perm} produces funny package problems, so wrap it in double-quotes.
	if(exists($user->{"OVERRIDE::$perm"}) && (my $nick = $user->{"OVERRIDE::$perm"})) {
		if(defined($nick)) {
			if(services_conf_log_overrides && $logMsg) {
				my $src = get_user_nick($user);
				wlog($csnick, LOG_INFO(), "\002$src\002 used override $logMsg");
			}
			return (wantarray ? ($nick, 1) : $nick);
		} else {
			return;
		}
	}
	foreach my $o (@override) {
		my ($operRank, $permHashRef) = @$o;
		if($permHashRef->{$perm} and my $nick = adminserv::can_do($user, $operRank)) {
			$user->{"OVERRIDE::$perm"} = $nick;
			if(services_conf_log_overrides && $logMsg) {
				my $src = get_user_nick($user);
				wlog($csnick, LOG_INFO(), "\002$src\002 used override $logMsg");
			}
			return (wantarray ? ($nick, 1) : $nick);
		}
	}
	$user->{"OVERRIDE::$perm"} = undef;
}

sub can_do($$$;$) {
	my ($chan, $perm, $user, $data) = @_;
	$data = {} unless defined $data;
	# $data is a hashref/struct
	my $noreply = $data->{NOREPLY};
	my $acc = $data->{ACC};
	my $overrideMsg = $data->{OVERRIDE_MSG};

	if(my $nick = __can_do($chan, $perm, $user, $acc)) {
		# This is becoming increasingly complicated
		# and checking if an override was used is becoming tricky.
		# We had a case in cs_kick where an oper should be able to override +Q/$peace
		# but cannot b/c they have regular access in that channel.
		my $override;
		if(defined($user)) {
			(undef, $override) = check_override($user, $perm);
		}
		return (wantarray ? ($nick, $override) : $nick);
	} elsif ( $user and adminserv::is_svsop($user, adminserv::S_HELP()) ) { 
		#set_lastused($cn, get_user_id($user));
		my ($nick, $override) = check_override($user, $perm, $overrideMsg);
		return (wantarray ? ($nick, $override) : $nick) if $override;
	}
	if($user and !$noreply) {
		my $cn = $chan->{CHAN};
		if (cr_chk_flag($chan, (CRF_CLOSE | CRF_DRONE))) {
			notice($user, "\002$cn\002 is closed and cannot be used".
				((uc $perm eq 'INFO') ? ': '.get_close($chan) : '.'));
		}
		elsif(cr_chk_flag($chan, CRF_FREEZE)) {
			notice($user, "\002$cn\002 is frozen and access suspended.");
		}
		else {
			notice($user, "$cn: $err_deny");
		}
	}
	return 0;
}

sub __can_do($$$;$) {
	my ($chan, $perm, $user, $acc) = @_;
	my $nick;
	my $cn = $chan->{CHAN};
	$perm = uc $perm;

	my $level;
	unless(exists($chan->{"PERM::$perm"})) {
		$level = $chan->{"PERM::$perm"} = get_level($chan, $perm);
	} else {
		$level = $chan->{"PERM::$perm"};
	}

	unless(defined($acc)) {
		unless (defined $user && ref($user) eq 'HASH') {
			die "invalid __can_do call";
		}
		my $chanuser = $user->{lc $cn};
		unless (defined($chanuser) && exists($chanuser->{ACC})) {
			($acc, $nick) = get_best_acc($user, $chan, 2);
			($chanuser->{ACC}, $chanuser->{ACCNICK}) = ($acc, $nick);
		} else {
			($acc, $nick) = ($chanuser->{ACC}, $chanuser->{ACCNICK});
		}
	}
	$nick = 1 unless $nick;

	if($acc >= $level and !cr_chk_flag($chan, (CRF_CLOSE | CRF_FREEZE | CRF_DRONE))) {
		set_lastused($cn, get_user_id($user)) if $user;
		return (wantarray ? ($nick, 0) : $nick);
	}

	if(cr_chk_flag($chan, CRF_FREEZE) and ($perm eq 'JOIN')) {
		return (wantarray ? ($nick, 0) : $nick);
	}

	return 0;
}

sub can_keep_op($$$$) {
# This is a naïve implemenation using a loop.
# If we ever do a more flexible version that further restricts how
# LEVELS affect opguard, the loop will have to be unrolled.
# --
# Only call this if you've already checked opguard, as we do not check it here.
# --
# Remember, this isn't a permission check if someone is allowed to op someone [else],
# rather this checks if the person being opped is allowed to keep/have it.
	my ($user, $chan, $tuser, $opmode) = @_;
	return 1 if $opmode eq 'v'; # why remove a voice?
	my %permhash = (
		'q' => ['OWNER', 	4],
		'a' => ['ADMIN', 	3],
		'o' => ['OP', 		2],
		'h' => ['HALFOP', 	1],
		'v' => ['VOICE', 	0]
	);

	my $self = (lc(get_user_nick($user)) eq lc(get_user_nick($tuser)));

	#my ($level, $isnotnull) = get_level($chan, $permhash{$opmode}[1]);
	my $level = get_level($chan, $permhash{$opmode}[0]);

	foreach my $luser ($tuser, $user) {
	# We check target first, as there seems no reason that
	# someone who has access can't be opped by someone
	# who technically doesn't.
		return 1 if (adminserv::is_svsop($luser, adminserv::S_HELP()) and
			check_override($luser, $permhash{$opmode}[0]));

		my $acc = get_best_acc($luser, $chan);
		return 1 if ($self and ($permhash{opmode}[2] + 2) <= $acc);

		if($acc < $level) {
			return 0;
		}
	}

	return 1;
}

sub agent($) {
	my ($chan) = @_;

	return $chan->{AGENT} if($chan->{AGENT});
	
	unless(initial_synced()) {
		return $csnick;
	}

	$botserv::get_chan_bot->execute($chan->{CHAN});
	my ($agent) = $botserv::get_chan_bot->fetchrow_array;

	$agent = $csnick unless $agent;

	return $chan->{AGENT} = $agent;
}

sub drop($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};

	undef($enforcers{lc $cn});
	my $agent = agent($chan);
	agent_part($agent, $cn, 'Channel dropped') unless (lc($agent) eq lc($csnick));
	if (module::is_loaded('logserv')) {
		eval { logserv::delchan(undef, $cn); }
	}

	$drop_acc->execute($cn);
	$drop_lvl->execute($cn);
	$del_close->execute($cn);
	$drop_akick->execute($cn);
	$drop_welcome->execute($cn);
	$drop_chantext->execute($cn);
	$drop_nicktext->execute($cn); # Leftover channel auths
	$drop->execute($cn);
	ircd::setmode($csnick, $cn, '-r');
}

sub drop_nick_chans($) {
	my ($nick) = @_;

	$delete_successors->execute($nick);
	
	$get_nick_own_chans->execute($nick);
	while(my ($cn) = $get_nick_own_chans->fetchrow_array) {
		succeed_chan($cn, $nick);
	}
}

sub succeed_chan($$) {
	my ($cn, $nick) = @_;

	$get_successor->execute($cn);
	my ($suc) = $get_successor->fetchrow_array;

	if($suc) {
		$set_founder->execute($suc, $cn);
		set_acc($suc, undef, {CHAN => $cn}, FOUNDER);
		$del_successor->execute($cn);
	} else {
		drop({CHAN => $cn});
		wlog($csnick, LOG_INFO(), "\002$cn\002 has been dropped due to expiry/drop of \002$nick\002");
	}
}

sub get_close($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};
	return undef unless cr_chk_flag($chan, CRF_CLOSE | CRF_DRONE);

	$get_close->execute($cn);
	my ($reason, $opnick, $time) = $get_close->fetchrow_array();
	$get_close->finish();

	$reason = "[$opnick ".gmtime2($time)."] - $reason";
	
	return (wantarray ? ($reason, $opnick, $time) : $reason);
}

sub get_users_nochans(;$) {
	my ($noid) = @_;
	my @users;

	if($noid) {
		$get_users_nochans_noid->execute();
		while (my ($usernick, $userid) = $get_users_nochans_noid->fetchrow_array()) {
			push @users, { NICK => $usernick, ID => $userid };
		}
		$get_users_nochans_noid->finish();
	}
	else {
		$get_users_nochans->execute();
		while (my ($usernick, $userid) = $get_users_nochans->fetchrow_array()) {
			push @users, { NICK => $usernick, ID => $userid };
		}
		$get_users_nochans->finish();
	}

	return @users;
}

sub get_bantype($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};

	unless (exists($chan->{BANTYPE})) {
		$get_bantype->execute($cn);
		($chan->{BANTYPE}) = $get_bantype->fetchrow_array();
		$get_bantype->finish();
	}

	return $chan->{BANTYPE};
}

sub memolog($$) {
	my ($chan, $log) = @_;

	my $level = get_level($chan, "MemoAccChange");
	return if $level == 8; # 8 is 'disable'
	$level = 1 if $level == 0;
	memoserv::send_chan_memo($csnick, $chan, $log, $level);
}

sub get_ban_num($$) {
	my ($chan, $num) = @_;
	$get_ban_num->execute($chan->{CHAN}, 0, $num-1);
	my ($mask) = $get_ban_num->fetchrow_array();
	$get_ban_num->finish();
	return sql2glob($mask);
}

### IRC EVENTS ###

sub user_join($$) {
# Due to special casing of '0' this wrapper should be used
# by anyone handling a JOIN (not SJOIN, it's a JOIN) event.
# This is an RFC1459 requirement.
	my ($nick, $cn) = @_;
	my $user = { NICK => $nick };
	my $chan = { CHAN => $cn };

	if ($cn == 0) {
	# This should be treated as a number
	# Just in case we ever got passed '000', not that Unreal does.
	# In C, you could check that chan[0] != '#' && chan[0] == '0'
		user_part_multi($user, [ get_user_chans($user) ], 'Left all channels');
	}
	else {
		user_join_multi($chan, [$user]);
	}
}

sub handle_sjoin($$$$$$$) {
	my ($server, $cn, $ts, $chmodes, $chmodeparms, $userarray, $banarray, $exceptarray) = @_;
	my $chan = { CHAN => $cn };

	if(synced()) {
		chan_mode($server, $cn, $chmodes, $chmodeparms) if $chmodes;
	} else {
		update_modes($cn, "$chmodes $chmodeparms") if $chmodes;
	}
	user_join_multi($chan, $userarray) if scalar @$userarray;

	foreach my $ban (@$banarray) {
		process_ban($cn, $ban, $server, 0, 1);
	}
	foreach my $except (@$exceptarray) {
		process_ban($cn, $except, $server, 128, 1);
	}
}

sub user_join_multi($$) {
	my ($chan, $users) = @_;
	my $cn = $chan->{CHAN};
	my $seq = $ircline;
	my $multi_tradeoff = 2; # could use some synthetic-benchmark tuning

	foreach my $user (@$users) {
		$user->{__ID} = get_user_id($user);
		
		unless (defined($user->{__ID})) {
			# This does happen occasionally. it's a BUG.
			# At least we have a diagnostic for it now.
			# Normally we'd just get a [useless] warning from the SQL server
			ircd::debug($user->{NICK}.' has a NULL user->{__ID} in user_join_multi('.$cn.', ...');
		}
	}
	
	$get_joinpart_lock->execute; $get_joinpart_lock->finish;

	$chan_create->execute($seq, $cn);

	$get_user_count->execute($cn);
	my ($count) = $get_user_count->fetchrow_array;

	if(scalar(@$users) < $multi_tradeoff) {
		foreach my $user (@$users) {
			# see note above in get_user_id loop
			if (defined($user->{__ID})) {
				$chanjoin->execute($seq, $user->{__ID}, $cn, $user->{__OP});
			}
		}
	}
	else {
		my $query = "REPLACE INTO chanuser (seq, nickid, chan, op, joined) VALUES ";
		foreach my $user (@$users) {
		# a join(',', list) would be nice but would involve preparing the list first.
		# I think this will be faster.
			if (defined($user->{__ID})) {
				# see note above in get_user_id loop
				$query .= '('.$dbh->quote($seq).','.
					$dbh->quote($user->{__ID}).','.
					$dbh->quote($cn).','.
					$dbh->quote($user->{__OP}).', 1),';
			}
		}
		$query =~ s/\,$//;
		$dbh->do($query);
	}

	$unlock_tables->execute; $unlock_tables->finish;

	my $bot = agent($chan);
	foreach my $user (@$users) {
		$user->{AGENT} = $bot;
	}
	
	if(initial_synced() and cr_chk_flag($chan, (CRF_CLOSE | CRF_DRONE))) {
		my ($reason, $opnick, $time) = get_close($chan);
		my $cmsg = "$cn is closed: $reason";
		my $preenforce = $enforcers{lc $chan};
		
		if (cr_chk_flag($chan, CRF_CLOSE)) {
			kickban_multi($chan, $users, $cmsg);
		}
		elsif (cr_chk_flag($chan, CRF_DRONE)) {
			chan_kill($chan, $cmsg, $users);
		}

		unless($preenforce) {
			ircd::settopic($bot, $cn, $opnick, $time, $cmsg);

			my $ml = get_modelock($chan);
			ircd::setmode($bot, $cn, $ml) if($ml);
		}
	}

	if(($count == 0  or !is_agent_in_chan($bot, $cn)) and initial_synced()) {
		unless (lc($bot) eq lc($csnick)) {
			unless(is_agent_in_chan($bot, $cn)) {
				botserv::bot_join($chan);
			}
		}
	}
	
	return unless synced() and not cr_chk_flag($chan, (CRF_CLOSE | CRF_DRONE));

	my $n;
	foreach my $user (@$users) {
		if(do_status($user, $chan)) {
			$n++;
			$user->{__DO_WELCOME} = 1;
		}
	}

	if($count == 0 and $n) {
		my ($ml) = get_modelock($chan);
		ircd::setmode($bot, $cn, $ml) if($ml);
		
		$get_topic->execute($cn);
		my ($ntopic, $nsetter, $ntime) = $get_topic->fetchrow_array;
		ircd::settopic($bot, $cn, $nsetter, $ntime, $ntopic) if $ntopic;
	}

	ircd::flushmodes();

	if($n) {
		foreach my $user (@$users) {
			if ($user->{__DO_WELCOME} and chk_user_flag($user, UF_FINISHED())) {
				do_welcome($user, $chan);
				do_greet($user, $chan)
					if can_do($chan, 'GREET', $user, { NOREPLY => 1 });
			}
		}
	}
}

sub user_part($$$) {
	my ($nick, $cn, $reason) = @_;

	my $user = ( ref $nick eq 'HASH' ? $nick : { NICK => $nick });

	user_part_multi($user, [ $cn ], $reason);
}

sub user_part_multi($$$) {
# user_join_multi takes a channel and multiple users
# user_part_multi takes a user and multiple channels
# There should probably be a user_join_* that takes one user, multiple channels
# However, it seems that so far, Unreal splits both PART and JOIN (non-SJOIN)
# into multiple events/cmds. The reason is unclear.
# Other ircds may not do so. 
# There is also KICK. some IRCds allow KICK #chan user1,user2,...
# Unreal it's _supposed_ to work, but it does not.

	my ($user, $chanlist, $reason) = @_;
	my @chans;
	foreach my $cn (@$chanlist) {
		push @chans, { CHAN => $cn };
	
	}

	my $uid = get_user_id($user);
	my $seq = $ircline;

	$get_joinpart_lock->execute; $get_joinpart_lock->finish;

	foreach my $chan (@chans) {
		my $cn = $chan->{CHAN};
		$chanpart->execute($seq, $uid, $cn, $seq, $seq+1000);
		$get_user_count->execute($cn);
		$chan->{COUNT} = $get_user_count->fetchrow_array;
	}

	$unlock_tables->execute; $unlock_tables->finish;
	
	foreach my $chan (@chans) {
		channel_emptied($chan) if $chan->{COUNT} == 0;
	}
}

sub channel_emptied($) {
	my ($chan) = @_;

	botserv::bot_part_if_needed(undef, $chan, 'Nobody\'s here', 1);
	$chan_delete->execute($chan->{CHAN});
	$wipe_bans->execute($chan->{CHAN});
}

sub process_kick($$$$) {
	my ($src, $cn, $target, $reason) = @_;
	my $tuser = { NICK => $target };
	user_part($tuser, $cn, 'Kicked by '.$src.' ('.$reason.')');

	my $chan = { CHAN => $cn };
	if ( !(is_agent($src) or $src =~ /\./ or adminserv::is_ircop({ NICK => $src })) and
		({modes::splitmodes(get_modelock($chan))}->{Q}->[0] eq '+') )
	{
		my $srcUser = { NICK => $src };
		#ircd::irckill(agent($chan), $src, "War script detected (kicked $target past +Q in $cn)");
		nickserv::kline_user($srcUser, 300, "War script detected (kicked $target past +Q in $cn)");
		# SVSJOIN won't work while they're banned, unless you invite.
		ircd::invite(agent($chan), $cn, $target);
		ircd::svsjoin(undef, $target, $cn);
		unban_user($chan, $tuser);
	}
}

sub chan_mode($$$$) {
	my ($src, $cn, $modes, $args) = @_;
	my $user = { NICK => $src };
	my $chan = { CHAN => $cn };
	my ($sign, $num);

	# XXX This is not quite right, but maybe it's good enough.
	my $mysync = ($src =~ /\./ ? 0 : 1);
	
	if($modes !~ /^[beIvhoaq+-]+$/ and (!synced() or $mysync)) {
		do_modelock($chan, "$modes $args");
	}

	my $opguard = (!current_message->{SYNC} and cr_chk_flag($chan, CRF_OPGUARD, 1));
	
	my @perms = ('VOICE', 'HALFOP', 'OP', 'PROTECT');
	my $unmodes = '-';
	my @unargs;

	my @modes = split(//, $modes);
	my @args = split(/ /, $args);

	foreach my $mode (@modes) {
		if($mode eq '+') { $sign = 1; next; }
		if($mode eq '-') { $sign = 0; next; }
		
		my $arg = shift(@args) if($mode =~ $scm or $mode =~ $ocm);
		my $auser = { NICK => $arg };
		
		if($mode =~ /^[vhoaq]$/) {
			next if $arg eq '';
			next if is_agent($arg);
			$num = 0 if $mode eq 'v';
			$num = 1 if $mode eq 'h';
			$num = 2 if $mode eq 'o';
			$num = 3 if $mode eq 'a';
			$num = 4 if $mode eq 'q';

			if($opguard and $sign == 1 and
				!can_keep_op($user, $chan, $auser, $mode)
			) {
				$unmodes .= $mode;
				push @unargs, $arg;
			} else {
				my $nid = get_user_id($auser) or next;
				my ($r, $i);
				do {
					if($sign) {
						$r = $chop->execute((2**$num), (2**$num), $nid, $cn);
					} else {
						$r = $chdeop->execute((2**$num), (2**$num), $nid, $cn);
					}
					$i++;
				} while($r==0 and $i<10);
			}
		}
		if ($mode eq 'b') {
			next if $arg eq '';
			process_ban($cn, $arg, $src, 0, $sign);
		}
		if ($mode eq 'e') {
			next if $arg eq '';
			process_ban($cn, $arg, $src, 128, $sign);
		}
		if ($mode eq 'I') {
			next;# if $arg eq '';
			#process_ban($cn, $arg, $src, 128, $sign);
		}
	}
	ircd::setmode(agent($chan), $cn, $unmodes, join(' ', @unargs)) if($opguard and @unargs);
}

sub process_ban($$$$) {
	my ($cn, $arg, $src, $type, $sign) = @_;

	my $arg2 = $arg;

	$arg =~ tr/\*\?/\%\_/;

	if ($sign > 0) {
		$add_ban->execute($cn, $arg, $src, $type);
	} else {
		$delete_ban->execute($cn, $arg, $type);
		del_tempban($cn, $arg2);
	}
}
sub cs_topicappend {
	my ($user, $cn, $topicappend) = @_;
	$get_topic->execute($cn);
	my ($ntopic, $nsetter, $ntime) = $get_topic->fetchrow_array;
	my $newtopic;
	if ($ntopic) {
		$newtopic = $ntopic . " | " . $topicappend;
	}
	else { $newtopic = $topicappend; }
	cs_topic ($user, { CHAN => $cn }, $newtopic);
}
sub cs_topicprepend {
	my ($user, $cn, $topicprepend) = @_;
	$get_topic->execute($cn);
	my ($ntopic, $nsetter, $ntime) = $get_topic->fetchrow_array;
	my $newtopic;
	if ($ntopic) {
		$newtopic = $topicprepend . " | " . $ntopic;
	}
	else { $newtopic = $topicprepend; }
	cs_topic ($user, { CHAN => $cn }, $newtopic);
}
sub chan_topic {
	my ($src, $cn, $setter, $time, $topic) = @_;
	my $chan = { CHAN => $cn };
	my $suser = { NICK => $setter, AGENT => agent($chan) };

	return unless is_registered($chan);
	return if cr_chk_flag($chan, CRF_CLOSE, 1);

	if(current_message->{SYNC}) {  # We don't need to undo our own topic changes.
		$set_topic1->execute($setter, $time, $cn);
		$set_topic2->execute($cn, $topic);
		return;
	}

	if(!synced()) {
		$get_topic->execute($cn);
		my ($ntopic, $nsetter, $ntime) = $get_topic->fetchrow_array;
		if($topic ne '' and $time == $ntime or can_do($chan, 'SETTOPIC', undef, { ACC => 0 })) {
			$set_topic1->execute($setter, $time, $cn);
			$set_topic2->execute($cn, $topic);
		} else {
			ircd::settopic(agent($chan), $cn, $nsetter, $ntime, $ntopic);
		}
	}

	elsif(lc($src) ne lc($setter) or can_do($chan, 'SETTOPIC', $suser)) {
		$set_topic1->execute($setter, $time, $cn);
		$set_topic2->execute($cn, $topic);
	} else {
		$get_topic->execute($cn);
		my ($ntopic, $nsetter, $ntime) = $get_topic->fetchrow_array;
		ircd::settopic(agent($chan), $cn, $nsetter, $ntime, $ntopic);
	}
}

sub eos(;$) {
	my ($server) = @_;
	my $gsa;

	$get_all_closed_chans->execute(CRF_DRONE|CRF_CLOSE);
	while(my ($cn, $type, $reason, $opnick, $time) = $get_all_closed_chans->fetchrow_array) {
		my $chan = { CHAN => $cn };

		my $cmsg = " is closed [$opnick ".gmtime2($time)."]: $reason";
		if($type == CRF_DRONE) {
			chan_kill($chan, $cn.$cmsg);
		} else {
			ircd::settopic(agent($chan), $cn, $opnick, $time, "Channel".$cmsg);
			clear_users($chan, "Channel".$cmsg);
		}
	}

	while($chanuser_table > 0) { }

	$get_eos_lock->execute(); $get_eos_lock->finish;
	$get_akick_all->execute();
	if($server) {
		$get_status_all_server->execute($server);
		$gsa = $get_status_all_server;
	} else {
		$get_status_all->execute();
		$gsa = $get_status_all;
	}
	#$unlock_tables->execute(); $unlock_tables->finish;

	while(my @akick = $get_akick_all->fetchrow_array) {
		akickban(@akick);
	}

	$get_modelock_all->execute();
	while(my ($cn, $modes, $ml) = $get_modelock_all->fetchrow_array) {
		$ml = do_modelock_fast($cn, '', $modes, $ml);
		ircd::setmode(agent({CHAN=>$cn}), $cn, $ml) if $ml;
	}

	while(my ($cn, $cflags, $agent, $nick, $uid, $uflags, $level, $op, $neverop) = $gsa->fetchrow_array) {
		my $user = { NICK => $nick, ID => $uid };
		#next if chk_user_flag($user, UF_FINISHED);
		$agent = $csnick unless $agent;
		my $chan = { CHAN => $cn, FLAGS => $cflags, AGENT => $agent };

		set_modes($user, $chan, $level, ($cflags & CRF_OPGUARD)) if not $neverop and $ops[$level] != $op and not $cflags & (CRF_FREEZE | CRF_CLOSE | CRF_DRONE);
		do_welcome($user, $chan);
	}

	set_user_flag_all(UF_FINISHED());
	$unlock_tables->execute(); $unlock_tables->finish;
	check_expired_bans();
}

1;
