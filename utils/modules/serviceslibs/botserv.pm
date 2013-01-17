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
package botserv;

use strict;
no strict 'refs';

use Safe;

use SrSv::Agent;
use SrSv::Process::Worker 'ima_worker'; #FIXME

use SrSv::Text::Format qw(columnar);
use SrSv::Errors;

use SrSv::Conf2Consts qw( main services );

use SrSv::User qw(get_user_nick get_user_id :flood);
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::ChanReg::Flags;
use SrSv::NickReg::Flags qw(NRF_NOHIGHLIGHT nr_chk_flag_user);

use SrSv::MySQL '$dbh';

use constant {
	F_PRIVATE 	=> 1,
	F_DEAF		=> 2
};

our $bsnick_default = 'BotServ';
our $bsnick = $bsnick_default;
our $botchmode;
if(!ircd::PREFIXAQ_DISABLE()) {
	$botchmode = '+q';
} else {
	$botchmode = '+qo';
}

*agent = \&chanserv::agent;

our $calc_safe = new Safe;

our (
	$get_all_bots, $get_botchans, $get_botstay_chans, $get_chan_bot, $get_bots_chans, $get_bot_info,

	$create_bot, $delete_bot, $delete_bot_allchans, $assign_bot, $unassign_bot,
	$change_bot, $update_chanreg_bot,

	$is_bot, $has_bot,

	$set_flag, $unset_flag, $get_flags
);

sub init() {
	$get_all_bots = $dbh->prepare("SELECT nick, ident, vhost, gecos, flags FROM bot");
	$get_botchans = $dbh->prepare("SELECT chan, COALESCE(bot, '$chanserv::csnick') FROM chanreg WHERE bot != '' OR (flags & ". CRF_BOTSTAY() . ")");
	$get_botstay_chans = $dbh->prepare("SELECT chan, COALESCE(bot, '$chanserv::csnick') FROM chanreg WHERE (flags & ".
		CRF_BOTSTAY() . ")");
	$get_chan_bot = $dbh->prepare("SELECT bot FROM chanreg WHERE chan=?");
	$get_bots_chans = $dbh->prepare("SELECT chan FROM chanreg WHERE bot=?");
	$get_bot_info = $dbh->prepare("SELECT nick, ident, vhost, gecos, flags FROM bot WHERE nick=?");

	$create_bot = $dbh->prepare("INSERT INTO bot SET nick=?, ident=?, vhost=?, gecos=?");
	$delete_bot = $dbh->prepare("DELETE FROM bot WHERE nick=?");
	$delete_bot_allchans = $dbh->prepare("UPDATE chanreg SET bot='' WHERE bot=?");
	$change_bot = $dbh->prepare("UPDATE bot SET nick=?, ident=?, vhost=?, gecos=? WHERE nick=?");
	$update_chanreg_bot = $dbh->prepare("UPDATE chanreg SET bot=? WHERE bot=?");

	$assign_bot = $dbh->prepare("UPDATE chanreg, bot SET chanreg.bot=bot.nick WHERE bot.nick=? AND chan=?");
	$unassign_bot = $dbh->prepare("UPDATE chanreg SET chanreg.bot='' WHERE chan=?");

	$is_bot = $dbh->prepare("SELECT 1 FROM bot WHERE nick=?");
	$has_bot = $dbh->prepare("SELECT 1 FROM chanreg WHERE chan=? AND bot != ''");

	$set_flag = $dbh->prepare("UPDATE bot SET flags=(flags | (?)) WHERE nick=?");
	$unset_flag = $dbh->prepare("UPDATE bot SET flags=(flags & ~(?)) WHERE nick=?");
	$get_flags = $dbh->prepare("SELECT flags FROM bot WHERE bot.nick=?");

	register() unless ima_worker; #FIXME
};

sub dispatch($$$) {
        my ($src, $dst, $msg) = @_;
	
	if(lc $dst eq lc $bsnick or lc $dst eq lc $bsnick_default ) {
		bs_dispatch($src, $dst, $msg);
	}
	elsif($dst =~ /^#/) {
		if($msg =~ /^\!/) {
			$has_bot->execute($dst);
			return unless($has_bot->fetchrow_array);
			chan_dispatch($src, $dst, $msg);
		} else {
			chan_msg($src, $dst, $msg);
		}
	}
	else {
		$is_bot->execute($dst);
		if($is_bot->fetchrow_array) {
			bot_dispatch($src, $dst, $msg);
		}
	}
}

