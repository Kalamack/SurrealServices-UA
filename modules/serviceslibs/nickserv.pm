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
package nickserv;

use strict;
use Time::Local;
use SrSv::Timer qw(add_timer);
use SrSv::IRCd::State qw($ircline synced initial_synced %IRCd_capabilities);
use SrSv::Agent;
use SrSv::Conf qw(main services sql);
use SrSv::Conf2Consts qw(main services sql);
use SrSv::HostMask qw(normalize_hostmask hostmask_to_regexp parse_mask parse_hostmask make_hostmask);

use SrSv::MySQL qw( $dbh :sql_types );
use SrSv::MySQL::Glob;

use SrSv::Shared qw(%newuser %olduser);

use SrSv::Time;
use SrSv::Text::Format qw(columnar);
use SrSv::Errors;

use SrSv::Log;

use SrSv::User '/./';
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::NickReg::Flags;
use SrSv::NickReg::User '/./';
use SrSv::Hash::Passwords;

use SrSv::NickControl::Enforcer qw(%enforcers);

use SrSv::Email;

use SrSv::Util qw( makeSeqList );

use SrSv::Debug;

use SrSv::NickReg::NickText;

use SrSv::IPv6;

require SrSv::MySQL::Stub;

use constant {
	# Clone exception max limit.
	# This number typically means infinite/no-limit.
	# It is 2**24-1
	MAX_LIM	=> 16777215,

	# This could be made a config option
	# But our config system currently sucks.
	MAX_PROFILE	=> 10,
	# This value likely cannot be increased very far
	# as the following limits would apply:
	# 106 (nick/hostmask), 6 (NOTICE), 30 (destination-nick), 32 (key length) = 174
	# 510 - 174 = 336
	# but this does not take into account additional spaces/colons
	# or reformatting by the SrSv::Format code.
	# Likely the maximum value is ~300
	MAX_PROFILE_LEN	=> 250,
};

our $nsnick_default = 'NickServ';
our $nsnick = $nsnick_default;

our $cur_lock;
our $cnt_lock = 0;

our @protect_short = ('none', 'normal', 'high', 'kill');
our @protect_long = (
	'You will not be required to identify to use this nick.',
	'You must identify within 60 seconds to use this nick.',
	'You must identify before using this nick.',
	'You must identify before using this nick or you will be disconnected.'
);
our %protect_level = (
	'none'		=> 0,
	'no'		=> 0,
	'false'		=> 0,
	'off'		=> 0,
	'0'		=> 0,

	'true'		=> 1,
	'yes'		=> 1,
	'on'		=> 1,
	'normal'	=> 1,
	'1'		=> 1,

	'high'		=> 2,
	'2'		=> 2,

	'kill'		=> 3,
	'3'		=> 3
);
	
our (
	$nick_check,
	$nick_create, $nick_create_old,	$nick_change, $nick_quit, $nick_delete, $nick_id_delete,
	$get_quit_empty_chans, $nick_chan_delete, $chan_user_partall,
	$get_hostless_nicks,

	$get_squit_lock, $squit_users, $squit_nickreg, $get_squit_empty_chans, $squit_lastquit,

	$del_nickchg_id, $add_nickchg, $reap_nickchg,
	
	$get_nick_inval, $inc_nick_inval,
	$is_registered,
	$is_alias_of,

	$get_guest, $set_guest,

	$get_lock, $release_lock,
	
	$get_umodes, $set_umodes,
	
	$get_info,
	$set_vhost, $set_ident, $set_ip,
	$update_regnick_vhost, $get_regd_time, $get_nickreg_quit, 

	$chk_clone_except, $count_clones,

	$set_pass,
	$set_email, 

	$get_root_nick, $get_id_nick, $chk_pass, $identify, $identify_ign, $id_update, $logout, $unidentify, $unidentify_single,
	$update_lastseen, $quit_update,  $update_nickalias_last,
	$set_protect_level,

	$get_register_lock, $register, $create_alias, $drop, $change_root,

	$get_aliases, $get_glist, $count_aliases, $get_random_alias, $delete_alias, $delete_aliases,
	$get_all_access, $del_all_access, $change_all_access, $change_akicks, $change_founders,
	$change_successors, $change_svsops,
	
	$lock_user_table, $unlock_tables,

	$get_matching_nicks,

	$cleanup_nickid, $cleanup_users, $cleanup_chanuser,
	$get_dead_users,

	$get_expired, $get_near_expired, $set_near_expired,
	
	$get_watches, $check_watch, $set_watch, $del_watch, $drop_watch,
	$get_silences, $check_silence, $set_silence, $del_silence, $drop_silence,
	$get_silence_by_num,
	$get_expired_silences, $del_expired_silences,

	$get_seen,

	$set_greet, $get_greet, $get_greet_nick, $del_greet,
	$get_num_nicktext_type, $drop_nicktext,

	$get_auth_chan, $get_auth_num, $del_auth, $list_auth, $add_auth,

	$del_nicktext,

	$set_umode_ntf, $get_umode_ntf,

	$set_vacation_ntf, $get_vacation_ntf,

	$set_authcode_ntf, $get_authcode_ntf,

	$get_nicks_by_email,
);