### BOTSERV COMMANDS ###

sub bs_dispatch($$$) {
	my ($src, $dst, $msg) = @_;
	$msg =~ s/^\s+//;
	my @args = split(/\s+/, $msg);
	my $cmd = shift @args;

	my $user = { NICK => $src, AGENT => $dst };

	return if flood_check($user);

	if($cmd =~ /^assign$/i) {
		if (@args == 2) {
			bs_assign($user, {CHAN => $args[0]}, $args[1]);
		} else {
			notice($user, 'Syntax: ASSIGN <#channel> <bot>');
		}
	}
	elsif ($cmd =~ /^unassign$/i) {
		if (@args == 1) {
			bs_assign($user, {CHAN => $args[0]}, '');
		} else {
			notice($user, 'Syntax: UNASSIGN <#channel>');
		}
	}
	elsif ($cmd =~ /^list$/i) {
		if(@args == 0) {
			bs_list($user);
		} else {
			notice($user, 'Syntax: LIST');
		}
	}
	elsif ($cmd =~ /^add$/i) {
		if (@args >= 4) {
			@args = split(/\s+/, $msg, 5);
			bs_add($user, $args[1], $args[2], $args[3], $args[4]);
		} else {
			notice($user, 'Syntax: ADD <nick> <ident> <vhost> <realname>');
		}
	}
	elsif ($cmd =~ /^change$/i) {
		if (@args >= 4) {
			@args = split(/\s+/, $msg, 6);
			bs_change($user, $args[1], $args[2], $args[3], $args[4], $args[5]);
		} else {
			notice($user, 'Syntax: ADD <oldnick> <nick> <ident> <vhost> <realname>');
		}
	}
	elsif ($cmd =~ /^del(ete)?$/i) {
		if (@args == 1) {
			bs_del($user, $args[0]);
		} else {
			notice($user, 'Syntax: DEL <botnick>');
		}
	}
	elsif($cmd =~ /^set$/i) {
		if(@args == 3) {
			bs_set($user, $args[0], $args[1], $args[2]);
		} else {
			notice($user, 'Syntax: SET <botnick> <option> <value>');
		}
	}
	elsif($cmd =~ /^seen$/i) {
		if(@args >= 1) {
			nickserv::ns_seen($user, @args);
		} else {
			notice($user, 'Syntax: SEEN <nick> [nick ...]');
		}
	}
	
	elsif($cmd =~ /^(say|act)$/i) {
		if(@args > 1) {
			my @args = split(/\s+/, $msg, 3);
			my $botmsg = $args[2];
			$botmsg = "\001ACTION $botmsg\001" if(lc $cmd eq 'act');
			bot_say($user, {CHAN => $args[1]}, $botmsg);
		} else {
			notice($user, 'Syntax: '.uc($cmd).' <#chan> <message>');
		}
	}
	elsif($cmd =~ /^info$/i) {
		if(@args == 1) {
			bs_info($user, $args[0]);
		} else {
			notice($user, 'Syntax: INFO <botnick>');
		}
	}
	elsif($cmd =~ /^help$/i) {
		sendhelp($user, 'botserv', @args);
	}
	elsif($cmd =~ /^d(ice)?$/i) {
		notice($user, get_dice($args[0]));
	}
	else {
		notice($user, "Unrecognized command.  For help, type: \002/bs help\002");
	}
}

# For unassign, set $bot to ''
# 
sub bs_assign($$$) {
	my ($user, $chan, $bot) = @_;

	chanserv::chk_registered($user, $chan) or return;

	unless (chanserv::can_do($chan, 'BotAssign', $user)) {
		notice($user, $err_deny);
		return;
	}
	
	if ($bot) {
        	$is_bot->execute($bot);
		unless($is_bot->fetchrow_array) {
			notice($user, "\002$bot\002 is not a bot.");
			return;
		}
	}

	$get_flags->execute($bot);
	my ($botflags) = $get_flags->fetchrow_array;
	if (($botflags & F_PRIVATE) && !adminserv::can_do($user, 'BOT')) {
		notice($user, $err_deny);
		return;
	}
	

	my $cn = $chan->{CHAN};
	my $src = get_user_nick($user);
	my $oldbot;
	if ($oldbot = get_chan_bot($chan)) {
		agent_part($oldbot, $cn, "Unassigned by \002$src\002.");
	}

	
	
	if($bot) {
		$assign_bot->execute($bot, $cn);
		bot_join($chan, $bot);
		notice($user, "\002$bot\002 now assigned to \002$cn\002.");
	} else {
		$unassign_bot->execute($cn);
		notice($user, "\002$oldbot\002 removed from \002$cn\002.");
	}
}

sub bs_list($) {
	my ($user) = @_;
	my @data;
	my $is_oper = adminserv::is_svsop($user, adminserv::S_HELP());
	
	$get_all_bots->execute();
	while (my ($botnick, $botident, $bothost, $botgecos, $flags) = $get_all_bots->fetchrow_array) {
		if($is_oper) {
			push @data, [$botnick, "($botident\@$bothost)", $botgecos, 
				(($flags & F_PRIVATE) ? "Private":"Public")];
		} else {
			next if($flags & F_PRIVATE);
			push @data, [$botnick, "($botident\@$bothost)", $botgecos];
		}
	}
	
	notice($user, columnar({TITLE => "The following bots are available:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data));
}

sub bs_add($$$$$) {
	my ($user, $botnick, $botident, $bothost, $botgecos) = @_;
	
	unless (adminserv::can_do($user, 'BOT')) {
		notice($user, $err_deny);
		return;
	}

	if (my $ret = is_invalid_agentname($botnick, $botident, $bothost)) {
		notice($user, $ret);
		return;
	}

	if(nickserv::is_registered($botnick)) {
		notice($user, "The nick \002$botnick\002 is already registered.");
		return;
	}

	if(nickserv::is_online($botnick)) {
		notice($user, "The nick \002$botnick\002 is currently in use.");
		return;
	}

	$is_bot->execute($botnick);
	if($is_bot->fetchrow_array) {
		notice($user, "\002$botnick\002 already exists.");
		return;
	}

	$create_bot->execute($botnick, $botident, $bothost, $botgecos);
	ircd::sqline($botnick, $services::qlreason);
	agent_connect($botnick, $botident, $bothost, '+pqBSrz', $botgecos);
	agent_join($botnick, main_conf_diag);
	ircd::setmode($main::rsnick, main_conf_diag, '+h', $botnick);

	notice($user, "Bot $botnick connected.");
}

sub bs_del($$) {
	my ($user, $botnick) = @_;
	
	unless (adminserv::can_do($user, 'BOT')) {
		notice($user, $err_deny);
		return;
	}
	$is_bot->execute($botnick);
	if (!$is_bot->fetchrow_array) {
		notice($user, "\002$botnick\002 is not a bot.");
		return;
	}
	
	my $src = get_user_nick($user);
	$delete_bot->execute($botnick);
	agent_quit($botnick, "Deleted by \002$src\002.");
	ircd::unsqline($botnick);
	
	$delete_bot_allchans->execute($botnick);
	notice($user, "Bot \002$botnick\002 disconnected.");
}

sub bs_set($$$$) {
	my ($user, $botnick, $set, $parm) = @_;

	unless (adminserv::can_do($user, 'BOT')) {
		notice($user, $err_deny);
		return;
	}
	if($set =~ /^private$/i) {
		if ($parm =~ /^(on|true)$/i) {
			set_flag($botnick, F_PRIVATE());
			notice($user, "\002$botnick\002 is now private.");
		}
		elsif ($parm =~ /^(off|false)$/i) {
			unset_flag($botnick, F_PRIVATE());
			notice($user, "\002$botnick\002 is now public.");
		}
		else {
			notice($user, 'Syntax: SET <botnick> PRIVATE <ON|OFF>');
		}
	}
	if($set =~ /^deaf$/i) {
		if ($parm =~ /^(on|true)$/i) {
			set_flag($botnick, F_DEAF());
			setagent_umode($botnick, '+d');
			notice($user, "\002$botnick\002 is now deaf.");
		}
		elsif ($parm =~ /^(off|false)$/i) {
			unset_flag($botnick, F_DEAF());
			setagent_umode($botnick, '-d');
			notice($user, "\002$botnick\002 is now undeaf.");
		}
		else {
			notice($user, 'Syntax: SET <botnick> DEAF <ON|OFF>');
		}
	}
}

sub bs_info($$) {
	my ($user, $botnick) = @_;

	unless (adminserv::can_do($user, 'HELP')) {
		notice($user, $err_deny);
		return;
	}
	$is_bot->execute($botnick);
	unless($is_bot->fetchrow_array) {
		notice($user, "\002$botnick\002 is not a bot.");
		return;
	}

	$get_bot_info->execute($botnick);
	my ($nick, $ident, $vhost, $gecos, $flags) = $get_bot_info->fetchrow_array;
	$get_bot_info->finish();
	$get_bots_chans->execute($botnick);
	my @chans = ();
	while (my $chan = $get_bots_chans->fetchrow_array) {
		push @chans, $chan;
	}
	$get_bots_chans->finish();

	notice($user, columnar({TITLE => "Information for bot \002$nick\002:", 
			NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)},
		['Mask:', "$ident\@$vhost"], ['Realname:', $gecos], 
		['Flags:', (($flags & F_PRIVATE())?'Private ':'').(($flags & F_DEAF())?'Deaf ':'')],
		{COLLAPSE => [
			'Assigned to '. @chans.' channel(s):',
			'  ' . join(' ', @chans)
		]}
	));
}

sub bs_change($$$$$$) {
	my ($user, $oldnick, $botnick, $botident, $bothost, $botgecos) = @_;
	
	if (lc $oldnick eq lc $botnick) {
		notice($user, "Error: $oldnick is the same (case-insensitive) as $botnick", 
			"At this time, you cannot change only the ident, host, gecos, or nick-case of a bot.");
		return;
	}

	unless (adminserv::can_do($user, 'BOT')) {
		notice($user, $err_deny);
		return;
	}

	if (my $ret = is_invalid_agentname($botnick, $botident, $bothost)) {
		notice($user, $ret);
		return;
	}

	if(nickserv::is_registered($botnick)) {
		notice($user, "The nick \002$botnick\002 is already registered.");
		return;
	}

	if(nickserv::is_online($botnick)) {
		notice($user, "The nick \002$botnick\002 is currently in use.");
		return;
	}

	$is_bot->execute($botnick);
	if($is_bot->fetchrow_array) {
		notice($user, "\002$botnick\002 already exists.");
		return;
	}

	#Create bot first, join it to its chans
	# then finally delete the old bot
	# This is to prevent races.
	$create_bot->execute($botnick, $botident, $bothost, $botgecos);
	ircd::sqline($botnick, $services::qlreason);
	agent_connect($botnick, $botident, $bothost, '+pqBSrz', $botgecos);
	agent_join($botnick, main_conf_diag);
	ircd::setmode($main::rsnick, main_conf_diag, '+h', $botnick);

	notice($user, "Bot $botnick connected.");

	$get_bots_chans->execute($oldnick);
	while(my ($cn) = $get_bots_chans->fetchrow_array()) {
		my $chan = { CHAN => $cn };
		bot_join($chan, $botnick)
			if chanserv::get_user_count($chan) or cr_chk_flag($chan, CRF_BOTSTAY(), 1);
	}
	$get_bots_chans->finish();

	$update_chanreg_bot->execute($botnick, $oldnick); $update_chanreg_bot->finish();

	my $src = get_user_nick($user);
	$delete_bot->execute($oldnick);
	agent_quit($oldnick, "Deleted by \002$src\002.");
	ircd::unsqline($oldnick);
	notice($user, "Bot \002$oldnick\002 disconnected.");
}

### CHANNEL COMMANDS ###

sub chan_dispatch($$$) {
	my ($src, $cn, $msg) = @_;

	my @args = split(/\s+/, $msg);
	my $cmd = lc(shift @args);
	$cmd =~ s/^\!//;

	my $chan = { CHAN => $cn };
	my $user = { NICK => $src, AGENT => agent($chan) };

	my %cmdhash = (
		'voice'		=>	\&give_ops,
		'devoice'	=>	\&give_ops,
		'hop'		=>	\&give_ops,
		'halfop'	=>	\&give_ops,
		'dehop'		=>	\&give_ops,
		'dehalfop'	=>	\&give_ops,
		'op'		=>	\&give_ops,
		'deop'		=>	\&give_ops,
		'protect'	=>	\&give_ops,
		'admin'		=>	\&give_ops,
		'deprotect'	=>	\&give_ops,
		'deadmin'	=>	\&give_ops,

		'up'		=>	\&up,

		'down'		=>	\&down,
		'molest'	=>	\&down,

		'invite'	=>	\&invite,

		'kick'		=>	\&kick,
		'k'		=>	\&kick,

		'kb'		=>	\&kickban,
		'kickb'		=>	\&kickban,
		'kban'		=>	\&kickban,
		'kickban'	=>	\&kickban,
		'bk'		=>	\&kickban,
		'bkick'		=>	\&kickban,
		'bank'		=>	\&kickban,
		'bankick'	=>	\&kickban,

		'kickmask'	=>	\&kickmask,
		'km'		=>	\&kickmask,
		'kmask'		=>	\&kickmask,

		'kickbanmask'	=>	\&kickbanmask,
		'kickbmask'	=>	\&kickbanmask,
		'kickbm'	=>	\&kickbanmask,
		'kbm'		=>	\&kickbanmask,
		'kbanm'		=>	\&kickbanmask,
		'kbanmask'	=>	\&kickbanmask,
		'kbmask'	=>	\&kickbanmask,

		'calc'		=>	\&calc,

		'seen'		=>	\&seen,

		#We really need something that is mostly obvious
		# and won't be used by any other bots.
		#TriviaBot I added !trivhelp
		# I guess anope uses !commands
		'help'		=>	\&help,
		'commands'	=>	\&help,
		'botcmds'	=>	\&help,

		'abbrevs'	=>	\&help,
		'abbreviations'	=>	\&help,
		'abbrev'	=>	\&help,

		'users'		=>	\&alist,
		'alist'		=>	\&alist,

		'unban'		=>	\&unban,

		'banlist'	=>	\&banlist,
		'blist'		=>	\&banlist,

		'ban'		=>	\&ban,
		'b'		=>	\&ban,
		'qban'		=>	\&ban,
		'nban'		=>	\&ban,

		'd'		=>	\&dice,
		'dice'		=>	\&dice,

		'mode'		=>	\&mode,
		'm'		=>	\&mode,

		'resync'	=>	\&resync,

		'topic'		=>	\&topic,
		't'		=>	\&topic,

		'why'		=>	\&why,
		'tempban' => \&tempban,
		'tmpban' => \&tempban,
		"tb" => \&tempban,
	);

	sub give_ops {
		my ($user, $chan, $cmd, undef, @args) = @_;
		chanserv::cs_setmodes($user, $cmd, $chan, @args);
	}
	sub up {
		my ($user, $chan, $cmd, undef, @args) = @_;
		chanserv::cs_updown($user, $cmd, $chan->{CHAN}, @args);
	}
	sub down {
		my ($user, $chan, $cmd, undef, @args) = @_;
		if(lc $cmd eq 'molest') {
			chanserv::unset_modes($user, $chan);
		} else {
			chanserv::cs_updown($user, $cmd, $chan->{CHAN}, @args);
		}
	}

	sub invite {
		my ($user, $chan, $cmd, undef, @args) = @_;
		chanserv::cs_invite($user, $chan, @args) unless @args == 0;
	}

	sub kick {
		my ($user, $chan, $cmd, undef, @args) = @_;
		my $target = shift @args or return;
		chanserv::cs_kick($user, $chan, $target, 0, join(' ', @args));
	}
	sub tempban {
		my ($user, $chan, $cmd, undef, @args) = @_;
       
        my $cn = $chan->{CHAN};
        use Data::Dumper;

        unshift @args, $cn;
        print ("ARGS " . Dumper (@args));
		chanserv::cs_tempban($user, join(' ', @args));
	}
	sub kickban {
		my ($user, $chan, $cmd, undef, @args) = @_;
		my $target = shift @args or return;
		chanserv::cs_kick($user, $chan, $target, 1, join(' ', @args));
	}

	sub kickmask {
		my ($user, $chan, $cmd, undef, @args) = @_;
		my $target = shift @args or return;
		chanserv::cs_kickmask($user, $chan, $target, 0, join(' ', @args));
	}
	sub kickbanmask {
		my ($user, $chan, $cmd, undef, @args) = @_;
		my $target = shift @args or return;
		chanserv::cs_kickmask($user, $chan, $target, 1, join(' ', @args));
	}

	sub calc {
		my ($user, $chan, $cmd, undef, @args) = @_;
		my $msg = join(' ', @args);
		for ($msg) {
			s/,/./g;
			s/[^*.+0-9&|)(x\/^-]//g;
			s/([*+\\.\/x-])\1*/$1/g;
			s/\^/**/g;
			s/(?<!0)x//g;
		}

		my $answer = $calc_safe->reval("($msg) || 0");
		$answer = 'ERROR' unless defined $answer;

		notice($user, ($@ ? "$msg = ERROR (${\ (split / at/, $@, 2)[0]})" : "$msg = $answer"));
	}

	sub seen {
		my ($user, $chan, $cmd, undef, @args) = @_;
		
		if(@args >= 1) {
			nickserv::ns_seen($user, @args);
		} else {
			notice($user, 'Syntax: SEEN <nick> [nick ...]');
		}
	}

	sub help {
		my ($user, $chan, $cmd, undef, @args) = @_;
		if($cmd =~ /^abbrev(iation)?s?$/) {
			sendhelp($user, 'chanbot', 'abbreviations');
		} else {
			sendhelp($user, 'chanbot');
		}
	}

	sub alist {
		my ($user, $chan, $cmd, undef, @args) = @_;
		chanserv::cs_alist($user, $chan);
	}

	sub unban {
		my ($user, $chan, $cmd, undef, @args) = @_;
		if(@args == 0) {
			chanserv::cs_unban($user, $chan, get_user_nick($user));
		}
		elsif(@args >= 1) {
			chanserv::cs_unban($user, $chan, @args);
		}
	}

	sub ban {
		my ($user, $chan, $cmd, undef, @args) = @_;
		$cmd =~ /^(q|n)?ban$/; my $type = $1;
		if(@args >= 1) {
			chanserv::cs_ban($user, $chan, $type, @args);
		}
	}

	sub banlist {
		my ($user, $chan, $cmd, undef, @args) = @_;
		chanserv::cs_banlist($user, $chan);
	}

	sub dice {
	# FIXME: If dice is disabled, don't count towards flooding.
		my ($user, $chan, $cmd, undef, @args) = @_;

		if(chanserv::can_do($chan, 'DICE', $user)) {
			ircd::privmsg(agent($chan), $chan->{CHAN},
				get_dice($args[0]));
		}
	}

	sub mode {
		my ($user, $chan, $cmd, undef, @args) = @_;
		if(@args >= 1) {
			chanserv::cs_mode($user, $chan, shift @args, @args);
		}
	}

	sub resync {
		my ($user, $chan, $cmd) = @_;
		chanserv::cs_resync($user, $chan->{CHAN});
	}

	sub topic {
		my ($user, $chan, $cmd, $msg) = @_;
		if (@args >= 1) {
			$msg =~ s/^!$cmd //;
			chanserv::cs_topic($user, $chan, $msg);
		}
	}

	sub why {
		my ($user, $chan, $cmd, undef, @args) = @_;
		
		if(@args >= 1) {
			chanserv::cs_why($user, $chan, @args);
		} else {
			notice($user, 'Syntax: WHY <nick> [nick ...]');
		}
	}
	if(defined($cmdhash{$cmd})) {
		return if flood_check($user);

		&{$cmdhash{$cmd}}($user, $chan, $cmd, $msg, @args);
	}
}

sub bot_say($$$) {
	my ($user, $chan, $botmsg) = @_;
	my $cn = $chan->{CHAN};
	
	if(chanserv::can_do($chan, 'BotSay', $user)) {
		ircd::notice(agent($chan), '%'.$cn, get_user_nick($user).' used BotSay')
			if cr_chk_flag($chan, CRF_VERBOSE());
		ircd::privmsg(agent($chan), $cn, $botmsg);
	} else {
		# can_do will give the $err_deny for us.
		#notice($user, $err_deny);
	}
}

### BOT COMMANDS ###

sub bot_dispatch($$$) {
    my ($src, $bot, $msg) = @_;
    
    my ($cmd, $cn, $botmsg) = split(/ /, $msg, 3);

    my $user = { NICK => $src, AGENT => $bot };
    my $chan = { CHAN => $cn };

    return if flood_check($user);
    
    if ($cmd =~ /^join$/i) {
	    if (adminserv::can_do($user, 'BOT')) {
	    agent_join($bot, $cn);
	} else { 
	    notice($user, $err_deny);
	}
    }
    elsif ($cmd =~ /^part$/i) {
	if (adminserv::can_do($user, 'BOT')) {
	    agent_part($bot, $cn, "$src requested part");
	} else { 
	    notice($user, $err_deny);
	}
    }
    elsif ($cmd =~ /^say$/i) {
    	bot_say($user, $chan, $botmsg);
    }
    elsif ($cmd =~ /^act$/i) {
    	bot_say($user, $chan, "\001ACTION $botmsg\001");
    }
    elsif ($cmd =~ /^help$/i) {
    	#my @help; @help = ($cn) if $cn; push @help, split(/\s+/, $botmsg);
    	sendhelp($user, 'botpriv');
    }
}

sub get_dice($) {
	my ($count, $sides) = map int($_), ($_[0] ? split('d', $_[0]) : (1, 6));
	
	if ($sides < 1 or $sides > 1000 or $count < 0 or $count > 100) {
		return "Sorry, you can't have more than 100 dice, or 1000 sides, or less than 1 of either.";
	}
	$count = 1 if $count == 0;
	
	my $sum = 0;

	if($count == 1 or $count > 25) {
		for(my $i = 1; $i <= $count; $i++) {
			$sum += int(rand($sides)+1);
		}

		return "${count}d$sides: $sum";
	}
	else {
		my @dice;

		for(my $i = 1; $i <= $count; $i++) {
			my $n = int(rand($sides)+1);
			$sum += $n;
			push @dice, $n;
		}
		
		return "${count}d$sides: $sum  [" . join(' ', sort {$a <=> $b} @dice) . "]";
	}
}

### IRC EVENTS ###

sub chan_msg($$$) {
	#We don't do chanmsg processing yet, like badwords.
}

sub register() {
	$get_all_bots->execute();
	while(my ($nick, $ident, $vhost, $gecos, $flags) = $get_all_bots->fetchrow_array) {
		agent_connect($nick, $ident, $vhost, '+pqBSrz'.(($flags & F_DEAF())?'d':''), $gecos);
		ircd::sqline($nick, $services::qlreason);
		agent_join($nick, main_conf_diag);
		ircd::setmode($main::rsnick, main_conf_diag, '+h', $nick);
	}
}

sub eos() {
	$get_botchans->execute();
	while(my ($cn, $nick) = $get_botchans->fetchrow_array) {
		my $chan = { CHAN => $cn };
		if(chanserv::get_user_count($chan)) {
			bot_join($chan, $nick);
		}
		elsif(cr_chk_flag($chan, CRF_BOTSTAY(), 1)) {
			bot_join($chan, $nick);
			my $modelock = chanserv::get_modelock($chan);
			ircd::setmode(main_conf_local, $cn, $modelock) if $modelock;
		}
	}
}

### Database Functions ###

sub set_flag($$) {
	my ($bot, $flag) = @_;

	$set_flag->execute($flag, $bot);
}

sub unset_flag($$) {
	my ($bot, $flag) = @_;

	$unset_flag->execute($flag, $bot);
}

sub bot_join($;$) {
	my ($chan, $nick) = @_;

	my $cn = $chan->{CHAN};

	$nick = agent($chan) unless $nick;
	
	unless(is_agent_in_chan($nick, $cn)) {
		agent_join($nick, $cn);
		ircd::setmode($nick, $cn, $botchmode, $nick.(ircd::PREFIXAQ_DISABLE() ? ' '.$nick : '') );
	}
}

sub bot_part_if_needed($$$;$) {
	my ($nick, $chan, $reason, $empty) = @_;
	my $cn = $chan->{CHAN};
	my $bot = get_chan_bot($chan);
	$nick = agent($chan) unless $nick;

	return if (lc $chanserv::enforcers{lc $cn} eq lc $nick);

	if(is_agent_in_chan($nick, $cn)) {
		if(lc $bot eq lc $nick) {
			if(cr_chk_flag($chan, CRF_BOTSTAY(), 1) or ($empty != 1 or chanserv::get_user_count($chan))) {
				return;
			}
		}

		agent_part($nick, $cn, $reason);
	}
}

sub get_chan_bot($) {
	my ($chan) = @_;
	my $cn = $chan->{CHAN};
	$botserv::get_chan_bot->execute($cn);
	
	my ($bot) = $botserv::get_chan_bot->fetchrow_array();
	$botserv::get_chan_bot->finish();

	return $bot;
}

1;