sub init() {
	$nick_check = $dbh->prepare("SELECT id FROM user WHERE nick=? AND online=0 AND time=?");
	$nick_create = $dbh->prepare("INSERT INTO user SET nick=?, time=?, inval=0, ident=?, host=?, vhost=?, server=?, modes=?,
		gecos=?, flags=?, cloakhost=?, online=1");
#	$nick_create = $dbh->prepare("INSERT INTO user SET id=(RAND()*294967293)+1, nick=?, time=?, inval=0, ident=?, host=?, vhost=?, server=?, modes=?, gecos=?, flags=?, cloakhost=?, online=1");
	$nick_create_old = $dbh->prepare("UPDATE user SET nick=?, ident=?, host=?, vhost=?, server=?, modes=?, gecos=?,
		flags=?, cloakhost=?, online=1 WHERE id=?");
	$nick_change = $dbh->prepare("UPDATE user SET nick=?, time=? WHERE nick=?");
	$nick_quit = $dbh->prepare("UPDATE user SET online=0, quittime=UNIX_TIMESTAMP() WHERE nick=?");
	$nick_delete = $dbh->prepare("DELETE FROM user WHERE nick=?");
	$nick_id_delete = $dbh->prepare("DELETE FROM nickid WHERE id=?");
	$get_quit_empty_chans = $dbh->prepare("SELECT cu2.chan, COUNT(*) AS c
		FROM chanuser AS cu1, chanuser AS cu2
		WHERE cu1.nickid=?
		AND cu1.chan=cu2.chan AND cu1.joined=1 AND cu2.joined=1
		GROUP BY cu2.chan HAVING c=1 ORDER BY NULL");
	$nick_chan_delete = $dbh->prepare("DELETE FROM chanuser WHERE nickid=?");
	$chan_user_partall = $dbh->prepare("UPDATE chanuser SET joined=0 WHERE nickid=?");
	$get_hostless_nicks = $dbh->prepare("SELECT nick FROM user WHERE vhost='*'");

	$get_squit_lock = $dbh->prepare("LOCK TABLES chanuser WRITE, chanuser AS cu1 READ LOCAL, chanuser AS cu2 READ LOCAL, user WRITE, nickreg WRITE, nickid WRITE, chanban WRITE, chan WRITE, chanreg READ LOCAL, nicktext WRITE");
	$squit_users = $dbh->prepare("UPDATE chanuser, user
		SET chanuser.joined=0, user.online=0, user.quittime=UNIX_TIMESTAMP()
		WHERE user.id=chanuser.nickid AND user.server=?");
	# Must call squit_nickreg and squit_lastquit before squit_users as it modifies user.online
	$squit_nickreg = $dbh->prepare("UPDATE nickreg, nickid, user
		SET nickreg.last=UNIX_TIMESTAMP()
		WHERE nickreg.id=nickid.nrid AND nickid.id=user.id
		AND user.online=1 AND user.server=?");
=cut
	$squit_lastquit = $dbh->prepare("UPDATE nickid, user, nicktext
		SET nicktext.data=?
		WHERE nicktext.nrid=nickid.nrid AND nickid.id=user.id
		AND user.online=1 AND user.server=?");
=cut
	$squit_lastquit = $dbh->prepare("REPLACE INTO nicktext ".
		"SELECT nickid.nrid, ".NTF_QUIT.", 0, '', ? ".
		"FROM nickid JOIN user ON (nickid.id=user.id) ".
		"WHERE user.online=1 AND user.server=?");
	$get_squit_empty_chans = $dbh->prepare("SELECT cu2.chan, COUNT(*) AS c
		FROM user, chanuser AS cu1, chanuser AS cu2
		WHERE user.server=? AND cu1.nickid=user.id
		AND cu1.chan=cu2.chan AND cu1.joined=1 AND cu2.joined=1
		GROUP BY cu2.chan HAVING c=1 ORDER BY NULL");

	$del_nickchg_id = $dbh->prepare("DELETE FROM nickchg WHERE nickid=?");
	$add_nickchg = $dbh->prepare("REPLACE INTO nickchg SELECT ?, id, ? FROM user WHERE nick=?");
	$reap_nickchg = $dbh->prepare("DELETE FROM nickchg WHERE seq<?");
	
	$get_nick_inval = $dbh->prepare("SELECT nick, inval FROM user WHERE id=?");
	$inc_nick_inval = $dbh->prepare("UPDATE user SET inval=inval+1 WHERE id=?");

	$is_registered = $dbh->prepare("SELECT 1 FROM nickalias WHERE alias=?");
	$is_alias_of = $dbh->prepare("SELECT 1 FROM nickalias AS n1 LEFT JOIN nickalias AS n2 ON n1.nrid=n2.nrid
		WHERE n1.alias=? AND n2.alias=? LIMIT 1");

	$get_guest = $dbh->prepare("SELECT flags & @{[UF_GUEST]} FROM user WHERE nick=?");
	$set_guest = $dbh->prepare("UPDATE user SET flags = IF(?, flags | @{[UF_GUEST]}, flags & ~@{[UF_GUEST]})
		WHERE nick=?");

	$get_lock = $dbh->prepare("SELECT GET_LOCK(?, 10)");
	$release_lock = $dbh->prepare("SELECT RELEASE_LOCK(?)");

	$get_umodes = $dbh->prepare("SELECT modes FROM user WHERE id=?");
	$set_umodes = $dbh->prepare("UPDATE user SET modes=? WHERE id=?");
	
	$get_info = $dbh->prepare("SELECT nickreg.email, nickreg.regd, nickreg.last, nickreg.flags, nickreg.ident,
		nickreg.vhost, nickreg.gecos, nickalias.last
		FROM nickreg, nickalias WHERE nickalias.nrid=nickreg.id AND nickalias.alias=?");
	$get_nickreg_quit = $dbh->prepare("SELECT nicktext.data FROM nickreg, nicktext, nickalias
		WHERE nickalias.nrid=nickreg.id AND nickalias.alias=? AND
		(nicktext.nrid=nickreg.id AND nicktext.type=".NTF_QUIT.")");
	$set_ident = $dbh->prepare("UPDATE user SET ident=? WHERE id=?");
	$set_vhost = $dbh->prepare("UPDATE user SET vhost=? WHERE id=?");
	$set_ip = $dbh->prepare("UPDATE user SET ip=?, ipv6=? WHERE id=?");
	$update_regnick_vhost = $dbh->prepare("UPDATE nickreg,nickid SET nickreg.vhost=?
		WHERE nickreg.id=nickid.nrid AND nickid.id=?");
	$get_regd_time = $dbh->prepare("SELECT nickreg.regd FROM nickreg, nickalias
		WHERE nickalias.nrid=nickreg.id and nickalias.alias=?");

	$chk_clone_except = $dbh->prepare("SELECT
		GREATEST(IF((user.ip >> (32 - sesexip.mask)) = (sesexip.ip >> (32 - sesexip.mask)), sesexip.lim, 0),
		IF(IF(sesexname.serv, user.server, user.host) LIKE sesexname.host, sesexname.lim, 0)) AS n
		FROM user, sesexip, sesexname WHERE user.id=? ORDER BY n DESC LIMIT 1");
	$count_clones = $dbh->prepare("SELECT COUNT(*) FROM user WHERE ip=? AND online=1");

	$get_root_nick = $dbh->prepare("SELECT nickreg.nick FROM nickreg, nickalias WHERE nickreg.id=nickalias.nrid AND nickalias.alias=?");
	$get_id_nick = $dbh->prepare("SELECT nickreg.nick FROM nickreg WHERE nickreg.id=?");
	$identify = $dbh->prepare("INSERT INTO nickid SELECT ?, nickalias.nrid FROM nickalias WHERE alias=?");
	$identify_ign = $dbh->prepare("INSERT IGNORE INTO nickid SELECT ?, nickalias.nrid FROM nickalias WHERE alias=?");
	$id_update = $dbh->prepare("UPDATE nickreg, user SET
		nickreg.last=UNIX_TIMESTAMP(), nickreg.ident=user.ident,
		nickreg.vhost=user.vhost, nickreg.gecos=user.gecos,
		nickreg.nearexp=0, nickreg.flags = (nickreg.flags & ~". NRF_VACATION .")
		WHERE nickreg.nick=? AND user.id=?");
	$logout = $dbh->prepare("DELETE FROM nickid WHERE id=?");
	$unidentify = $dbh->prepare("DELETE FROM nickid USING nickreg, nickid WHERE nickreg.nick=? AND nickid.nrid=nickreg.id");

	$update_lastseen = $dbh->prepare("UPDATE nickreg,nickid SET nickreg.last=UNIX_TIMESTAMP()
		WHERE nickreg.id=nickid.nrid AND nickid.id=?");
	$update_nickalias_last = $dbh->prepare("UPDATE nickalias SET last=UNIX_TIMESTAMP() WHERE alias=?");
	$quit_update = $dbh->prepare("REPLACE INTO nicktext
		SELECT nickreg.id, ".NTF_QUIT().", 0, NULL, ? FROM nickreg, nickid
		WHERE nickreg.id=nickid.nrid AND nickid.id=?");

	$set_protect_level = $dbh->prepare("UPDATE nickalias SET protect=? WHERE alias=?");


	$set_email = $dbh->prepare("UPDATE nickreg, nickalias SET nickreg.email=? WHERE nickalias.nrid=nickreg.id AND nickalias.alias=?");
	
	$set_pass = $dbh->prepare("UPDATE nickreg, nickalias SET nickreg.pass=? WHERE nickalias.nrid=nickreg.id AND nickalias.alias=?");

	$get_register_lock = $dbh->prepare("LOCK TABLES nickalias WRITE, nickreg WRITE");
	$register = $dbh->prepare("INSERT INTO nickreg SET nick=?, pass=?, email=?, flags=".NRF_HIDEMAIL().", regd=UNIX_TIMESTAMP(), last=UNIX_TIMESTAMP()");
	$create_alias = $dbh->prepare("INSERT INTO nickalias SELECT id, ?, NULL, NULL FROM nickreg WHERE nick=?");

	$drop = $dbh->prepare("DELETE FROM nickreg WHERE nick=?");

	$get_aliases = $dbh->prepare("SELECT nickalias.alias FROM nickalias, nickreg WHERE
		nickalias.nrid=nickreg.id AND nickreg.nick=? ORDER BY nickalias.alias");
	$get_glist = $dbh->prepare("SELECT nickalias.alias, nickalias.protect, nickalias.last 
		FROM nickalias, nickreg WHERE
		nickalias.nrid=nickreg.id AND nickreg.nick=? ORDER BY nickalias.alias");
	$count_aliases = $dbh->prepare("SELECT COUNT(*) FROM nickalias, nickreg WHERE
		nickalias.nrid=nickreg.id AND nickreg.nick=?");
	$get_random_alias = $dbh->prepare("SELECT nickalias.alias FROM nickalias, nickreg WHERE
		nickalias.nrid=nickreg.id AND nickreg.nick=? AND nickalias.alias != nickreg.nick LIMIT 1");
	$delete_alias = $dbh->prepare("DELETE FROM nickalias WHERE alias=?");
	$delete_aliases = $dbh->prepare("DELETE FROM nickalias USING nickreg, nickalias WHERE
		nickalias.nrid=nickreg.id AND nickreg.nick=?");

	$get_all_access = $dbh->prepare("SELECT chanacc.chan, chanacc.level, chanacc.adder, chanacc.time FROM nickalias, chanacc WHERE chanacc.nrid=nickalias.nrid AND nickalias.alias=? ORDER BY chanacc.chan");
	$del_all_access = $dbh->prepare("DELETE FROM chanacc USING chanacc, nickreg WHERE chanacc.nrid=nickreg.id AND nickreg.nick=?");
	
	$change_root = $dbh->prepare("UPDATE nickreg SET nick=? WHERE nick=?");

	$unlock_tables = $dbh->prepare("UNLOCK TABLES");

	$get_matching_nicks = $dbh->prepare("SELECT nickalias.alias, nickreg.nick, nickreg.ident, nickreg.vhost FROM nickalias, nickreg WHERE nickalias.nrid=nickreg.id AND nickalias.alias LIKE ? AND nickreg.ident LIKE ? AND nickreg.vhost LIKE ? LIMIT 50");

	$cleanup_chanuser = $dbh->prepare("DELETE FROM chanuser USING chanuser
		LEFT JOIN user ON (chanuser.nickid=user.id) WHERE user.id IS NULL;");
	$cleanup_nickid = $dbh->prepare("DELETE FROM nickid USING nickid
		LEFT JOIN user ON(nickid.id=user.id)
		WHERE user.id IS NULL");
	$cleanup_users = $dbh->prepare("DELETE FROM user WHERE online=0 AND quittime>0 AND quittime<?");
	$get_dead_users = $dbh->prepare("SELECT id,nick,time,online,quittime FROM user
		WHERE online=0 AND quittime>0 AND quittime<?");

	$get_expired = $dbh->prepare("SELECT nickreg.nick, nickreg.email, nickreg.ident, nickreg.vhost
		FROM nickreg LEFT JOIN nickid ON(nickreg.id=nickid.nrid)
		LEFT JOIN svsop ON(nickreg.id=svsop.nrid)
		WHERE nickid.nrid IS NULL AND svsop.nrid IS NULL ".
		'AND ('.(services_conf_nearexpire ? 'nickreg.nearexp!=0 AND' : '').
		" ( !(nickreg.flags & " . NRF_HOLD . ") AND !(nickreg.flags & " . NRF_VACATION . ") AND nickreg.last<? ) OR
		( (nickreg.flags & " . NRF_VACATION . ") AND nickreg.last<? ) ) OR
		( (nickreg.flags & ". NRF_EMAILREG .") AND nickreg.last<?)");
	$get_near_expired = $dbh->prepare("SELECT nickreg.nick, nickreg.email, nickreg.flags, nickreg.last
		FROM nickreg LEFT JOIN nickid ON(nickreg.id=nickid.nrid) 
		LEFT JOIN svsop ON(nickreg.id=svsop.nrid)
		WHERE nickid.nrid IS NULL AND svsop.nrid IS NULL AND nickreg.nearexp=0 AND
		( ( !(nickreg.flags & " . NRF_HOLD . ") AND !(nickreg.flags & " . NRF_VACATION . ") AND nickreg.last<? ) OR
		( (nickreg.flags & " . NRF_VACATION . ") AND nickreg.last<? )
		)");
	$set_near_expired = $dbh->prepare("UPDATE nickreg SET nearexp=1 WHERE nick=?");

	$get_watches = $dbh->prepare("SELECT watch.mask, watch.time
		FROM watch
		JOIN nickalias ON (watch.nrid=nickalias.nrid)
		WHERE nickalias.alias=?");
	$check_watch = $dbh->prepare("SELECT 1
		FROM watch
		JOIN nickalias ON (watch.nrid=nickalias.nrid)
		WHERE nickalias.alias=? AND watch.mask=?");
	$set_watch = $dbh->prepare("INSERT INTO watch SELECT nrid, ?, ? FROM nickalias WHERE alias=?");
	$del_watch = $dbh->prepare("DELETE FROM watch USING watch
		JOIN nickalias ON (watch.nrid=nickalias.nrid)
		WHERE nickalias.alias=? AND watch.mask=?");
	$drop_watch = $dbh->prepare("DELETE FROM watch
		USING nickreg JOIN watch ON (watch.nrid=nickreg.id)
		WHERE nickreg.nick=?");
	$get_silences = $dbh->prepare("SELECT silence.mask, silence.time, silence.expiry, silence.comment
		FROM silence
		JOIN nickalias ON (silence.nrid=nickalias.nrid)
		WHERE nickalias.alias=? ORDER BY silence.time");
	$check_silence = $dbh->prepare("SELECT 1 FROM silence
		JOIN nickalias ON (silence.nrid=nickalias.nrid)
		WHERE nickalias.alias=? AND silence.mask=?");
	$set_silence = $dbh->prepare("INSERT INTO silence SELECT nrid, ?, ?, ?, ? FROM nickalias WHERE alias=?");
	$del_silence = $dbh->prepare("DELETE FROM silence USING silence, nickalias
		WHERE silence.nrid=nickalias.nrid AND nickalias.alias=? AND silence.mask=?");
	$drop_silence = $dbh->prepare("DELETE FROM silence USING nickreg, silence
		WHERE silence.nrid=nickreg.id AND nickreg.nick=?");
	$get_expired_silences = $dbh->prepare("SELECT nickreg.nick, silence.mask, silence.comment
		FROM nickreg
		JOIN silence ON (nickreg.id=silence.nrid)
		WHERE silence.expiry < UNIX_TIMESTAMP() AND silence.expiry!=0 ORDER BY nickreg.nick");
	$del_expired_silences = $dbh->prepare("DELETE silence.* FROM silence
		WHERE silence.expiry < UNIX_TIMESTAMP() AND silence.expiry!=0");
	$get_silence_by_num = $dbh->prepare("SELECT silence.mask, silence.time, silence.expiry, silence.comment
		FROM silence
		JOIN nickalias ON (silence.nrid=nickalias.nrid)
		WHERE nickalias.alias=? ORDER BY silence.time LIMIT 1 OFFSET ?");
	$get_silence_by_num->bind_param(2, 0, SQL_INTEGER);

	$get_seen = $dbh->prepare("SELECT nickalias.alias, nickreg.nick, nickreg.last FROM nickreg, nickalias 
		WHERE nickalias.nrid=nickreg.id AND nickalias.alias=?");

	$set_greet = $dbh->prepare("REPLACE INTO nicktext SELECT nickreg.id, ".NTF_GREET.", 0, NULL, ? 
		FROM nickreg, nickalias WHERE nickreg.id=nickalias.nrid AND nickalias.alias=?");
	$get_greet = $dbh->prepare("SELECT nicktext.data FROM nicktext, nickid
		WHERE nicktext.nrid=nickid.nrid AND nicktext.type=".NTF_GREET." AND nickid.id=?
		LIMIT 1");
	$get_greet_nick = $dbh->prepare("SELECT nicktext.data FROM nicktext, nickalias
		WHERE nicktext.nrid=nickalias.nrid AND nicktext.type=".NTF_GREET." AND nickalias.alias=?");
	$del_greet = $dbh->prepare("DELETE nicktext.* FROM nicktext, nickreg, nickalias WHERE
		nicktext.type=".NTF_GREET." AND nickreg.id=nickalias.nrid AND nickalias.alias=?");

	$get_num_nicktext_type = $dbh->prepare("SELECT COUNT(nicktext.id) FROM nicktext, nickalias
		WHERE nicktext.nrid=nickalias.nrid AND nickalias.alias=? AND nicktext.type=?");
	$drop_nicktext = $dbh->prepare("DELETE FROM nicktext USING nickreg
		JOIN nicktext ON (nicktext.nrid=nickreg.id)
		WHERE nickreg.nick=?");

	$get_auth_chan = $dbh->prepare("SELECT nicktext.data FROM nicktext, nickalias WHERE
		nicktext.nrid=nickalias.nrid AND nicktext.type=(".NTF_AUTH().") AND nickalias.alias=? AND nicktext.chan=?");
	$get_auth_num = $dbh->prepare("SELECT nicktext.chan, nicktext.data FROM nicktext, nickalias WHERE 
		nicktext.nrid=nickalias.nrid AND nicktext.type=(".NTF_AUTH().") AND nickalias.alias=? LIMIT 1 OFFSET ?");
	$get_auth_num->bind_param(2, 0, SQL_INTEGER);
	$del_auth = $dbh->prepare("DELETE nicktext.* FROM nicktext, nickalias WHERE
		nicktext.nrid=nickalias.nrid AND nicktext.type=(".NTF_AUTH().") AND nickalias.alias=? AND nicktext.chan=?");;
	$list_auth = $dbh->prepare("SELECT nicktext.chan, nicktext.data FROM nicktext, nickalias WHERE
		nicktext.nrid=nickalias.nrid AND nicktext.type=(".NTF_AUTH().") AND nickalias.alias=?");

	$del_nicktext = $dbh->prepare("DELETE nicktext.* FROM nickreg
		JOIN nickalias ON (nickalias.nrid=nickreg.id)
		JOIN nicktext ON (nicktext.nrid=nickreg.id)
		WHERE nicktext.type=? AND nickalias.alias=?");

	$set_umode_ntf = $dbh->prepare("REPLACE INTO nicktext SELECT nickreg.id, ".NTF_UMODE().", 1, ?, NULL
		FROM nickreg, nickalias WHERE nickreg.id=nickalias.nrid AND nickalias.alias=?");
	$get_umode_ntf = $dbh->prepare("SELECT nicktext.chan FROM nickreg, nickalias, nicktext
		WHERE nicktext.type=(".NTF_UMODE().") AND nicktext.nrid=nickalias.nrid AND nickalias.alias=?");

	$set_vacation_ntf = $dbh->prepare("INSERT INTO nicktext SELECT nickreg.id, ".NTF_VACATION().", 0, ?, NULL
		FROM nickreg, nickalias WHERE nickreg.id=nickalias.nrid AND nickalias.alias=?");
	$get_vacation_ntf = $dbh->prepare("SELECT nicktext.chan FROM nickalias, nicktext
		WHERE nicktext.nrid=nickalias.nrid AND nicktext.type=".NTF_VACATION()." AND nickalias.alias=?");

	$set_authcode_ntf = $dbh->prepare("REPLACE INTO nicktext SELECT nickreg.id, ".NTF_AUTHCODE().", 0, '', ?
		FROM nickreg, nickalias WHERE nickreg.id=nickalias.nrid AND nickalias.alias=?");
	$get_authcode_ntf = $dbh->prepare("SELECT 1 FROM nickalias, nicktext
		WHERE nicktext.nrid=nickalias.nrid AND nicktext.type=".NTF_AUTHCODE()." AND nickalias.alias=? AND nicktext.data=?");

	$get_nicks_by_email = $dbh->prepare("SELECT nickreg.nick, nickreg.ident, nickreg.vhost FROM nickreg
		WHERE nickreg.email LIKE ? GROUP BY nickreg.nick");

}
import SrSv::MySQL::Stub {
	add_profile_ntf => ['INSERT', "REPLACE INTO nicktext SELECT nickreg.id, @{[NTF_PROFILE]}, 0, ?, ?
		FROM nickreg JOIN nickalias ON (nickreg.id=nickalias.nrid) WHERE nickalias.alias=?"],
	get_profile_ntf => ['ARRAY', "SELECT chan, data FROM nicktext
		JOIN nickalias ON (nicktext.nrid=nickalias.nrid)
		WHERE nicktext.type=@{[NTF_PROFILE]} AND nickalias.alias=?"],
	del_profile_ntf => ['NULL', "DELETE nicktext.* FROM nicktext
		JOIN nickalias ON (nicktext.nrid=nickalias.nrid)
		WHERE nicktext.type=@{[NTF_PROFILE]} AND nickalias.alias=? AND nicktext.chan=?"],
	wipe_profile_ntf => ['NULL', "DELETE nicktext.* FROM nicktext
		JOIN nickalias ON (nicktext.nrid=nickalias.nrid)
		WHERE nicktext.type=@{[NTF_PROFILE]} AND nickalias.alias=?"],
	count_profile_ntf => ['SCALAR', "SELECT COUNT(chan) FROM nicktext
		JOIN nickalias ON (nicktext.nrid=nickalias.nrid)
		WHERE nicktext.type=@{[NTF_PROFILE]} AND nickalias.alias=?"],

	protect_level => ['SCALAR', 'SELECT protect FROM nickalias WHERE alias=?'],
	get_pass => ['SCALAR', "SELECT nickreg.pass
		FROM nickreg JOIN nickalias ON (nickreg.id=nickalias.nrid)
		WHERE nickalias.alias=?"],
	get_email => ['SCALAR', "SELECT nickreg.email
		FROM nickalias JOIN nickreg ON (nickreg.id=nickalias.nrid)
		WHERE nickalias.alias=?"],
	count_silences => ['SCALAR', "SELECT COUNT(silence.nrid) FROM silence
		JOIN nickalias ON (silence.nrid=nickalias.nrid)
		WHERE nickalias.alias=?"],
	count_watches => ['SCALAR', "SELECT COUNT(watch.nrid) FROM watch
		JOIN nickalias ON (watch.nrid=nickalias.nrid)
		WHERE nickalias.alias=?"],

	add_autojoin_ntf => ['INSERT', "INSERT INTO nicktext
		SELECT nickreg.id, @{[NTF_JOIN]}, 0, ?, NULL
		FROM nickreg JOIN nickalias ON (nickreg.id=nickalias.nrid)
		WHERE nickalias.alias=?"],
	get_autojoin_ntf => ['COLUMN', "SELECT chan
		FROM nicktext
		JOIN nickalias ON (nicktext.nrid=nickalias.nrid)
		WHERE nicktext.type=@{[NTF_JOIN]} AND nickalias.alias=?"],
	wipe_autojoin_ntf => ['NULL', "DELETE nicktext.* FROM nickreg
		JOIN nickalias ON (nickalias.nrid=nickreg.id)
		JOIN nicktext ON (nicktext.nrid=nickreg.id)
		WHERE nicktext.type=@{[NTF_JOIN]} AND nickalias.alias=?"],
	del_autojoin_ntf => ['NULL', "DELETE nicktext.* FROM nickreg
		JOIN nickalias ON (nickalias.nrid=nickreg.id)
		JOIN nicktext ON (nicktext.nrid=nickreg.id)
		WHERE nicktext.type=@{[NTF_JOIN]} AND nickalias.alias=? AND nicktext.chan=?"],
	check_autojoin_ntf => ['SCALAR', "SELECT 1 FROM nicktext
		JOIN nickalias ON (nicktext.nrid=nickalias.nrid)
		WHERE nicktext.type=@{[NTF_JOIN]} AND nickalias.alias=? AND nicktext.chan=?"],
	get_autojoin_by_num => ['SCALAR', "SELECT nicktext.chan
		FROM nicktext
		JOIN nickalias ON (nicktext.nrid=nickalias.nrid)
		WHERE nicktext.type=@{[NTF_JOIN]} AND nickalias.alias=? LIMIT 1 OFFSET ?"],
};


### NICKSERV COMMANDS ###

sub ns_ajoin_list($$) {
	my ($user, $nick) = @_;
	my @data;
	my $i = 0;
	foreach my $chan (get_autojoin_ntf($nick)) {
		push @data, [++$i, $chan];
	}

	notice( $user, columnar( {TITLE => "Channels in \002$nick\002's ajoin",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data ) );
}
sub ns_ajoin_del($$@) {
	my ($user, $nick, @args) = @_;
	my ($subj, $obj);
	if(lc(get_user_nick($user)) eq lc($nick)) {
		$subj='your';
		$obj='you';
	} else {
		$subj="\002$nick\002\'s";
		$obj="\002$nick\002";
	}
	my @entries;
	foreach my $arg (@args) {
		if ($arg =~ /^[0-9\.,-]+$/) {
			foreach my $num (makeSeqList($arg)) {
				if(my $chan = get_autojoin_by_num($nick, $num - 1)) {
					push @entries, $chan;
				} else {
					notice($user, "No entry \002#$num\002 was found in $subj ajoin list");
				}
			}
		} elsif($arg =~ /^#.*?,#/) {
			push @entries, split(',', $arg);
		} else {
			push @entries, $arg;
		}
	}
	foreach my $entry (@entries) {
		if(check_autojoin_ntf($nick, $entry)) {
			del_autojoin_ntf($nick, $entry);
			notice($user,"Successfully removed \002$entry\002 from $subj ajoin list.");
		}
		else {
			notice($user, "\002$entry\002 was not in $subj ajoin!");
		}
	}
}
sub ns_ajoin_wipe($$) {
	my ($user, $nick) = @_;
	my ($subj, $obj);
	if(lc(get_user_nick($user)) eq lc($nick)) {
		$subj='your';
		$obj='you';
	} else {
		$subj="\002$nick\002\'s";
		$obj="\002$nick\002";
	}
	my $count = wipe_autojoin_ntf($nick);
	if($count) {
		notice($user,"Successfully wiped \002$count\002 entries from $subj ajoin list.");
	} else {
		notice($user,"No entries deleted.");
	}
}

sub ns_ajoin_join($$) {
	my ($user, $nick) = @_;
	#ns_ajoin_list($user, $nick);
	do_ajoin($user, $nick);
}

sub ns_ajoin($@) {
	my ($user, @args) = @_;
	my $nick;
	my $src = get_user_nick($user);
	my @chans = grep(/^(#|\d)/, @args);
	my @parms = grep(!/^(#|\d)/, @args);
	if(scalar(@parms) > 1) {
		$nick = shift @parms;
	} else {
		$nick = $src;
	}
	my $cmd = shift @parms;
	my ($subj, $obj);
	if(lc($src) eq lc($nick)) {
		$subj='Your';
		$obj='You';
	} else {
		$subj="\002$nick\002\'s";
		$obj="\002$nick\002";
	}

	my $override = adminserv::can_do($user, 'SERVOP');
	if(is_identified($user, $nick) || $override) {
		if(!is_registered($src)) {
			notice($user, "\002$nick\002 is not registered.");
			return;
		}
	} else {
		notice($user, "Permission denied for \002$nick\002");
		return;
	}
	if ($cmd =~ /^add$/i) {
		if(!scalar(@chans)) {
			notice($user, "Syntax: \002AJOIN ADD #channel\002");
			notice ($user, "Type \002/msg NickServ HELP AJOIN\002 for more help");
		}
		foreach my $chanlist (@chans) {
			if (defined($chanlist) && $chanlist !~ /^#/) {
				$chanlist = "#" . $chanlist; 
			}
			foreach my $chan (split(',', $chanlist)) {
				if(check_autojoin_ntf($nick, $chan)) {
					notice ($user, $chan . " is already in $subj ajoin list! ");
					next;
				} else {
					add_autojoin_ntf($chan, $nick);
					notice($user, "\002$chan\002 added to $subj ajoin.");
				}
			}
		}
	}
	elsif ($cmd =~ /^list$/i) {
		ns_ajoin_list($user, $nick);
	}
	elsif ($cmd =~ /^join$/i) {
		ns_ajoin_join($user, $nick);
	}
	elsif ($cmd =~ /^del(ete)?$/i) {
		ns_ajoin_del($user, $nick, @chans);
	}
	elsif ($cmd =~ /^(clear|wipe)$/i) {
		ns_ajoin_wipe($user, $nick);
	}
	else {
		notice($user,"Syntax: AJOIN ADD/DEL/LIST/WIPE");
		notice ($user,"Type \002/msg NickServ HELP AJOIN\002 for more help!");
	}
}

our %high_priority_cmds = (
	'id' => 1,
	'identify' => 1,
	'sid' => 1,
	'sidentify' => 1,
	'gidentify' => 1,
	'ghost' => 1,
);

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

	if($cmd =~ /^help$/i) {
		sendhelp($user, 'nickserv', @args)
	}
	elsif ($cmd =~ /^ajoin$/i) {
		ns_ajoin($user, shift @args, @args);
	}
	elsif($cmd =~ /^id(entify)?$/i) {
		if(@args == 1) {
			ns_identify($user, $src, $args[0]);
		} elsif(@args == 2) {
			ns_identify($user, $args[0], $args[1]);
		} else {
			notice($user, 'Syntax: IDENTIFY [nick] <password>');
		}
	}
	elsif($cmd =~ /^sid(entify)?$/i) {
		if(@args == 2) {
			ns_identify($user, $args[0], $args[1], 1);
		} else {
			notice($user, 'Syntax: SIDENTIFY <nick> <password>');
		}
	}
	elsif($cmd =~ /^gid(entify)?$/i) {
		if(@args == 2) {
			ns_identify($user, $args[0], $args[1], 2);
		} else {
			notice($user, 'Syntax: GIDENTIFY <nick> <password>');
		}
	}
	elsif($cmd =~ /^logout$/i) {
		ns_logout($user);
	}
	elsif($cmd =~ /^release$/i) {
		if(@args == 1) {
			ns_release($user, $args[0]);
		} elsif(@args == 2) {
			ns_release($user, $args[0], $args[1]);
		} else {
			notice($user, 'Syntax: RELEASE <nick> [password]');
		}
	}
	elsif($cmd =~ /^ghost$/i) {
		if(@args == 1) {
			ns_ghost($user, $args[0]);
		} elsif(@args == 2) {
			ns_ghost($user, $args[0], $args[1]);
		} else {
			notice($user, 'Syntax: GHOST <nick> [password]');
		}
	}
	elsif($cmd =~ /^register$/i) {
		if(@args == 2) {
			ns_register($user, $args[0], $args[1]);
		} else {
			notice($user, 'Syntax: REGISTER <password> <email>');
		}
	}
	elsif($cmd =~ /^(?:link|group)$/i) {
		if(@args == 2) {
			ns_link($user, $args[0], $args[1]);
		} else {
			notice($user, 'Syntax: LINK <nick> <password>');
		}
	}
	elsif($cmd =~ /^info$/i) {
		if(@args >= 1) {
			ns_info($user, @args);
		} else {
			notice($user, 'Syntax: INFO <nick> [nick ...]');
		}
	}
	elsif($cmd =~ /^set$/i) {
		ns_set_parse($user, @args);
	}
	elsif($cmd =~ /^(drop|unlink)$/i) {
		if(@args == 1) {
			ns_unlink($user, $src, $args[0]);
		}
		elsif(@args == 2) {
			ns_unlink($user, $args[0], $args[1]);
		}
		else {
			notice($user, 'Syntax: UNLINK [nick] <password>');
		}
	}
	elsif($cmd =~ /^dropgroup$/i) {
		if(@args == 1) {
			ns_dropgroup($user, $src, $args[0]);
		}
		elsif(@args == 2) {
			ns_dropgroup($user, $args[0], $args[1]);
		}
		else {
			notice($user, 'Syntax: DROPGROUP [nick] <password>');
		}
	}
	elsif($cmd =~ /^chgroot$/i) {
		if(@args == 1) {
			ns_changeroot($user, $src, $args[0]);
		}
		elsif(@args == 2) {
			ns_changeroot($user, $args[0], $args[1]);
		}
		else {
			notice($user, 'Syntax: CHGROOT [oldroot] <newroot>');
		}
	}
	elsif($cmd =~ /^sendpass$/i) {
		if(@args == 1) {
			ns_sendpass($user, $args[0]);
		} else {
			notice($user, 'Syntax: SENDPASS <nick>');
		}
	}
	elsif($cmd =~ /^(?:glist|links)$/i) {
		if(@args == 0) {
			ns_glist($user, $src);
		}
		elsif(@args >= 1) {
			ns_glist($user, @args);
		}
		else {
			notice($user, 'Syntax: GLIST [nick] [nick ...]');
		}
	}
	elsif($cmd =~ /^(?:alist|listchans)$/i) {
		if(@args == 0) {
			ns_alist($user, $src);
		}
		elsif(@args >= 1) {
			ns_alist($user, @args);
		}
		else {
			notice($user, 'Syntax: ALIST [nick] [nick ...]');
		}
	}
	elsif($cmd =~ /^list$/i) {
		if(@args == 1) {
			ns_list($user, $args[0]);
		} else {
			notice($user, 'Syntax: LIST <mask>');
		}
	}
	elsif($cmd =~ /^watch$/i) {
		if ($args[0] =~ /^(add|del|list)$/i) {
			ns_watch($user, $src, @args);
		}
		elsif ($args[1] =~ /^(add|del|list)$/i) {
			ns_watch($user, @args);
		}
		else {
			notice($user, 'Syntax: WATCH <ADD|DEL|LIST> [nick]');
		}
	}
	elsif($cmd =~ /^silence$/i) {
		if ($args[0] =~ /^(add|del|list)$/i) {
			ns_silence($user, $src, @args);
		}
		elsif ($args[1] =~ /^(add|del|list)$/i) {
			ns_silence($user, @args);
		}
		else {
			notice($user, 'Syntax: SILENCE [nick] <ADD|DEL|LIST> [mask] [+expiry] [comment]');
		}
	}
	elsif($cmd =~ /^(acc(ess)?|stat(us)?)$/i) {
		if (@args >= 1) {
			ns_acc($user, @args);
		}
		else {
			notice($user, 'Syntax: ACC <nick>  [nick ...]');
		}
	}
	elsif($cmd =~ /^seen$/i) {
		if(@args >= 1) {
			ns_seen($user, @args);
		}
		else {
			notice($user, 'Syntax: SEEN <nick> [nick ...]');
		}
	}
	elsif($cmd =~ /^recover$/i) {
		if(@args == 1) {
			ns_recover($user, $args[0]);
		} elsif(@args == 2) {
			ns_recover($user, $args[0], $args[1]);
		} else {
			notice($user, 'Syntax: RECOVER <nick> [password]');
		}
	}
	elsif($cmd =~ /^auth$/i) {
		if (@args >= 1) {
			ns_auth($user, @args);
		}
		else {
			notice($user, 'Syntax: AUTH [nick] <LIST|ACCEPT|DECLINE> [num|chan]');
		}
	}
	elsif($cmd =~ /^(?:emailreg|(?:auth|email)code)$/i) {
		if(scalar(@args) >= 2 and scalar(@args) <= 3) {
			ns_authcode($user, @args);
		} else {
			notice($user, 'Syntax: AUTHCODE <nick> <code> [newpassword]');
		}
	}
	elsif($cmd =~ /^profile$/i) {
		ns_profile($user, @args);
	}
	elsif($cmd =~ /^liste?mail/i) {
		if ($#args == 0) {
			ns_listemail($user, $args[0]);
		} else {
			notice($user, 'Syntax: LISTEMAIL <email@domain.tld>');
		}
	}
	else {
		notice($user, "Unrecognized command.", "For help, type: \002/msg nickserv help\002");
		wlog($nsnick, LOG_DEBUG(), "$src tried to use NickServ $msg");
	}
}

sub ns_identify($$$;$) {
	my ($user, $nick, $pass, $svsnick) = @_;
	my $src = get_user_nick($user);

	my $root = get_root_nick($nick);
	unless($root) {
		notice($user, 'Your nick is not registered.');
		return 0;
	}

	if($svsnick) {
		if(lc($src) ne lc($nick) and is_online($nick)) {
			if($svsnick == 2) {
				ns_ghost($user, $nick, $pass) or return;
			} else {
				notice($user, $nick.' is already in use. Please use GHOST, GIDENTIFY or RECOVER');
				$svsnick = 0;
			}
		}
		if (is_identified($user, $nick)) {
			if(lc $src eq lc $nick) {
				notice($user, "Cannot only change case of nick");
				return;
			}
			ircd::svsnick($nsnick, $src, $nick);
			ircd::setumode($nsnick, $nick, '+r');
			return 1;
		}
	}
	# cannot be an else, note change of $svsnick above.
	if (!$svsnick and is_identified($user, $nick)) {
		notice($user, 'You are already identified for nick '.$nick.'.');
		return 0;
	}

	my $flags = nr_get_flags($root);

	if($flags & NRF_FREEZE) {
		notice($user, "This nick has been frozen and may not be used.", $err_deny);
		services::ulog($nsnick, LOG_INFO(), "\00305attempted to identify to frozen nick \003\002$nick\002", $user);
		return;
	}

	if($flags & NRF_EMAILREG) {
		notice($user, "This nick is awaiting an email validation code. Please check your email for instructions.");
		return;
	}

	elsif($flags & NRF_SENDPASS) {
		notice($user, "This nick is awaiting a SENDPASS authentication code. Please check your email for instructions.");
		return;
	}

	my $uid = get_user_id($user);
	unless(chk_pass($root, $pass, $user)) {
		if(inc_nick_inval($user)) {
			notice($user, $err_pass);
		}
		services::ulog($nsnick, LOG_INFO(), "failed to identify to nick $nick (root: $root)", $user);
		return 0;
	}

	return do_identify($user, $nick, $root, $flags, $svsnick);
}

sub ns_logout($) {
	my ($user) = @_;
	my $uid = get_user_id($user);
	
	$update_lastseen->execute($uid);
	$logout->execute($uid);
	delete($user->{NICKFLAGS});
	ircd::nolag($nsnick, '-', get_user_nick($user));
	notice($user, 'You are now logged out');
	services::ulog($nsnick, LOG_INFO(), "used NickServ LOGOUT", $user);
}

sub ns_release($$;$) {
	my ($user, $nick, $pass) = @_;

	if(nr_chk_flag($nick, NRF_FREEZE)) {
		notice($user, "This nick has been frozen and may not be used.", $err_deny);
		services::ulog($nsnick, LOG_INFO(), "\00305attempted to release frozen nick \003\002$nick\002", $user);
		return;
	}

	unless(is_identified($user, $nick)) {
		if($pass) {
			my $s = ns_identify($user, $nick, $pass);
			return if($s == 0); #failed to identify
			if($s == 1) {
				notice($user, "Nick $nick is not being held.");
				return;
			}
		} else {
			notice($user, $err_deny);
			return;
		}
	}
	elsif(enforcer_quit($nick)) {
		notice($user, 'Your nick has been released from custody.');
	} else {
		notice($user, "Nick $nick is not being held.");
	}
}

sub ns_ghost($$;$) {

my @ghostbusters_quotes = (
	'Ray. If someone asks if you are a god, you say, "yes!"',
	'I feel like the floor of a taxicab.',
	'I don\'t have to take this abuse from you, I\'ve got hundreds of people dying to abuse me.',
	'He slimed me.',
	'This chick is *toast*.',
	'"Where do these stairs go?" "They go up."',
	'"That\'s the bedroom, but nothing ever happened in there." "What a crime."',
	'NOBODY steps on a church in my town.',
	'Whoa, whoa, whoa! Nice shootin\', Tex!',
	'It\'s the Stay Puft Marshmallow Man.',
	'"Symmetrical book stacking. Just like the Philadelphia mass turbulence of 1947." "You\'re right, no human being would stack books like this."',
	'"Egon, this reminds me of the time you tried to drill a hole through your head. Remember that?" "That would have worked if you hadn\'t stopped me."',
	'"Ray has gone bye-bye, Egon... what\'ve you got left?" "Sorry, Venkman, I\'m terrified beyond the capacity for rational thought."',
	'Listen! Do you smell something?',
	'As they say in T.V., I\'m sure there\'s one big question on everybody\'s mind, and I imagine you are the man to answer that. How is Elvis, and have you seen him lately?',
	'"You know, you don\'t act like a scientist." "They\'re usually pretty stiff." "You\'re more like a game show host."',
);
	my ($user, $nick, $pass) = @_;
	my $src = get_user_nick($user);

	if(nr_chk_flag($nick, NRF_FREEZE)) {
		notice($user, "This nick has been frozen and may not be used.", $err_deny);
		services::ulog($nsnick, LOG_INFO(), "\00305attempted to ghost frozen nick \003\002$nick\002", $user);
		return 0;
	}

	unless(is_identified($user, $nick)) {
		if($pass) {
			my $s = ns_identify($user, $nick, $pass);
			return 0 if($s == 0); #failed to identify
		} else {
			notice($user, $err_deny);
			return 0;
		}
	}

	if(!is_online($nick)) {
		notice($user, "\002$nick\002 is not online");
		return 0;
	} elsif(lc $src eq lc $nick) {
		notice($user, "I'm sorry, $src, I'm afraid I can't do that.");
		return 0;

	} else {
		my $ghostbusters = @ghostbusters_quotes[int rand(scalar(@ghostbusters_quotes))];
		ircd::irckill($nsnick, $nick, "GHOST command used by $src ($ghostbusters)");
		notice($user, "Your ghost has been disconnected");
		services::ulog($nsnick, LOG_INFO(), "used NickServ GHOST on $nick", $user);
		#nick_delete($nick);
		return 1;
	}
}

sub ns_register($$$) {
	my ($user, $pass, $email) = @_;
	my $src = get_user_nick($user);
	
	if($src =~ /^guest/i) {
		notice($user, $err_deny);
		return;
	}
	
	unless(validate_email($email)) {
		notice($user, $err_email);
		return;
	}

	if ($pass =~ /pass/i) {
		notice($user, 'Try a more secure password.');
		return;
	}
	
	my $uid = get_user_id($user);
	
	$get_register_lock->execute; $get_register_lock->finish;
	
	if(not is_registered($src)) {
		$register->execute($src, hash_pass($pass), $email); $register->finish();
		$create_alias->execute($src, $src); $create_alias->finish;
		if (defined(services_conf_default_protect)) {
			$set_protect_level->execute((defined(services_conf_default_protect) ?
				$protect_level{lc services_conf_default_protect} : 1), $src);
			$set_protect_level->finish();
		}
		$unlock_tables->execute; $unlock_tables->finish;
		
		if(services_conf_validate_email) {
			nr_set_flag($src, NRF_EMAILREG());
			authcode($src, 'emailreg', $email);
			notice($user, "Your registration is not yet complete.", 
				"Your nick will expire within ".
				(services_conf_validate_expire == 1 ? '24 hours' : services_conf_validate_expire.' days').
				" if you do not enter the validation code.",
				"Check your email for further instructions.");
		}
		else {
			$identify->execute($uid, $src); $identify->finish();
			notice($user, 'You are now registered and identified.');
			ircd::setumode($nsnick, $src, '+r');
		}
		
		$id_update->execute($src, $uid); $id_update->finish();
		services::ulog($nsnick, LOG_INFO(), "registered $src (email: $email)".
			(services_conf_validate_email ? ' requires email validation code' : ''),
			$user);
	} else {
		$unlock_tables->execute; $unlock_tables->finish;
		notice($user, 'Your nickname has already been registered.');
	}
}

sub ns_link($$$) {
	my ($user, $nick, $pass) = @_;

	my $root = get_root_nick($nick);
	my $src = get_user_nick($user);
	my $uid = get_user_id($user);

	if($src =~ /^guest/i) {
		notice($user, $err_deny);
		return;
	}

	unless (is_registered($nick)) {
		if(is_registered($src)) {
			notice($user, "The nick \002$nick\002 is not registered. You need to change your nick to \002$nick\002 and then link to \002$src\002.");
		} else { # if neither $nick nor $src are registered
			notice($user, "You need to register your nick first. For help, type \002/ns help register");
		}
		return;
	}

	unless(chk_pass($root, $pass, $user)) {
		notice($user, $err_pass);
		return;
	}

	if(nr_chk_flag($nick, NRF_FREEZE) and (lc $pass ne 'force')) {
		notice($user, "\002$root\002 has been frozen and may not be used.");
		return;
	}

	if(is_alias_of($src, $nick)) {
		notice($user, "\002$nick\002 is already linked to \002$src\002.");
		return;
	}

	$get_register_lock->execute; $get_register_lock->finish;
		
	if(is_registered($src)) {
		$unlock_tables->execute; $unlock_tables->finish;
		
		if(is_identified($user, $src)) {
			notice($user, "You cannot link an already registered nick. Type this and try again: \002/ns drop $src <password>");
			return;
		} else {
			notice($user, 'Your nickname has already been registered.');
			return;
		}
	} else {
		$create_alias->execute($src, $root); $create_alias->finish();
		if (defined(services_conf_default_protect)) {
			$set_protect_level->execute((defined(services_conf_default_protect) ?
				$protect_level{lc services_conf_default_protect} : 1), $src);
			$set_protect_level->finish();
		}
		$unlock_tables->execute; $unlock_tables->finish;
		
		if(is_identified($user, $root)) {
			$identify_ign->execute($uid, $root); $identify_ign->finish();
			$id_update->execute($root, $uid); $id_update->finish();
		} else {
			ns_identify($user, $root, $pass);
		}
	}
	
	notice($user, "\002$src\002 is now linked to \002$root\002.");
	services::ulog($nsnick, LOG_INFO(), "made $src an alias of $root.", $user);

	check_identify($user);
}

sub ns_unlink($$$) {
	my ($user, $nick, $pass) = @_;
	my $uid = get_user_id($user);
	my $src = get_user_nick($user);
	
	my $root = get_root_nick($nick);
	unless(chk_pass($root, $pass, $user)) {
		notice($user, $err_pass);
		return;
	}

	if(nr_chk_flag($nick, NRF_FREEZE) and (lc $pass ne 'force')) {
		notice($user, "\002$root\002 has been frozen and may not be used.", $err_deny);
		services::ulog($nsnick, LOG_INFO(), "\00305attempted to unlink \002$nick\002 from frozen nick \002$root\002", $user);
		return;
	}

	if(lc $root eq lc $nick) {
		$count_aliases->execute($root);
		my ($count) = $count_aliases->fetchrow_array;
		if($count == 1) {
			ns_dropgroup_real($user, $root);
			return;
		}

		$get_random_alias->execute($root);
		my ($new) = $get_random_alias->fetchrow_array;
		ns_changeroot($user, $root, $new, 1);
		
		$root = $new;
	}
	
	unidentify_single($nick);
	delete_alias($nick);
	enforcer_quit($nick);
	
	notice($user, "\002$nick\002 has been unlinked from \002$root\002.");
	services::ulog($nsnick, LOG_INFO(), "removed alias $nick from $root.", $user);
}

sub ns_dropgroup($$$) {
	my ($user, $nick, $pass) = @_;
	my $uid = get_user_id($user);
	my $src = get_user_nick($user);
	my $root = get_root_nick($nick);

	if(adminserv::get_svs_level($root)) {
		notice($user, "A nick with services access may not be dropped.");
		return;
	}

	unless(chk_pass($root, $pass, $user)) {
		notice($user, $err_pass);
		return;
	}

	if(nr_chk_flag($nick, NRF_FREEZE) and (lc $pass ne 'force')) {
		notice($user, "This nick has been frozen and may not be used.", $err_deny);
		services::ulog($nsnick, LOG_INFO(), "\00305attempted to dropgroup frozen nick \002$root\002", $user);
		return;
	}

	ns_dropgroup_real($user, $root);
}

sub ns_dropgroup_real($$) {
	my ($user, $root) = @_;
	my $src = get_user_nick($user);
	
	unidentify($root, "Your nick, \002$root\002, was dropped by \002$src\002.", $src);
	dropgroup($root);
	#enforcer_quit($nick);
	notice($user, "Your nick(s) have been dropped.  Thanks for playing.");
	
	services::ulog($nsnick, LOG_INFO(), "dropped group $root.", $user);
}

sub ns_changeroot($$$;$) {
	my ($user, $old, $new, $force) = @_;

	$force or chk_identified($user, $old) or return;

	my $root = get_root_nick($old);
	
	if(lc($new) eq lc($root)) {
		notice($user, "\002$root\002 is already your root nick.");
		return;
	}
	
	unless(get_root_nick($new) eq $root) {
		notice($user, "\002$new\002 is not an alias of your nick.  Type \002/msg nickserv help link\002 for information about creating aliases.");
		return;
	}

	changeroot($root, $new);

	notice($user, "Your root nick is now \002$new\002.");
	services::ulog($nsnick, LOG_INFO(), "changed root $root to $new.", $user);
}

sub ns_info($@) {
	my ($user, @nicks) = @_;

	foreach my $nick (@nicks) {
		my $root = get_root_nick($nick);
	
		$get_info->execute($nick);
		my @result = $get_info->fetchrow_array;
		$get_info->finish();

		unless(@result) {
			notice($user, "The nick \002$nick\002 is not registered.");
			next;
		}
	
		my ($email, $regd, $last, $flags, $ident, $vhost, $gecos, $alias_used) = @result;
		# the quit entry might not exist if the user hasn't quit yet.
		$get_nickreg_quit->execute($nick);
		my ($quit) = $get_nickreg_quit->fetchrow_array(); $get_nickreg_quit->finish();
		my $hidemail = $flags & NRF_HIDEMAIL;

		$get_greet_nick->execute($nick);
		my ($greet) = $get_greet_nick->fetchrow_array(); $get_greet_nick->finish();
		$get_umode_ntf->execute($nick);
		my ($umode) = $get_umode_ntf->fetchrow_array(); $get_umode_ntf->finish();

		my $svslev = adminserv::get_svs_level($root);
		my $protect = protect_level($nick);
		my $showprivate = (is_identified($user, $nick) or
			adminserv::is_svsop($user, adminserv::S_HELP()));
	
		my ($seens, $seenm) = do_seen($nick);

		my @data;
		
		push @data, {FULLROW=>"(Online now, $seenm.)"} if $seens == 2;
		push @data, ["Last seen:", "$seenm."] if $seens == 1;
		
		push @data,
			["Last seen address:", "$ident\@$vhost"],
			["Registered:", gmtime2($regd)];
		push @data, ["Last used:", ($alias_used ? gmtime2($alias_used) : 'Unknown')] if $showprivate;
		push @data, ["Last real name:", $gecos];
		
		push @data, ["Services Rank:", $adminserv::levels[$svslev]] 
			if $svslev;
		push @data, ["E-mail:", $email] unless $hidemail;
		push @data, ["E-mail:", "$email (Hidden)"] 
			if($hidemail and $showprivate);
		push @data, ["Alias of:", $root] 
			if ((lc $root ne lc $nick) and $showprivate);

		my @extra;

		push @extra, "Last quit: $quit" if $quit;
		push @extra, $protect_long[$protect] if $protect;
		push @extra, "Does not accept memos." if($flags & NRF_NOMEMO);
		push @extra, "Cannot be added to channel access lists." if($flags & NRF_NOACC);
		push @extra, "Will not be automatically opped in channels." if($flags & NRF_NEVEROP);
		push @extra, "Requires authorization to be added to channel access lists."
			if($flags & NRF_AUTH);
		push @extra, "Is frozen and may not be used." if($flags & NRF_FREEZE);
		push @extra, "Will not expire." if($flags & NRF_HOLD);
		push @extra, "Is currently on vacation." if($flags & NRF_VACATION);
		push @extra, "Registration pending email-code verification." if($flags & NRF_EMAILREG);
		push @extra, "UModes on Identify: ".$umode if ($umode and $showprivate);
		push @extra, "Greeting: ".$greet if ($greet and $showprivate);
		push @extra, "Disabled highlighting of alternating lines." if ($flags & NRF_NOHIGHLIGHT);

		notice($user, columnar({TITLE => "NickServ info for \002$nick\002:",
			NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)},
			@data, {COLLAPSE => \@extra, BULLET => 1}));
	}
}

sub ns_set_parse($@) {
	my ($user, @parms) = @_;
	my $src = get_user_nick($user);
# This is a new NS SET parser
# required due to it's annoying syntax
#
# Most commands have only 2 params at most
# the target (which is implied to be src when not spec'd)
# However in the case of GREET num-params is unbounded
#
# Alternative parsings would be possible,
# one being to use a regexp for valid set/keys
	if (lc($parms[1]) eq 'greet') {
		ns_set($user, @parms);
	}
	elsif(lc($parms[0]) eq 'greet') {
		ns_set($user, $src, @parms);
	}
	else {
		if(@parms == 2) {
			ns_set($user, $src, $parms[0], $parms[1]);
		}
		elsif(@parms == 3) {
			ns_set($user, $parms[0], $parms[1], $parms[2]);
		}
		else {
			notice($user, 'Syntax: SET [nick] <option> <value>');
			return;
		}
	}
}

sub ns_set($$$$) {
	my ($user, $target, $set, @parms) = @_;
	my $src = get_user_nick($user);
	my $override = (adminserv::can_do($user, 'SERVOP') or
		(adminserv::can_do($user, 'FREEZE') and $set =~ /^freeze$/i) ? 1 : 0);
	
	unless(is_registered($target)) {
		notice($user, "\002$target\002 is not registered.");
		return;
	}
	unless(is_identified($user, $target) or $override) {
		notice($user, $err_deny);
		return;
	}

	unless (
		$set =~ /^protect$/i or
		$set =~ /^e?-?mail$/i or
		$set =~ /^pass(?:w(?:or)?d)?$/i or
		$set =~ /^hidee?-?mail$/i or
		$set =~ /^nomemo$/i or
		$set =~ /^no(?:acc|op)$/i or
		$set =~ /^neverop$/i or
		$set =~ /^auth$/i or
		$set =~ /^(hold|no-?expire)$/i or 
		$set =~ /^freeze$/i or
		$set =~ /^vacation$/i or
		$set =~ /^greet$/i or
		$set =~ /^u?modes?$/i or
		$set =~ /^(email)?reg$/i or
		$set =~ /^nohighlight$/i or
		$set =~ /^(?:(?:chg)?root|display)$/i
	) {
		notice($user, qq{"$set" is not a valid NickServ setting.});
		return;
	}

	my ($subj, $obj);
	if($src eq $target) {
		$subj='Your';
		$obj='You';
	} else {
		$subj="\002$target\002\'s";
		$obj="\002$target\002";
	}
	delete($user->{NICKFLAGS});

	if($set =~ /^protect$/i) {
		my $level = $protect_level{lc shift @parms};
		unless (defined($level)) {
			notice($user, "Syntax: SET PROTECT <none|normal|high|kill>");
			return;
		}
		
		$set_protect_level->execute($level, $target);
		notice($user, "$subj protection level is now set to \002".$protect_short[$level]."\002. ".$protect_long[$level]);

		return;
	}

	elsif($set =~ /^e?-?mail$/i) {
		unless(@parms == 1) {
			notice($user, 'Syntax: SET EMAIL <address>');
			return;
		}
		my $email = $parms[0];
		
		unless(validate_email($email)) {
			notice($user, $err_email);
			return;
		}

		$set_email->execute($email, $target);
		notice($user, "$subj email address has been changed to \002$email\002.");
		services::ulog($nsnick, LOG_INFO(), "changed email of \002$target\002 to $email", $user);

		return;
	}

	elsif($set =~ /^pass(?:w(?:or)?d)?$/i) {
		unless(@parms == 1) {
			notice($user, 'Syntax: SET PASSWD <address>');
			return;
		}
		if($parms[0] =~ /pass/i) {
			notice($user, 'Try a more secure password.');
		}

		$set_pass->execute(hash_pass($parms[0]), $target);
		notice($user, "$subj password has been changed.");
		services::ulog($nsnick, LOG_INFO(), "changed password of \002$target\002", $user);
		if(nr_chk_flag($target,  NRF_SENDPASS())) {
			$del_nicktext->execute(NTF_AUTHCODE, $target); $del_nicktext->finish();
			nr_set_flag($target, NRF_SENDPASS(), 0);
		}

		return;
	}

	elsif($set =~ /^greet$/i) {
		unless(@parms) {
			notice($user, 'Syntax: SET [nick] GREET <NONE|greeting>');
			return;
		}

		my $greet = join(' ', @parms);
		if ($greet =~ /^(none|off)$/i) {
			$del_greet->execute($target);
			notice($user, "$subj greet has been deleted.");
			services::ulog($nsnick, LOG_INFO(), "deleted greet of \002$target\002", $user);
		}
		else {
			$set_greet->execute($greet, $target);
			notice($user, "$subj greet has been set to \002$greet\002");
			services::ulog($nsnick, LOG_INFO(), "changed greet of \002$target\002", $user);
		}

		return;
	}
	elsif($set =~ /^u?modes?$/i) {
		unless(@parms == 1) {
			notice($user, 'Syntax: SET UMODE <+modes-modes|none>');
			return;
		}

		if (lc $parms[0] eq 'none') {
			$del_nicktext->execute(NTF_UMODE, $target); $del_nicktext->finish();
			notice($user, "$obj will not receive any automatic umodes.");
		}
		else {
			my ($modes, $rejected) = modes::allowed_umodes($parms[0]);
			$del_nicktext->execute(NTF_UMODE, $target); $del_nicktext->finish(); # don't allow dups
			$set_umode_ntf->execute($modes, $target); $set_umode_ntf->finish();
			foreach my $usernick (get_nick_user_nicks $target) {
				ircd::setumode($nsnick, $usernick, $modes)
			}

			my @out;
			push @out, "Cannot set these umodes: " . $rejected if $rejected;
			push @out, "$subj automatic umodes have been set to: \002" . ($modes ? $modes : 'none');
			notice($user, @out);
		}
		return;
	}
	elsif($set =~ /^(?:(?:chg)?root|display)$/i) {
		ns_changeroot($user, $target, $parms[0], $override);
		return;
	}

	my $val;
	if($parms[0] =~ /^(?:no|off|false|0)$/i) { $val = 0; }
	elsif($parms[0] =~ /^(?:yes|on|true|1)$/i) { $val = 1; }
	else {
		notice($user, "Please say \002on\002 or \002off\002.");
		return;
	}

	if($set =~ /^hidee?-?mail$/i) {
		nr_set_flag($target, NRF_HIDEMAIL, $val);
		
		if($val) {
			notice($user, "$subj email address is now hidden.");
		} else {
			notice($user, "$subj email address is now visible.");
		}

		return;
	}

	if($set =~ /^nomemo$/i) {
		nr_set_flag($target, NRF_NOMEMO, $val);

		if($val) {
			notice($user, "$subj memos will be blocked.");
		} else {
			notice($user, "$subj memos will be delivered.");
		}

		return;
	}
	
	if($set =~ /^no(?:acc|op)$/i) {
		nr_set_flag($target, NRF_NOACC, $val);

		if($val) {
			notice($user, "$obj may not be added to channel access lists.");
		} else {
			notice($user, "$obj may be added to channel access lists.");
		}

		return;
	}

	if($set =~ /^neverop$/i) {
		nr_set_flag($target, NRF_NEVEROP, $val);

		if($val) {
			notice($user, "$obj will not be granted status upon joining channels.");
		} else {
			notice($user, "$obj will be granted status upon joining channels.");
		}

		return;
	}

	if($set =~ /^auth$/i) {
		nr_set_flag($target, NRF_AUTH, $val);

		if($val) {
			notice($user, "$obj must now authorize additions to channel access lists.");
		} else {
			notice($user, "$obj will not be asked to authorize additions to channel access lists.");
		}

		return;
	}

	if($set =~ /^(hold|no-?expire)$/i) {
		unless (adminserv::can_do($user, 'SERVOP') or
			is_identified($user, $target) and adminserv::is_ircop($user))
		{	
			notice($user, $err_deny);
			return;
		}

		nr_set_flag($target, NRF_HOLD, $val);

		if($val) {
			notice($user, "\002$target\002 is now held from expiration.");
			services::ulog($nsnick, LOG_INFO(), "has held \002$target\002", $user);
		} else {
			notice($user, "\002$target\002 will now expire normally.");
			services::ulog($nsnick, LOG_INFO(), "released \002$target\002 from hold", $user);
		}

		return;
	}

	if($set =~ /^freeze$/i) {
		unless (adminserv::can_do($user, 'FREEZE') or
			is_identified($user, $target) and adminserv::is_ircop($user))
		{
			notice($user, $err_deny);
			return;
		}

		nr_set_flag($target, NRF_FREEZE, $val);

		if($val) {
			notice($user, "\002$target\002 is now frozen.");
			unidentify($target, "Your nick, \002$target\002, has been frozen and may no longer be used.");
			services::ulog($nsnick, LOG_INFO(), "froze \002$target\002", $user);
		} else {
			notice($user, "\002$target\002 is no longer frozen.");
			services::ulog($nsnick, LOG_INFO(), "unfroze \002$target\002", $user);
		}

		return;
	}

	if($set =~ /^vacation$/i) {
		if ($val) {
			$get_regd_time->execute($target);
			my ($regd) = $get_regd_time->fetchrow_array;
			$get_regd_time->finish();

			if(($regd > (time() - 86400 * int(services_conf_vacationexpire / 3))) and !$override) {
				notice($user, "$target is not old enough to use VACATION",
					'Minimum age is '.int(services_conf_vacationexpire / 3).' days');
				return;
			}

			$get_vacation_ntf->execute($target);
			my ($last_vacation) = $get_vacation_ntf->fetchrow_array();
			$get_vacation_ntf->finish();
			if(defined($last_vacation)) {
				$last_vacation = unpack('N', MIME::Base64::decode($last_vacation));
				if ($last_vacation > (time() - 86400 * int(services_conf_vacationexpire / 3)) and !$override) {
					notice($user, "I'm sorry, \002$src\002, I'm afraid I can't do that.",
						"Last vacation ended ".gmtime2($last_vacation),
						'Minimum time between vacations is '.int(services_conf_vacationexpire / 3).' days.');
					return;
				}
			}
		}

		nr_set_flag($target, NRF_VACATION, $val);

		services::ulog($nsnick, LOG_INFO(),
			($val ? 'enabled' : 'disabled')." vacation mode for \002$target\002", $user);
		notice($user, "Vacation mode ".($val ? 'enabled' : 'disabled')." for \002$target\002");
		return;
	}

	if($set =~ /^(email)?reg$/i) {
		unless (adminserv::can_do($user, 'SERVOP'))
		{
			notice($user, $err_deny);
			return;
		}

		nr_set_flag($target, NRF_EMAILREG, $val);

		if($val) {
			authcode($target, 'emailreg');
			notice($user, "\002$target\002 now needs an email validation code.");
			unidentify($target, ["Your nick, \002$target\002, has been flagged for an email validation audit.",
				"Your nick will expire within 24 hours if you do not enter the validation code.",
				"Check your email for further instructions."]);
			services::ulog($nsnick, LOG_INFO(), "requested an email audit for \002$target\002", $user);
		} else {
			$del_nicktext->execute(NTF_AUTHCODE, $target); $del_nicktext->finish();
			notice($user, "\002$target\002 is now fully registered.");
			services::ulog($nsnick, LOG_INFO(), "validated the email for \002$target\002", $user);
		}

		return;
	}

	if($set =~ /^nohighlight$/i) {
		nr_set_flag($target, NRF_NOHIGHLIGHT, $val);

		if($val) {
			notice($user, "$obj will no longer have alternative highlighting of lists.");
		} else {
			notice($user, "$obj will have alternative highlighting of lists.");
		}

		return;
	}

}

sub ns_sendpass($$) {
	my ($user, $nick) = @_;

	unless(adminserv::is_svsop($user, adminserv::S_HELP() )) {
		notice($user, $err_deny);
		return;
	}

	my $email = get_email($nick);

	unless($email) {
		notice($user, "\002$nick\002 is not registered or does not have an email address.");
		return;
	}

	my $pass = get_pass($nick);
	if ($pass and !is_hashed($pass)) {
		send_email($email, "$nsnick Password Reminder",
			"The password for the nick $nick is:\n$pass");
		notice($user, "Password for \002$nick\002 has been sent to \002$email\002.");
	} else {
		authcode($nick, 'sendpass', $email);
		nr_set_flag($nick, NRF_SENDPASS);
		notice($user, "Password authentication code for \002$nick\002 has been sent to \002$email\002.");
	}

	services::ulog($nsnick, LOG_INFO(), "used SENDPASS on $nick ($email)", $user);
}

sub ns_glist($@) {
	my ($user, @targets) = @_;

	foreach my $target (@targets) {
		my $root = get_root_nick($target);
		unless($root) {
			notice $user, "\002$target\002 is not registered.";
			next;
		}

		unless(is_identified($user, $target) or 
			adminserv::is_svsop($user, adminserv::S_HELP())
		) {
			notice $user, "$target: $err_deny";
			next;
		}

		my @data;
		$get_glist->execute($root);
		while(my ($alias, $protect, $last) = $get_glist->fetchrow_array) {
			my $time_ago;
			if(0) {
			# This needs a new NS GLIST cmd, like NS GLISTA or something.
			# The idea is a command that shows the long version of the time_ago.
				$time_ago = time_ago($last, 1);
			} else {
				$time_ago = time_ago($last);
			}
			push @data, ["\002$alias\002", "Protect: $protect_short[$protect]",
				($last ? "Last used $time_ago ago" : '')
			];
		}

		notice $user, columnar {TITLE => "Group list for \002$root\002 (" . $get_glist->rows . " nicks):",
			NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data;
		
		$get_glist->finish();
	}
}

sub ns_alist($@) {
	my ($user, @targets) = @_;

	foreach my $target (@targets) {
		(adminserv::is_svsop($user, adminserv::S_HELP()) and (
			chk_registered($user, $target) or next)
		) or chk_identified($user, $target) or next;

		my @data;

		$get_all_access->execute($target);
		while(my ($c, $l, $a, $t) = $get_all_access->fetchrow_array) {
			next unless $l > 0;
			push @data, [$c, $chanserv::plevels[$l+$chanserv::plzero], ($a ? "($a)" : ''),
				gmtime2($t)];
		}

		notice $user, columnar {TITLE => "Access listing for \002$target\002 (".scalar(@data)." entries)",
			NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data;
	}
}

sub ns_list($$) {
	my ($user, $mask) = @_;

	unless(adminserv::is_svsop($user, adminserv::S_HELP())) {
		notice($user, $err_deny);
		return;
	}

	my ($mnick, $mident, $mhost) = glob2sql(parse_mask($mask));
	
	$mnick = '%' if($mnick eq '');
	$mident = '%' if($mident eq '');
	$mhost = '%' if($mhost eq '');

	my @data;
	$get_matching_nicks->execute($mnick, $mident, $mhost);
	while(my ($rnick, $rroot, $rident, $rhost) = $get_matching_nicks->fetchrow_array) {
		push @data, [$rnick, ($rroot ne $rnick ? $rroot : ''), $rident . '@' . $rhost];
	}

	notice $user, columnar {TITLE => "Registered nicks matching \002$mask\002:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data;
}

sub ns_watch($$$;$) {
	my ($user, $target, $cmd, $mask) = @_;
	my $src = get_user_nick($user);
	
	my $root = get_root_nick($target);
	unless ($root) {
		notice($user, "\002$target\002 is not registered.");
		return;
	}
	unless(is_identified($user, $target)) {
		notice($user, $err_deny);
		return;
	}
	
	if ($cmd =~ /^add$/i) {
		my $max_watches = $IRCd_capabilities{WATCH}; # load here for caching.
		if(count_watches($root) >= $max_watches) {
			notice($user, "WATCH list for $target full, there is a limit of $max_watches. Please trim your list.");
			return;
		}

		if($mask =~ /\!/ or $mask =~ /\@/) {
			my ($mnick, $mident, $mhost) = parse_mask($mask);
			if ($mnick =~ /\*/) {
				notice($user, "Invalid mask: \002$mask\002", 
					'A WATCH mask cannot wildcard the nick.');
				return;
			}
		}

		$check_watch->execute($root, $mask);
		if ($check_watch->fetchrow_array) {
			notice($user, "\002$mask\002 is already in \002$target\002's watch list.");
			return;
		}

		$set_watch->execute($mask, time(), $root);
		ircd::svswatch($nsnick, $src, "+$mask");
		notice($user, "\002$mask\002 added to \002$target\002's watch list.");
		return;
	}
	elsif ($cmd =~ /^del(ete)?$/i) {
		$check_watch->execute($root, $mask);
		unless ($check_watch->fetchrow_array) {
			notice($user, "\002$mask\002 is not in \002$target\002's watch list.");
			return;
		}
		$del_watch->execute($root, $mask);
		ircd::svswatch($nsnick, $src, "-$mask");
		notice($user, "\002$mask\002 removed from \002$target\002's watch list.");
	}
	elsif ($cmd =~ /^list$/i) {
		my @data;
		
		$get_watches->execute($root);
		while(my ($mask, $time) = $get_watches->fetchrow_array) {
			push @data, [$mask, gmtime2($time)];
		}
		
		notice $user, columnar {TITLE => "Watch list for \002$target\002:",
			NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data;
	}
	else {
		notice($user, 'Syntax: WATCH <ADD|DEL|LIST> [nick]');
	}
}

sub ns_silence($$$;$@) {
	my ($user, $target, $cmd, $mask, @args) = @_;
	my ($expiry, $comment);
	my $src = get_user_nick($user);
	my ($subj, $obj);
	if(lc(get_user_nick($user)) eq lc($target)) {
		$subj='your';
		$obj='you';
	} else {
		$subj="\002$target\002\'s";
		$obj="\002$target\002";
	}

sub get_silence_by_num($$) {
# This one cannot be converted to SrSv::MySQL::Stub, due to bind_param call
	my ($nick, $num) = @_;
	$get_silence_by_num->execute($nick, $num-1);
	my ($mask) = $get_silence_by_num->fetchrow_array();
	$get_silence_by_num->finish();
	return $mask;
}
	
	my $root = get_root_nick($target);
	my $isRegistered;
	if(!defined($root)) {
		#notice($user, "\002$target\002 is not registered.");
		$isRegistered = 0;
		#return;
	} else {
		$isRegistered = 1;
	}
	
	if($isRegistered && !is_identified($user, $target)) {
		notice($user, $err_deny);
		return;
	}

	if ($cmd =~ /^add$/i) {
		my $max_silences = $IRCd_capabilities{SILENCE};
		if(count_silences($root) >= $max_silences) {
			notice($user, "SILENCE list for $target full, there is a limit of $max_silences. Please trim your list.");
			return;
		}

		if (substr($args[0],0,1) eq '+') {
			$expiry = shift @args;
		}
		elsif (substr($args[-1],0,1) eq '+') {
			$expiry = pop @args;
		}
		$comment = join(' ', @args);

		if($mask !~ /[!@.]/) {
			my $target_user = { NICK => $mask };
			if(!defined($mask) || !length($mask)) {
				notice($user, qq{Did not specify a user or hostmask.});
				return;
			}
			elsif(!get_user_id($target_user)) {
				notice($user, qq{"\002$mask\002" is not a known user, nor a valid hostmask.});
				return;
			}
			$comment = $mask unless $comment;
			no warnings 'misc';
			my ($ident, $vhost) = get_vhost($target_user);
			my ($nick, $ident, $vhost) = make_hostmask(10, $mask, $ident, $vhost);
			$mask = $nick.'!'.$ident.'@'.$vhost;
		}
		else {
			$mask = normalize_hostmask($mask);
		}

=cut
		if("$nsnick!services\@".main_conf_local =~ hostmask_to_regexp($mask)) {
			notice($user, "You shouldn't add NickServ to your SILENCE list.");
			return;
		}
=cut

		if(defined $expiry) {
			$expiry = parse_time($expiry) + time();
		}
		else {
			$expiry = 0;
		};
		if($isRegistered) {
			$check_silence->execute($root, $mask);
			if ($check_silence->fetchrow_array) {
				notice($user, "\002$mask\002 is already in $subj SILENCE list.");
				return;
			}

			$set_silence->execute($mask, time(), $expiry, $comment, $root);
		}
		ircd::svssilence($nsnick, $src, "+$mask");
		notice($user, "\002$mask\002 added to $subj SILENCE list.");
	}
	elsif ($cmd =~ /^del(ete)?$/i) {
		my @masks;
		if ($mask =~ /^[0-9\.,-]+$/) {
			foreach my $num (makeSeqList($mask)) {
				push @masks, get_silence_by_num($root, $num) or next;
			}
			if(scalar(@masks) == 0) {
				notice($user, "Unable to find any silences matching $mask");
				return;
			}
		} else {
			@masks = ($mask);
		}
		my @reply; my @out_masks;
		foreach my $mask (@masks) {
			$check_silence->execute($root, $mask);
			unless ($check_silence->fetchrow_array) {
				$mask = normalize_hostmask($mask);

				$check_silence->execute($root, $mask);
				unless ($check_silence->fetchrow_array) {
					push @reply, "\002$mask\002 is not in $subj SILENCE list.";
					next;
				}
			}
			$del_silence->execute($root, $mask);
			push @out_masks, "-$mask";
			push @reply, "\002$mask\002 removed from $subj SILENCE list.";
		}
		ircd::svssilence($nsnick, $src, @out_masks);
		notice($user, @reply);
	}
	elsif ($cmd =~ /^list$/i) {
		$get_silences->execute($root);
		
		my @reply; my $i = 1;
		while(my ($mask, $time, $expiry, $comment) = $get_silences->fetchrow_array) {
			push @reply, "$i \002[\002 $mask \002]\002 Date added: ".gmtime2($time),
				'    '.($comment ? "\002[\002 $comment \002]\002 " : '').
				($expiry ? 'Expires in '.time_rel($expiry-time()) : 
					"\002[\002 Never expires \002]\002");
			$i++;
		}
		
		notice($user, "SILENCE list for $obj:", (scalar @reply ? @reply : "  list empty"));
	}
	else {
		notice($user, 'Syntax: SILENCE [nick] <ADD|DEL|LIST> [mask] [+expiry] [comment]');
	}

}

sub ns_acc($@) {
	my ($user, @targets) = @_;
	my @reply;

	foreach my $target (@targets) {
		unless(is_registered($target)) {
			push @reply, "ACC 0 \002$target\002 is not registered.";
			next;
		}

		unless(is_online($target)) {
			push @reply, "ACC 1 \002$target\002 is registered and offline.";
			next;
		}

		unless(is_identified({NICK => $target}, $target)) {
			push @reply, "ACC 2 \002$target\002 is online but not identified.";
			next;
		}

		push @reply, "ACC 3 \002$target\002 is registered and identified.";
	}
	notice($user, @reply);
}

sub ns_seen($@) {
	my ($user, @nicks) = @_;

	foreach my $nick (@nicks) {
		if(lc $nick eq lc $user->{AGENT}) {
			notice($user, "Oh, a wise guy, eh?");
			next;
		}
		my ($status, $msg) = do_seen($nick);
		if($status == 2) {
			notice($user, "\002$nick\002 is online now, ".$msg.'.');
		} elsif($status == 1) {
			notice($user, "\002$nick\002 was last seen ".$msg.'.');
		} else {
			notice($user, "The nick \002$nick\002 is not registered.");
		}
	}
}

sub ns_recover($$;$) {
	my ($user, $nick, $pass) = @_;
	my $src = get_user_nick($user);

	if(nr_chk_flag($nick, NRF_FREEZE)) {
		notice($user, "This nick has been frozen and may not be used.", $err_deny);
		services::ulog($nsnick, LOG_INFO(), "\00305attempted to recover frozen nick \003\002$nick\002", $user);
		return;
	}

	unless(is_identified($user, $nick)) {
		if($pass) {
			my $s = ns_identify($user, $nick, $pass);
			return if($s == 0); #failed to identify
		} else {
			notice($user, $err_deny);
			return;
		}
	}

	if(!is_online($nick)) {
		notice($user, "\002$nick\002 is not online");
		return;
	} elsif(lc $src eq lc $nick) {
		notice($user, "I'm sorry, $src, I'm afraid I can't do that.");
		return;

	} else {
		collide($nick);
		notice($user, "User claiming your nick has been collided", 
			"/msg NickServ RELEASE $nick to get it back before the one-minute timeout.");
		services::ulog($nsnick, LOG_INFO(), "used NickServ RECOVER on $nick", $user);
		return;
	}
}

sub ns_auth($@) {
	my ($user, @args) = @_;
	my ($target, $cmd);

#These helpers shouldn't be needed anywhere else.
# If they ever are, move them to the helpers section
	sub get_auth_num($$) {
		# this cannot be converted to SrSv::MySQL::Stub, due to bind_param
		my ($nick, $num) = @_;
		$get_auth_num->execute($nick, $num - 1);
		my ($cn, $data) = $get_auth_num->fetchrow_array();
		$get_auth_num->finish();
		return ($data ? ($cn, split(/:/, $data)) : undef);
	}
	sub get_auth_chan($$) {
		my ($nick, $cn) = @_;
		$get_auth_chan->execute($nick, $cn);
		my ($data) = $get_auth_chan->fetchrow_array();
		$get_auth_chan->finish();
		return (split(/:/, $data));
	}

	if ($args[0] =~ /^(list|accept|approve|decline|reject)$/i) {
		$target = get_user_nick($user);
		$cmd = lc shift @args;
	}
	else {
		$target = shift @args;
		$cmd = lc shift @args;
	}

	unless (is_registered($target)) {
		notice($user, "The nickname \002$target\002 is not registered");
		return;
	}
	unless (is_identified($user, $target)) {
		notice($user, $err_deny);
		return;
	}

	if ($cmd eq 'list') {
		my @data;
		$list_auth->execute($target);
		while (my ($cn, $data) = $list_auth->fetchrow_array()) {
			my ($adder, $old, $level, $time) = split(':', $data);
			push @data, [$cn, $chanserv::levels[$level], $adder, gmtime2($time)];
		}
		if ($list_auth->rows()) {
			notice $user, columnar {TITLE => "Pending authorizations for \002$target\002:",
				NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data;
		}
		else {
			notice($user, "There are no pending authorizations for \002$target\002");
		}
	}
	elsif ($cmd eq 'accept' or $cmd eq 'approve') {
		my $parm = shift @args;
		my ($cn, $adder, $old, $level, $time);
		if(misc::isint($parm) and
			($cn, $adder, $old, $level, $time) = get_auth_num($target, $parm))
		{
		}
		elsif ($parm =~ /^\#/ and 
			($adder, $old, $level, $time) = get_auth_chan($target, $parm))
		{
			$cn = $parm;
		}
		unless ($cn) {
		# This should normally be an 'else' as the elsif above should prove false
		# For some reason, it doesn't work. the unless ($cn) fixes it.
		# It only doesn't work for numbered entries
			notice($user, "There is no entry for \002$parm\002 in \002$target\002's AUTH list");
			return;
		}
		my $chan = { CHAN => $cn };
		my $root = get_root_nick($target);

		# These next 3 lines should use chanserv::set_acc() but it doesn't seem to work.
		# It won't let me use a $nick instead of $user
		$chanserv::set_acc1->execute($cn, $level, $root);
		$chanserv::set_acc2->execute($level, $adder, $cn, $root);
		chanserv::set_modes_allnick($root, $chan, $level) unless chanserv::is_neverop($root);
		
		my $log_str = ($old?'move':'addition')." \002$root\002"
			. ($old ? ' from the '.$chanserv::levels[$old] : '') .
			' to the '.$chanserv::levels[$level]." list of \002$cn\002";
		services::ulog($chanserv::csnick, LOG_INFO(), "accepted the $log_str from $adder", $user, $chan);
		notice($user, "You have accepted the $log_str");
		$del_auth->execute($target, $cn);
		$del_auth->finish();
		memoserv::send_memo($chanserv::csnick, $adder, "$target accepted the $log_str");
	}
	elsif ($cmd eq 'decline' or $cmd eq 'reject') {
		my $parm = shift @args;
		my ($cn, $adder, $old, $level, $time);
		if(misc::isint($parm) and
			($cn, $adder, $old, $level, $time) = get_auth_num($target, $parm))
		{
		}
		elsif ($parm =~ /^\#/ and 
			($adder, $old, $level, $time) = get_auth_chan($target, $parm))
		{
			$cn = $parm;
		}
		unless ($cn) {
		# This should normally be an 'else' as the elsif above should prove false
		# For some reason, it doesn't work. the unless ($cn) fixes it.
		# It only doesn't work for numbered entries
			notice($user, "There is no entry for \002$parm\002 in \002$target\002's AUTH list");
			return;
		}
		my $chan = { CHAN => $cn };

		my $root = get_root_nick($target);
		my $log_str = ($old?'move':'addition')." \002$root\002"
			. ($old ? ' from the '.$chanserv::plevels[$old+$chanserv::plzero] : '') .
			' to the '.$chanserv::plevels[$level+$chanserv::plzero]." list of \002$cn\002";
		services::ulog($chanserv::csnick, LOG_INFO(), "declined the $log_str from $adder", $user, $chan);
		notice($user, "You have declined $log_str");
		$del_auth->execute($target, $cn);
		$del_auth->finish();
		memoserv::send_memo($chanserv::csnick, $adder, "$target declined the $log_str");
	}
	#elsif ($cmd eq 'read') {
	#}
	else {
		notice($user, "Unknown AUTH cmd");
	}
}

sub ns_authcode($$$;$) {
	my ($user, $target, $code, $pass) = @_;

	if ($pass and $pass =~ /pass/i) {
		notice($user, 'Try a more secure password.');
		return;
	}

	unless(is_registered($target)) {
		notice($user, "\002$target\002 isn't registered.");
		return;
	}

	if(authcode($target, undef, $code)) {
		notice($user, "\002$target\002 authenticated.");
		services::ulog($nsnick, LOG_INFO(), "logged in to \002$target\002 using an authcode", $user);

		do_identify($user, $target, $target);
		if($pass) {
			ns_set($user, $target, 'PASSWD', $pass)
		} elsif(nr_chk_flag($target, NRF_SENDPASS())) {
			notice($user, "YOU MUST CHANGE YOUR PASSWORD NOW", "/NS SET $target PASSWD <newpassword>");
		}
	}
	else {
		notice($user, "\002$target\002 authentication failed. Please verify that you typed or pasted the code correctly.");
	}
}

sub ns_profile($@) {
	my ($user, $first, @args) = @_;
	
	my %profile_dispatch = (
		'read'   => \&ns_profile_read,
		'info'   => \&ns_profile_read,

		'del'    => \&ns_profile_del,
		'delete' => \&ns_profile_del,

		'set'    => \&ns_profile_update,
		'update' => \&ns_profile_update,
		'add'    => \&ns_profile_update,

		'wipe'   => \&ns_profile_wipe,
	);

	no warnings 'misc';
	if(my $sub = $profile_dispatch{$args[0]}) {
		# Second command with nick
		shift @args;
		$sub->($user, $first, @args);
	}
	elsif(my $sub = $profile_dispatch{$first}) {
		# Second command without nick
		$sub->($user, get_user_nick($user), @args);
	}
	elsif(@args == 0) {
		# No second command
		ns_profile_read($user, ($first || get_user_nick($user)));
	}
	else {
		notice $user,
			"Syntax: PROFILE [nick] [SET|DEL|READ|WIPE ...]",
			"For help, type: \002/ns help profile\002";
	}
}

sub ns_profile_read($$@) {
	my ($user, $target, @args) = @_;
	
	foreach my $nick ((scalar(@args) ? @args : $target)) {
		next unless chk_registered($user, $nick);
		my @profile_entries = get_profile_ntf($nick);
		if(scalar(@profile_entries)) {
			notice $user, columnar({TITLE => "Profile information for \002$nick\002:",
				NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)},
				map( ["$_->[0]:", $_->[1]], @profile_entries )
				);
		}
		else {
			notice $user, "\002$nick\002 has not created a profile.";
		}
	}
}

sub ns_profile_update($$@) {
	my ($user, $target, @args) = @_;

	return unless chk_registered($user, $target);
	
	unless(is_identified($user, $target) or 
		adminserv::is_svsop($user, adminserv::S_HELP())
	) {
		notice($user, "$target: $err_deny");
		return;
	}

	my ($key, $data) = (shift @args, join(' ', @args));

	unless ($key and $data) {
		notice $user, "Syntax: PROFILE [nick] SET <item> <text>",
			"For help, type: \002/ns help profile\002";
		return;
	}

	if(count_profile_ntf($target) >= MAX_PROFILE) {
		notice($user, "You may not have more than ".MAX_PROFILE." profile items.");
		return;
	}
	elsif (length($key) > 32) {
		notice($user, "Item name may not be longer than 32 characters.");
		return;
	}
	elsif (length($data) > MAX_PROFILE_LEN) {
		my $over = length($data) - MAX_PROFILE_LEN;
		notice($user, "Your entry is $over characters too long. (".MAX_PROFILE_LEN." max.)");
		return;
	}
	add_profile_ntf($key, $data, $target);
	notice($user, "\002$target\002's \002$key\002 is now \002$data\002");
}

sub ns_profile_del($$@) {
	my ($user, $target, @args) = @_;

	return unless chk_registered($user, $target);
	
	unless(is_identified($user, $target) or 
		adminserv::is_svsop($user, adminserv::S_HELP())
	) {
		notice($user, "$target: $err_deny");
		return;
	}

	my $key = shift @args;

	unless ($key) {
		notice $user, "Syntax: PROFILE [nick] DEL <item>",
			"For help, type: \002/ns help profile\002";
		return;
	}

	if(del_profile_ntf($target, $key) == 0) {
		notice($user, "There is no profile item \002$key\002 for \002$target\002");
	} else {
		notice($user, "Profile item \002$key\002 for \002$target\002 deleted.");
	}
}

sub ns_profile_wipe($$@) {
	my ($user, $target, undef) = @_;

	unless (is_registered($target)) {
		notice($user, "$target is not registered.");
		next;
	}
	unless(is_identified($user, $target) or 
		adminserv::is_svsop($user, adminserv::S_HELP())
	) {
		notice($user, "$target: $err_deny");
		return;
	}

	wipe_profile_ntf($target);
	notice($user, "Profile for \002$target\002 wiped.");
}

sub ns_listemail($$) {
	my ($user, $email) = @_;
	unless(adminserv::is_svsop($user, adminserv::S_HELP())) {
		notice($user, $err_deny);
		return;
	}
	my $likeemail = glob2sql($email);
	my (@found, $count);

	$get_nicks_by_email->execute($likeemail);
	while (my ($nick, $ident, $host) = $get_nicks_by_email->fetchrow_array) {
		push @found, "   $nick ($ident\@$host)";
	}
	$email =~ s/\%/\*/g;
	if ($#found >= 0) {
		notice($user, "Nicks matching an email address consisting of \002$email\002");
		for(@found) {
			notice($user, $_);
			$count++;
		}
		notice($user, "Found \002$count\002 matching nicks.");
	} else {
		notice($user, "There were no nicknames registered with an email address consisting of \002$email\002");
	}
}

### MISCELLANEA ###

sub do_seen($$) {
	my ($nick) = @_;
	my ($status, $msg);
	
	$get_seen->execute($nick);
	if (my ($alias, $root, $lastseen) = $get_seen->fetchrow_array) {
		if(my @usernicks = get_nick_user_nicks($nick)) {
			$status = 2;
			$msg = "using ".(@usernicks==1 ? 'the nick ' : 'the following nicks: ').join(', ', map "\002$_\002", @usernicks);
		}
		else {
			$status = 1;
			$msg = time_ago($lastseen) . " ago (".gmtime2($lastseen).")";
		}
	}
	else {
		$status = 0; $msg = undef();
	}

	return ($status, $msg);
}

# For a whole group:
sub unidentify($$;$) {
	my ($nick, $msg, $src) = @_;

	$nick = get_root_nick($nick);

	foreach my $t (get_nick_user_nicks $nick) {
		ircd::notice($nsnick, $t, (ref $msg ? @$msg : $msg)) unless(lc $t eq lc $src);
		if(is_alias_of($nick, $t)) {
			ircd::setumode($nsnick, $t, '-r');
		}
	}

	$unidentify->execute($nick);
}

# For a single alias:
sub unidentify_single($$) {
	my ($nick, $msg) = @_;

	if(is_online($nick)) {
		ircd::setumode($nsnick, $nick, '-r');
	}
}

sub kill_clones($$) {
	my ($user, $ip) = @_;
	my $uid = get_user_id($user);
	my $src = get_user_nick($user);

	return 0 if $ip == 0;

	$chk_clone_except->execute($uid);
	my ($lim) = $chk_clone_except->fetchrow_array;
	return 0 if $lim == MAX_LIM();
	$lim = services_conf_clone_limit unless $lim;
	
	$count_clones->execute($ip);
	my ($c) = $count_clones->fetchrow_array;

	if($c > $lim) {
		ircd::irckill($nsnick, $src, "Session Limit Exceeded");
		return 1;
	}
}

sub do_ajoin($$) {
	my ($user, $nick) = @_;
	my $src = get_user_nick($user);
	if(my @chans = get_autojoin_ntf($nick)) {
		chanserv::cs_join($user, @chans);
	}
}

sub do_identify ($$$;$$) {
	my ($user, $nick, $root, $flags, $svsnick) = @_;
	my $uid = get_user_id($user);
	my $src = get_user_nick($user);

	$identify_ign->execute($uid, $root);
	$id_update->execute($root, $uid);

	notice($user, 'You are now identified.');

	delete($user->{NICKFLAGS});
	if($flags & NRF_VACATION) {
		notice($user, "Welcome back from your vacation, \002$nick\002.");
		my $ts = MIME::Base64::encode(pack('N', time()));
		chomp $ts;
		$del_nicktext->execute(NTF_VACATION, $root); $del_nicktext->finish(); #don't allow dups
		$set_vacation_ntf->execute($ts, $root);
		$set_vacation_ntf->finish();
	}

	$get_umode_ntf->execute($nick);
	my ($umodes) = $get_umode_ntf->fetchrow_array();
	$get_umode_ntf->finish();
	if(adminserv::get_svs_level($root)) {
		$umodes = modes::merge_umodes('+h', $umodes);
		ircd::nolag($nsnick, '+', $src);
	}
	$umodes = modes::merge_umodes('+r', $umodes) if(is_identified($user, $src));

	hostserv::hs_on($user, $root, 1);

	nickserv::do_svssilence($user, $root);
	nickserv::do_svswatch($user, $root);

	chanserv::akick_alluser($user);
	chanserv::set_modes_allchan($user, $flags & NRF_NEVEROP);
	chanserv::fix_private_join_before_id($user);
	
	services::ulog($nsnick, LOG_INFO(), "identified to nick $nick (root: $root)", $user);

	memoserv::notify($user, $root);
	notify_auths($user, $root) if $flags & NRF_AUTH;

	my $enforced;
	if(enforcer_quit($nick)) {
		notice($user, 'Your nick has been released from custody.');
		$enforced = 1;
	}

	if (lc($src) eq lc($nick)) {
		ircd::setumode($nsnick, $src, $umodes);
		$update_nickalias_last->execute($nick); $update_nickalias_last->finish();
	}
	elsif($svsnick) {
		ircd::svsnick($nsnick, $src, $nick);
		ircd::setumode($nsnick, $nick, modes::merge_umodes('+r', $umodes) );
		# the update _should_ be taken care of in nick_change()
		#$update_nickalias_last->execute($nick); $update_nickalias_last->finish();
	}
	elsif(defined $umodes) {
		ircd::setumode($nsnick, $src, $umodes);
	}
	do_ajoin($user, $nick);
	return ($enforced ? 2 : 1);
}

sub authcode($;$$) {
	my ($nick, $type, $email) = @_;
	if($type) {
		unless (defined($email)) {
			$email = get_email($nick);
		}

		my $authcode = misc::gen_uuid(4, 5);
		$set_authcode_ntf->execute($authcode, $nick); $set_authcode_ntf->finish();
		send_email($email, "Nick Authentication Code for $nick",
			"Hello $nick,\n\n".

			"You are receiving this message from the automated nickname\n".
			"management system of the ".$IRCd_capabilities{NETWORK}." network.\n\n".
		(lc($type) eq 'emailreg' ? 
			"If you did not try to register your nickname with us, you can\n".
			"ignore this message. If you continue getting similar e-mails\n".
			"from us, chances are that someone is intentionally abusing your\n".
			"e-mail address. Please contact an administrator for help.\n".

			"In order to complete your registration, you must follow the\n".
			"instructions in this e-mail before ".gmtime2(time+86400)."\n".

			"To complete the registration, the next time you connect, issue the\n".
			"following command to NickServ:\n\n".

			"After you issue the command, your registration will be complete and\n".
			"you will be able to use your nickname.\n\n"

		: '').
		(lc($type) eq 'sendpass' ?
			"You requested a password authentication code for the nickname '$nick'\n".
			"on the ".$IRCd_capabilities{'NETWORK'}." IRC Network.\n".
			"As per our password policies, an authcode has been created for\n".
			"you and e-mailed to the address you set in NickServ.\n".
			"To complete the process, you need to return to ".$IRCd_capabilities{'NETWORK'}.",\n".
			"and execute the following command: \n\n"
		: '').

			"/NS EMAILCODE $nick $authcode\n\n".
			
		(lc($type) eq 'sendpass' ?
			"YOU MUST CHANGE YOUR PASSWORD AT THIS POINT.\n".
			"You can do so via the following command: \n\n".
			"/NS SET $nick PASSWD newpassword\n\n".
			"alternately, try this command: \n\n".

			"/NS EMAILCODE $nick $authcode <password>\n\n"
		: '').

			"---\n".
			"If you feel you have gotten this e-mail in error, please contact\n".
			"an administrator.\n\n".

			"----\n".
			"If this e-mail came to you unsolicited  and appears to be spam -\n".
			"please e-mail ".main_conf_replyto." with a copy of this e-mail\n".
			"including all headers.\n\n".

			"Thank you.\n");
	}
	else {
		$get_authcode_ntf->execute($nick, $email); 
		my ($passed) = $get_authcode_ntf->fetchrow_array();
		$get_authcode_ntf->finish();
		if ($passed) {
			nr_set_flag($nick, NRF_EMAILREG(), 0);
			unless(nr_chk_flag($nick, NRF_SENDPASS)) {
				$del_nicktext->execute(NTF_AUTHCODE, $nick); $del_nicktext->finish();
			}
			return 1;
		}
		else {
			return 0;
		}
	}
}

# This is mostly for logging, be careful using it for anything else
sub get_hostmask($) {
	my ($user) = @_;
	my ($ident, $host);
	my $src = get_user_nick($user);
	
	($ident, $host) = get_host($user);

	return "$src!$ident\@$host";
}

sub guestnick($) {
	my ($nick) = @_;
	
	$set_guest->execute(1, $nick);
	my $randnick = 'Guest'.int(rand(10)).int(rand(10)).int(rand(10)).int(rand(10)).int(rand(10));
	#Prevent collisions.
	while (is_online($randnick)) {
	    $randnick = 'Guest'.int(rand(10)).int(rand(10)).int(rand(10)).int(rand(10)).int(rand(10));
	}
	ircd::svsnick($nsnick, $nick, $randnick);

	return $randnick;
}

sub expire {
	return if services_conf_noexpire;

=cut
	my ($ne, $e, $ve, $eve) = (services_conf_nearexpire, services_conf_nickexpire, services_conf_vacationexpire,
		services_conf_validate_expire);
=cut
	
	$get_expired->execute(time() - (86400 * services_conf_nickexpire),
		time() - (86400 * services_conf_vacationexpire),
		time() - (86400 * services_conf_validate_expire));
	while(my ($nick, $email, $ident, $vhost) = $get_expired->fetchrow_array) {
		dropgroup($nick);
		wlog($nsnick, LOG_INFO(), "$nick has expired.  Email: $email  Vhost: $ident\@$vhost");
	}

	my $time = time();

	return unless services_conf_nearexpire; # if nearexpire is zero, don't.
	$get_near_expired->execute(
		$time - (86400 * (services_conf_nickexpire - services_conf_nearexpire)),
		$time - (86400 * (services_conf_vacationexpire - services_conf_nearexpire))
	);
	while(my ($nick, $email, $flags, $last) = $get_near_expired->fetchrow_array) {
		my $expire_days = services_conf_nearexpire;
		if ( ( $flags & NRF_VACATION ) and ( $last < time() - (86400 * services_conf_vacationexpire) )
			or (($last < time() - (86400 * services_conf_nickexpire)) ) )
		{
			$expire_days = 0;
		} elsif ( ( $flags & NRF_VACATION ) and ( $last > time() - (86400 * services_conf_vacationexpire) )
			or (($last > time() - (86400 * services_conf_nickexpire)) ) )
		{
			# this terrible invention is to determine how many days until their nick will expire.
			# this should almost always be ~7, unless something weird happens like
			# F_HOLD or svsop status is removed.
			# int truncates, so we add 0.5.
			$expire_days = -int(($time - ($last + (86400 * 
				( ( $flags & NRF_VACATION ) ? services_conf_vacationexpire : services_conf_nickexpire ) )))
				 / 86400 + .5);
		}
		if($expire_days >= 1) {

			$get_aliases->execute($nick);
			my $aliases = $get_aliases->fetchrow_arrayref();

			my $message = "We would like to remind you that your registered nick, $nick, will expire\n".
				"in approximately $expire_days days unless you sign on and identify.";
			if(scalar(@$aliases) > 1) {
				$message .= "\n\nThe following nicks are linked in this group:\n  " . join("\n  ", @$aliases);
			}

			send_email($email, "$nsnick Expiration Notice", $message);
		}

		wlog($nsnick, LOG_INFO(), "$nick will expire ".($expire_days <= 0 ? "today" : "in $expire_days days.")." ($email)");
		$set_near_expired->execute($nick);
	}
}

sub expire_silence_timed {
	my ($time) = shift;
	$time = 60 unless $time;
	add_timer('', $time, __PACKAGE__, 'nickserv::expire_silence_timed');

	find_expired_silences();
}

# This code is a mess b/c we can only pull one entry at a time
# and we want to batch the list to the user and to the ircd.
# our SQL statement explicitly orders the silence entries by nickreg.nick
sub find_expired_silences() {
	$get_expired_silences->execute();
	my ($lastnick, @entries);
	while(my ($nick, $mask, $comment) = $get_expired_silences->fetchrow_array()) {
		if ($nick eq $lastnick) {
		} else {
			do_expired_silences($lastnick, \@entries);
			@entries = ();
			$lastnick = $nick;
		}
		push @entries, [$mask, $comment];
	}
	if (@entries) {
		do_expired_silences($lastnick, \@entries);
	}
	$get_expired_silences->finish();
	$del_expired_silences->execute(); $del_expired_silences->finish();
	return;
}

sub do_expired_silences($$) {
	my $nick = $_[0];
	my (@entries) = @{$_[1]};

	foreach my $user (get_nick_users $nick) {
		$user->{AGENT} = $nsnick;
		ircd::svssilence($nsnick, get_user_nick($user), map ( { '-'.$_->[0] } @entries) );
		#notice($user, "The following SILENCE entries have expired: ".
		#	join(', ', map ( { $_->[0] } @entries) ));
		notice($user, map( { "The following SILENCE entry has expired: \002".$_->[0]."\002 ".$_->[1] } @entries ) );
	}
}
sub do_svssilence($$) {
	my ($user, $rootnick) = @_;
	my $target = get_user_nick($user);
	
	$get_silences->execute($rootnick);
	my $count = $get_silences->rows;
	unless ($get_silences->rows) {
		$get_silences->finish;
		return;
	}
	my @silences;
	for(my $i = 1; $i <= $count; $i++) {
		my ($mask, $time, $expiry) = $get_silences->fetchrow_array;
		push @silences, "+$mask";
	}
	$get_silences->finish;
	ircd::svssilence($nsnick, $target, @silences);
	return;
}

sub do_svswatch($$) {
	my ($user, $rootnick) = @_;
	my $target = get_user_nick($user);
	
	$get_watches->execute($rootnick);
	my $count = $get_watches->rows;
	unless ($get_watches->rows) {
		$get_watches->finish;
		return;
	}
	my @watches;
	for(my $i = 1; $i <= $count; $i++) {
		my ($mask, $time, $expiry) = $get_watches->fetchrow_array;
		push @watches, "+$mask";
	}
	$get_watches->finish;
	ircd::svswatch($nsnick, $target, @watches);
	return;
}

sub do_umode($$) {
	my ($user, $rootnick) = @_;
	my $target = get_user_nick($user);

	$get_umode_ntf->execute($rootnick);
	my ($umodes) = $get_umode_ntf->fetchrow_array; $get_umode_ntf->finish();

	ircd::setumode($nsnick, $target, $umodes) if $umodes;
	return
}

sub notify_auths($$) {
	my ($user, $nick) = @_;

	$get_num_nicktext_type->execute($nick, NTF_AUTH);
	my ($count) = $get_num_nicktext_type->fetchrow_array(); $get_num_nicktext_type->finish();
	notice($user, "$nick has $count channel authorizations awaiting action.", 
		"To list them, type /ns auth $nick list") if $count;
}

### PROTECTION AND ENFORCEMENT ###

sub protect($) {
	my ($nick) = @_;

	return if nr_chk_flag($nick, NRF_EMAILREG());
	my $lev = protect_level($nick);
	my $user = { NICK => $nick, AGENT => $nsnick };
	
	notice($user,
		"This nickname is registered and protected. If it is your",
		"nick, type \002/msg NickServ IDENTIFY <password>\002. Otherwise,",
		"please choose a different nick."
	) unless($lev==3);

	if($lev == 1) {
		warn_countdown("$nick 60");
	}
	elsif($lev==2) {
		collide($nick);
	}
	elsif($lev==3) {
		ircd::svshold($nick, 60, "If this is your nick, type /NS SIDENTIFY $nick \002password\002");
		kill_user($user, "Unauthorized nick use with KILL protection enabled.");
		$enforcers{lc $nick} = 1;
		add_timer($nick, 60, __PACKAGE__, "nickserv::enforcer_delete");
	}
	
	return;
}

sub warn_countdown($) {
	my ($cookie)  = @_;
	my ($nick, $rem) = split(/ /, $cookie);
	my $user = { NICK => $nick, AGENT => $nsnick };
	
	if (is_identified($user, $nick)) {
		$update_nickalias_last->execute($nick); $update_nickalias_last->finish();
		return;
	}
	elsif(!(is_online($nick)) or !(is_registered($nick))) { return; } 

	if($rem == 0) {
		notice($user, 'Your nick is now being changed.');
		collide($nick);
	} else {
		notice($user,
			"If you do not identify or change your nick in $rem seconds, your nick will be changed.");
		$rem -= 20;
		add_timer("$nick $rem", 20, __PACKAGE__, "nickserv::warn_countdown");
	}
}

sub collide($) {
	my ($nick) = @_;
	
	ircd::svshold($nick, 60, "If this is your nick, type /NS SIDENTIFY $nick \002password\002");
	$enforcers{lc $nick} = 1;
	add_timer($nick, 60, __PACKAGE__, "nickserv::enforcer_delete");

	return guestnick($nick);
}

sub enforcer_delete($) {
	my ($nick) = @_;
	delete($enforcers{lc $nick});
};

sub enforcer_quit($) {
	my ($nick) = @_;
	if($enforcers{lc $nick}) {
		enforcer_delete($nick);
		ircd::svsunhold($nick);
		return 1;
	}
	return 0;
}

### DATABASE UTILITY FUNCTIONS ###

sub get_lock($) {
	my ($nick) = @_;
	
	$nick = lc $nick;

	if($cur_lock) {
		if($cur_lock ne $nick) {
			really_release_lock($nick);
			die("Tried to get two locks at the same time");
		}
		$cnt_lock++;
	} else {
		$cur_lock = $nick;
		$get_lock->execute(sql_conf_mysql_db.".user.$nick");
		$get_lock->finish;
	}
}

sub release_lock($) {
	my ($nick) = @_;
	
	$nick = lc $nick;

	if($cur_lock and $cur_lock ne $nick) {
		really_release_lock($cur_lock);
		
		die("Tried to release the wrong lock");
	}
	
	if($cnt_lock) {
		$cnt_lock--;
	} else {
		really_release_lock($nick);
	}
}

sub really_release_lock($) {
	my ($nick) = @_;

	$cnt_lock = 0;
	$release_lock->execute(sql_conf_mysql_db.".user.$nick");
	$release_lock->finish;
	undef $cur_lock;
}

sub get_user_modes($) {
	my ($user) = @_;

	my $uid = get_user_id($user);
	$get_umodes->execute($uid);
	my ($umodes) = $get_umodes->fetchrow_array;
	$get_umodes->finish();
	return $umodes;
};

sub set_vhost($$) {
	my ($user, $vhost) = @_;
	my $id = get_user_id($user);
	
	return $set_vhost->execute($vhost, $id);
}

sub set_ident($$) {
	my ($user, $ident) = @_;
	my $id = get_user_id($user);
	
	return $set_ident->execute($ident, $id);
}

sub set_ipv6($$$) {
	my ($user, $ip, $ipv6) = @_;
	my $id = get_user_id($user);

	return $set_ip->execute($ip, $ipv6, $id);
}
sub set_ip($$) {
	my ($user, $ip) = @_;
	my $id = get_user_id($user);

	return $set_ip->execute($ip, undef, $id);
}

sub get_root_nick($) {
	my ($nick) = @_;

	$get_root_nick->execute($nick);
	my ($root) = $get_root_nick->fetchrow_array;

	return $root;
}

sub get_id_nick($) {
	my ($id) = @_;

	$get_id_nick->execute($id);
	my ($root) = $get_id_nick->fetchrow_array;

	return $root;
}

sub drop($) {
	my ($nick) = @_;
	
	my $ret = $drop->execute($nick);
	$drop->finish();
	return $ret;
}

sub changeroot($$) {
	my ($old, $new) = @_;

	return if(lc $old eq lc $new);

	$change_root->execute($new, $old);
}

sub dropgroup($) {
	my ($root) = @_;
	
	$del_all_access->execute($root);
	$memoserv::delete_all_memos->execute($root);
	$memoserv::wipe_ignore->execute($root);
	$memoserv::purge_ignore->execute($root);
	chanserv::drop_nick_chans($root);
	hostserv::del_vhost($root);
	$drop_watch->execute($root);
	$drop_silence->execute($root);
	$drop_nicktext->execute($root);
	$delete_aliases->execute($root);
	$chanserv::drop_nick_akick->execute($root);
	drop($root);
}

sub is_alias($) {
	my ($nick) = @_;
	
	return (get_root_nick($nick) eq $nick);
}

sub delete_alias($) {
	my ($nick) = @_;
	return $delete_alias->execute($nick);
}

sub delete_aliases($) {
	my ($root) = @_;
	return $delete_aliases->execute($root);
}

sub get_all_access($) {
	my ($nick) = @_;
	
	$get_all_access->execute($nick);
	return $get_all_access->fetchrow_array;
}

sub del_all_access($) {
	my ($root) = @_;
	
	return $del_all_access->execute($root);
}

sub chk_pass($$$) {
	my ($nick, $pass, $user) = @_;

	if(lc($pass) eq 'force' and adminserv::can_do($user, 'SERVOP')) {
		if(adminserv::get_best_svs_level($user) > adminserv::get_svs_level($nick)) {
			return 1;
		}
	}

	return validate_pass(get_pass($nick), $pass);
}

sub inc_nick_inval($) {
	my ($user) = @_;
	my $id = get_user_id($user);

	$inc_nick_inval->execute($id);
	$get_nick_inval->execute($id);
	my ($nick, $inval) = $get_nick_inval->fetchrow_array;
	if($inval > 3) {
		ircd::irckill($nsnick, $nick, 'Too many invalid passwords.');
		# unnecessary as irckill calls the quit handler.
		#nick_delete($nick);
		return 0;
	} else {
		return 1;
	}
}

sub is_registered($) {
	my ($nick) = @_;

	$is_registered->execute($nick);
	if($is_registered->fetchrow_array) {
		return 1;
	} else {
		return 0;
	}
}

sub chk_registered($;$) {
	my ($user, $nick) = @_;
	my $src = get_user_nick($user);
	my $what;
	
	if($nick) {
		if(lc $src eq lc $nick) {
			$what = "Your nick";
		} else {
			$what = "The nick \002$nick\002";
		}
	} else {
		$nick = get_user_nick($user) unless $nick;
		$what = "Your nick";
	}

	unless(is_registered($nick)) {
		notice($user, "$what is not registered.");
		return 0;
	}

	return 1;
}

sub is_alias_of($$) {
	$is_alias_of->execute($_[0], $_[1]);
	return ($is_alias_of->fetchrow_array ? 1 : 0);
}

sub check_identify($) {
	my ($user) = @_;
	my $nick = get_user_nick($user);
	if(is_registered($nick)) {
		if(is_identified($user, $nick)) {
			ircd::setumode($nsnick, $nick, '+r');
			$update_nickalias_last->execute($nick); $update_nickalias_last->finish();
			return 1;
		} else {
			protect($nick);
		}
	}
	return 0;
}

sub cleanup_users() {
	add_timer('', services_conf_old_user_age, __PACKAGE__, 'nickserv::cleanup_users');
	if(DEBUG) {
		ircd::privmsg('ServServ', main_conf_diag, "Starting cleanup_users()");
	}

	my $time = (time() - (services_conf_old_user_age * 2));
	if(DEBUG) {
		$get_dead_users->execute($time);
		my $arrayRef = $get_dead_users->fetchall_arrayref();
		if($arrayRef && scalar(@$arrayRef)) {
			ircd::privmsg('ServServ', main_conf_diag, columnar( { BORDER => 1, NOHIGHLIGHT => 1 }, @$arrayRef ) );
		}
		$get_dead_users->finish();
	}
	my $rows = $cleanup_users->execute($time) + 0;
	$cleanup_nickid->execute();
	$cleanup_chanuser->execute();
	if(DEBUG) {
		ircd::privmsg('ServServ', main_conf_diag, "Deleted $rows dead users\n");
		ircd::privmsg('ServServ', main_conf_diag, "Ending cleanup_users()");
	}
}

sub fix_vhosts() {
	return; # XXX
	add_timer('fix_vhosts', 5, __PACKAGE__, 'nickserv::fix_vhosts');
	$get_hostless_nicks->execute();
	while (my ($nick) = $get_hostless_nicks->fetchrow_array) {
		ircd::notice($nsnick, main_conf_diag, "HOSTLESS NICK $nick");
		ircd::userhost($nick);
		ircd::userip($nick);
	}
	$get_hostless_nicks->finish();
}

sub nick_cede($) {
	my ($nick) = @_;
	my $id;

	$get_user_id->execute($nick);
	if($id = $get_user_id->fetchrow_array) {
		$nick_id_delete->execute($id);
		$nick_delete->execute($nick);
	}
}

### IRC EVENTS ###

sub nick_create {
	my ($nick, $time, $ident, $host, $vhost, $server, $svsstamp, $modes, $gecos, $ip, $cloakhost) = @_;
	my $user = { NICK => $nick };
	get_lock($nick);
	if ($vhost eq '*') {
		if ({modes::splitumodes($modes)}->{x} eq '+') {
			if(defined($cloakhost)) {
				$vhost = $cloakhost;
			}
			else { # This should never happen with CLK or VHP
				ircd::userhost($nick);
			}
		} else {
			$vhost = $host;
		}
	}

	my $id;
	if($svsstamp) {
		$get_user_nick->execute($svsstamp);
		my ($oldnick) = $get_user_nick->fetchrow_array();
		$id = $svsstamp if defined($oldnick);
	}
	else {
		$nick_check->execute($nick, $time);
		($id) = $nick_check->fetchrow_array;
	}

	if($id) {
		$olduser{lc $nick} = 1;
		$nick_create_old->execute($nick, $ident, $host, $vhost, $server, $modes, $gecos, UF_FINISHED(), $cloakhost, $id);
	} else {
		nick_cede($nick);
		
		my $flags = (synced() ? UF_FINISHED() : 0);
		my $i;
		while($i < 10 and !$nick_create->execute($nick, $time, $ident, $host, $vhost, $server, $modes, $gecos, $flags, $cloakhost)) { $i++ }
		$id = get_user_id( { NICK => $nick } ); # There needs to be a better way to do this
	}
	ircd::setsvsstamp($nsnick, $nick, $id) unless $svsstamp == $id;

	$add_nickchg->execute($ircline, $nick, $nick);

	release_lock($nick);

	$newuser{lc $nick} = 1;

	if($ip) {
		nickserv::userip(undef, $nick, $ip);
	}
	else { # This should never happen with NICKIP
		ircd::userip($nick);
	}

	return $id;
}

sub nick_create_post($) {
	my ($nick) = @_;
	my $user = { NICK => $nick };
	my $old = $olduser{lc $nick};
	delete $olduser{lc $nick};

	operserv::do_news($nick, 'u') unless($old);

	get_lock($nick);

	check_identify($user);

	release_lock($nick);
}

sub nick_delete($$) {
	my ($nick, $quit) = @_;
	my $user = { NICK => $nick };
	
	get_lock($nick);
	
	my $id = get_user_id($user);

	$del_nickchg_id->execute($id); $del_nickchg_id->finish();

	$quit_update->execute($quit, $id); $quit_update->finish();
	$update_lastseen->execute($id); $update_lastseen->finish();

	$get_quit_empty_chans->execute($id);

	$chan_user_partall->execute($id); $chan_user_partall->finish();
	#$nick_chan_delete->execute($id); $nick_chan_delete->finish();
	$nick_quit->execute($nick); $nick_quit->finish();

	release_lock($nick);

	while(my ($cn) = $get_quit_empty_chans->fetchrow_array) {
		chanserv::channel_emptied({CHAN => $cn});
	}
	$get_quit_empty_chans->finish();
}

sub squit($$$) {
	my (undef, $servers, $reason) = @_;

	$get_squit_lock->execute; $get_squit_lock->finish;

	foreach my $server (@$servers) {
		$get_squit_empty_chans->execute($server);

		$squit_nickreg->execute($server);
		$squit_nickreg->finish;

		$squit_lastquit->execute("Netsplit from $server", $server);
		$squit_lastquit->finish;

		$squit_users->execute($server);
		$squit_users->finish;

		while(my ($cn) = $get_squit_empty_chans->fetchrow_array) {
			chanserv::channel_emptied({CHAN => $cn});
		}
		$get_squit_empty_chans->finish;
	}

	$unlock_tables->execute; $unlock_tables->finish;
}

sub nick_change($$$) {
	my ($old, $new, $time) = @_;

	return if(lc $old eq lc $new);

	get_lock($old);
	nick_cede($new);
	$nick_change->execute($new, $time, $old);
	$add_nickchg->execute($ircline, $new, $new);
	release_lock($old);

	if($new =~ /^guest/i) {
		$get_guest->execute($new);
		my ($guest) = $get_guest->fetchrow_array();
		if($guest) {
			$set_guest->execute(0, $new);
		} else {
			guestnick($new);
		}
		return;
	}
	
	ircd::setumode($nsnick, $new, '-r') 
		unless check_identify({ NICK => $new });
}

sub umode($$) {
	my ($nick, $modes) = @_;
	my $user = { NICK => $nick };

	get_lock($nick);

	my $id = get_user_id($user);
	
	$get_umodes->execute($id);
	my ($omodes) = $get_umodes->fetchrow_array;
	$set_umodes->execute(modes::add($omodes, $modes, 0), $id);


	my %modelist = modes::splitumodes($modes);
	if (defined($modelist{x})) {
		if($modelist{x} eq '-') {
			my ($ident, $host) = get_host($user);
			do_chghost(undef, $nick, $host, 1);
		}
		elsif(($modelist{x} eq '+') and !defined($modelist{t}) ) {
			my (undef, $cloakhost) = get_cloakhost($user);
			if($cloakhost) {
				do_chghost(undef, $nick, $cloakhost, 1);
			} else {
				ircd::userhost($nick);
			}
		}
	}
=cut
# awaiting resolution UnrealIRCd bug 2613
	elsif ($modelist{t} eq '-') {
		my %omodelist = modes::splitumodes($omodes);
		if($omodelist{x} eq '+') {
			my (undef, $cloakhost) = get_cloakhost($user);
			if($cloakhost) {
				do_chghost(undef, $nick, $cloakhost, 1);
			} else {
				ircd::userhost($nick);
			}
		}
	}
=cut
	release_lock($nick);

	# Else we will get it in a sethost or chghost
	# Also be aware, our tracking of umodes xt is imperfect
	# as the ircd doesn't always report it to us
	# This might need fixing up in chghost()
}

sub killhandle($$$$) {
	my ($src, $dst, $path, $reason) = @_;
	unless (is_agent($dst)) {
		nick_delete($dst, "Killed ($src ($reason))");
	}
}

sub userip($$$) {
	my($src, $nick, $ip) = @_;
	my $is_ipv6;
	($is_ipv6, $ip) = is_ipv6($ip);
	my $user = { 'NICK' => $nick };
	my $new = $newuser{lc $nick};
	delete $newuser{lc $nick};
	#my $targetid = get_nick_id($target);
	my $iip;
	if(!$is_ipv6) {
		my @ips = split(/\./, $ip);
		for(my $i; $i < 4; $i++) {
			$iip += $ips[$i] * (2 ** ((3 - $i) * 8));
		}
	} else {
		$iip = Socket6::inet_pton(&AF_INET6, $ip);
	}

	get_lock($nick);

	my $id = get_user_id($user);
	if(!$is_ipv6) {
		set_ip($user, $iip);
	} else {
		$iip = get_ipv6_net($ip);
		set_ipv6($user, $iip, $ip);
	}
	my $killed = kill_clones($user, $iip);

	release_lock($nick);

	nick_create_post($nick) if(!$killed and $new);
}

sub chghost($$$) {
	my ($src, $dst, $vhost) = @_;
	my $user = { NICK => $dst };
	my $uid = get_user_id($user);

	get_lock($dst);
	do_chghost($src, $dst, $vhost, 1);
	
	$get_umodes->execute($uid);
	my ($omodes) = $get_umodes->fetchrow_array;
	# I'm told that this is only valid if CLK is set, and
	# there is no good way yet to get info from the ircd/net
	# module to this code. it stinks of ircd-specific too
	# Also, we currently do any USERHOST replies as CHGHOST events
	# However, that is no longer necessary with CLK
	$set_umodes->execute(modes::add($omodes, '+xt', 0), $uid);
	release_lock($dst);
}

sub do_chghost($$$;$) {
# Don't use this for the handler,
# this is only for internal use
# where we don't want full loopback semantics.
# We call it from the normal handler.
	my ($src, $dst, $vhost, $no_lock) = @_;
# $no_lock is for where we already took the lock in the caller
# MySQL's GET LOCK doesn't allow recursive locks
	my $user = { NICK => $dst };
	my $uid = get_user_id($user);
	
	$update_regnick_vhost->execute($vhost, $uid);
	$update_regnick_vhost->finish();
	
	get_lock($dst) unless $no_lock;
	
	set_vhost($user, $vhost);
	chanserv::akick_alluser($user);

	release_lock($dst) unless $no_lock;
}

sub chgident($$$) {
	my ($src, $dst, $ident) = @_;
	my $user = { NICK => $dst };
	
	set_ident($user, $ident);
	chanserv::akick_alluser($user);
}

1;
