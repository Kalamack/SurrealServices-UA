#!/usr/bin/perl
#
#  Copyright saturn@surrealchat.net
#  multiple feature-adds and code changes tabris@tabris.net
#
#  Licensed under the GNU Public License 
#  http://www.gnu.org/licenses/gpl.txt
#

package securitybot;

use strict;
no strict "refs";
use Time::HiRes qw(gettimeofday);

use SrSv::Process::Init;
use SrSv::IRCd::Event 'addhandler';
use SrSv::IRCd::State 'initial_synced';
use SrSv::Timer qw(add_timer);
use SrSv::Time;
use SrSv::Agent;
use SrSv::HostMask qw( parse_hostmask );
use SrSv::Conf2Consts qw(main sql);
use SrSv::SimpleHash qw(readHash writeHash);

use SrSv::Log;

use SrSv::User qw( get_user_nick );
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::MySQL '$dbh';
use SrSv::MySQL::Glob;

use SrSv::Shared qw(%conf $torip %unwhois);

use SrSv::Process::InParent qw(list_conf loadconf saveconf update_tor_list);

use SrSv::TOR;

#this stuff needs to be put into files
our $sbnick = "SecurityBot";
our $ident = 'Security';
our $gecos = 'Security Monitor (you are being monitored)';
our $umodes = '+BHSdopqz';
our $vhost = 'services.SC.bot';

our (
	$add_spamfilter, $del_spamfilter, $add_tklban, $del_tklban,
	$del_expired_tklban, $get_expired_tklban,

	$get_tklban, $get_spamfilter,
	$get_all_tklban, $get_all_spamfilter,

	$check_opm,
);

loadconf(0);
our $enabletor = $conf{'EnableTor'};
register();

addhandler('SEOS', undef, undef, "securitybot::start_timers");
addhandler('TKL', undef, undef, "securitybot::handle_tkl");

addhandler('PRIVMSG', undef, $sbnick, "securitybot::msghandle");
addhandler('NOTICE', undef, $sbnick, "securitybot::noticehandle");
addhandler('SENDSNO', undef, undef, "securitybot::snotice");
addhandler('GLOBOPS', undef, undef, "securitybot::globops");
addhandler('SMO', undef, undef, "securitybot::snotice");

if($conf{'EnableTor'} or $conf{'CTCPonConnect'} or $conf{'EnableOPM'}) {
	addhandler('NICKCONN', undef, undef, 'securitybot::nickconn');
	addhandler('USERIP', undef, undef, 'securitybot::userip');
}
	
proc_init {
	$add_tklban = $dbh->prepare_cached("REPLACE INTO tklban
		SET type=?, ident=?, host=?, setter=?, expire=?, time=?, reason=?");
	$del_tklban = $dbh->prepare_cached("DELETE FROM tklban WHERE type=? AND ident=? AND host=?");
	$add_spamfilter = $dbh->prepare_cached("REPLACE INTO spamfilter 
		SET target=?, action=?, setter=?, expire=?, time=?, bantime=?, reason=?, mask=?");
	$del_spamfilter = $dbh->prepare_cached("DELETE FROM spamfilter WHERE target=? AND action=? AND mask=?");

	$del_expired_tklban = $dbh->prepare_cached("DELETE FROM tklban WHERE expire <= UNIX_TIMESTAMP() AND expire!=0");
	$get_expired_tklban = $dbh->prepare_cached("SELECT type, ident, host, setter, expire, time, reason 
		FROM tklban WHERE expire <= UNIX_TIMESTAMP() AND expire!=0");

	$get_tklban = $dbh->prepare_cached("SELECT setter, expire, time, reason FROM tklban WHERE
		type=? AND ident=? AND host=?");
	$get_spamfilter = $dbh->prepare_cached("SELECT time, reason FROM spamfilter WHERE target=? AND action=? AND mask=?");

	$get_all_tklban = $dbh->prepare_cached("SELECT type, ident, host, setter, expire, time, reason
		FROM tklban ORDER BY type, time, host");
	$get_all_spamfilter = $dbh->prepare_cached("SELECT target, action, setter, expire, time, bantime, reason, mask, managed
		FROM spamfilter ORDER BY time, mask");

	$check_opm = $dbh->prepare_cached("SELECT 1 FROM opm WHERE ipaddr=?");
};

sub init {
	return if main::COMPILE_ONLY();
	my $tmpdbh = DBI->connect(
		"DBI:mysql:".sql_conf_mysql_db,
		sql_conf_mysql_user,
		sql_conf_mysql_pass,
		{
			AutoCommit => 1,
			RaiseError => 1
		}
	);
	$tmpdbh->do("TRUNCATE TABLE tklban");
	$tmpdbh->do("TRUNCATE TABLE spamfilter");
	$tmpdbh->disconnect();
}

=cut
my %snomasks = (
	e => 'Eyes Notice',
	v => 'VHost Notice',
	# They're prefixed already.
	#S => 'Spamfilter',
	o => 'Oper-up Notice',
);
=cut

sub snotice($$$) {
	my ($server, $type, $msg) = @_;
#	$type = $snomasks{$type};
#	diagmsg( ($type ? "[$type] " : '').$msg);
	diagmsg( $msg);
}

sub globops($$) {
	my ($src, $msg) = @_;
	diagmsg("Global -- from $src: $msg");
}

sub register {
	agent_connect($sbnick, $ident, undef, $umodes, $gecos);
	ircd::sqline($sbnick, 'Reserved for Services');
	
	agent_join($sbnick, main_conf_diag);
	ircd::setmode($sbnick, main_conf_diag, '+o', $sbnick);
}

sub start_timers {
	add_timer('', 5, __PACKAGE__, 'securitybot::start_timers2');
	expire_tkl_timed();
}

sub start_timers2 {
	update_tor_list_timed(3540) if $enabletor;
	#securitybot::ss2tkl::update_ss_timed(3300) if $conf{'EnableSS'};
};

sub nickconn {
	my ($rnick, $time, $ident, $host, $vhost, $server, $modes, $gecos, $ip, $svsstamp) = @_[0,2..4,8,5,7,9,10,6];

	goto OUT if ($svsstamp or $unwhois{lc $rnick});

	if((initial_synced and $enabletor) or $conf{'EnableOPM'} or $conf{'BanCountry'} ) {
		if ($ip) {
			check_blacklists($rnick, $ip) or return;
		}
		else {
			ircd::userip($rnick) unless module::is_loaded('services');
		}
	}

	if($conf{'CTCPonConnect'}) {
		my @ctcplist = split(/ /, $conf{'CTCPonConnect'});
		foreach my $ctcp_msg (@ctcplist) {
			if(uc($ctcp_msg) eq 'PING') {
				my ($sec, $usec) = gettimeofday();
				ircd::ctcp($sbnick, $rnick, 'PING', $sec, $usec);
			} else {
				ircd::ctcp($sbnick, $rnick, uc($ctcp_msg));
			}
		}
	}
	OUT:
	$unwhois{lc $rnick} = 1 unless ($svsstamp or $ip);
}

sub userip {
	my($src, $rnick, $ip) = @_;

	return unless($unwhois{lc $rnick});
	return unless($ip =~ /^\d{1,3}(\.\d{1,3}){3}$/);

	check_blacklists($rnick, $ip) or return;

	delete $unwhois{lc $rnick};
}

sub check_opm($) {
	my ($ip) = @_;
	$check_opm->execute($ip);
	my ($ret) = $check_opm->fetchrow_array();
	$check_opm->finish();
	return $ret;
}

sub check_country($) {
	my ($ip) = @_;
	my $ccode; 
	if(module::is_loaded('geoip')) {
		$ccode = geoip::get_ip_location($ip); 
	} elsif(module::is_loaded('country')) {
		$ccode = country::get_ip_country_aton($ip);
	}
	foreach my $country (split(/[, ]+/, $conf{'BanCountry'})) {
		if (lc $ccode eq lc $country) {
			return country::get_country_long($country);
		}
	}
	return undef;
}

sub mk_banreason($$) {
	my ($reason, $ip) = @_;
	$reason =~ s/\$/$ip/g;
	return $reason;
}

sub check_blacklists($$) {
	my ($rnick, $ip) = @_;
	
	if(initial_synced and $enabletor && $torip->{$ip}) {
		if (lc $enabletor eq lc 'vhost') {
			ircd::chghost($sbnick, $rnick, misc::gen_uuid(1, 20).'.session.tor');
		} else {
			ircd::zline($sbnick, $ip, $conf{'ProxyZlineTime'}, $conf{'TorZlineReason'});
		}
		return 0;
	}

	if($conf{'EnableOPM'} && check_opm($ip)) {
		ircd::zline($sbnick, $ip, $conf{'ProxyZlineTime'}, mk_banreason($conf{'OPMZlineReason'}, $ip));
		return 0;
	}

sub hasGeoCountry() {
	return module::is_loaded('country') || module::is_loaded('geoip');
}

	if($conf{'BanCountry'} && hasGeoCountry() && (my $country = check_country($ip))) {
		ircd::zline($sbnick, $ip, $conf{'ProxyZlineTime'}, mk_banreason($conf{'CountryZlineReason'}, $country));
		return 0;
	}

	return 1;
}

sub update_tor_list_timed($) {
	my $time = shift;
	$time = 3600 unless $time;

	add_timer('', $time, __PACKAGE__, 'securitybot::update_tor_list_timed');
	
	update_tor_list() if $enabletor;
}

sub update_tor_list() {
	return unless (defined($conf{'TorServer'}) && length($conf{'TorServer'}));
	diagmsg( " -- Loading Tor server list.");
	
	# path may be a local one if you run a tor-client.
	# most configs are /var/lib/tor/cached-directory
	my %newtorip;
	my @entries;
	local $SIG{__DIE__} = undef;
	eval {
		@entries = getTorRouters($conf{'TorServer'});
	};
	if($@) {
		ircd::debug("SecurityBot failed to load TOR data", $@);
		return;
	}
	foreach my $torIP (@entries) {
		$newtorip{$torIP} = 1;
	}

	my $torcount = scalar(keys(%newtorip));

	if($torcount > 0) {
		$torip = \%newtorip;
		diagmsg( " -- Finished loading Tor server list - $torcount servers found.");
	} else {
		diagmsg( " -- Failed to load Tor server list, CHECK YOUR TorServer SETTING.");
	}
}

sub msghandle {
		my ($rnick, $dst, $msg) = @_;
		print join("\n", @_);
		my $user = { NICK => $rnick, AGENT => $sbnick };
		unless (adminserv::is_ircop($user)) {
			notice($user, 'Permission Denied');
			return;
		}

		if($msg =~ /^help/i) {
			my (undef, @args) = split(/ /, $msg); #discards first token 'help'
			sendhelp($user, 'securitybot', @args);
		}

		elsif($msg =~ /^notice (\S*) (.*)/i) {
			ircd::notice($sbnick, $1, $2);
		}

		elsif($msg =~ /^msg (\S*) (.*)/i) {
			ircd::privmsg($sbnick, $1, $2);
		}

		elsif($msg =~ /^raw (.*)/i) {
			if(!adminserv::is_svsop($user, adminserv::S_ROOT() )) {
				notice($user, 'You do not have sufficient rank for this command');
				return;
			}
			ircd::ircsend($1);
		}

		elsif($msg =~ /^kill (\S*) (.*)/i) {
			ircd::irckill($sbnick, $1, $2);
		}

		elsif($msg =~ /^conf/i) {
			notice($user, "Configuration:", list_conf);
		}

		elsif($msg =~ /^set (\S+) (.*)/i) {
			if(!adminserv::is_svsop($user, adminserv::S_ROOT() )) {
				notice($user, 'You do not have sufficient rank for this command');
				return;
			}

			my @p = ($1, $2);
			chomp $p[1];

			if(update_conf($p[0], $p[1])) {
				notice($user, "Configuration: ".$p[0]." = ".$p[1]);
			} else {
				notice($user, "That value is read-only.");
			}
		}

		elsif($msg =~ /^save/i) {
			notice($user, "Saving configuration.");

			saveconf();
		}

		elsif($msg =~ /^rehash/i) {
			notice($user, "Loading configuration.");

			loadconf(1);
		}

		elsif($msg =~ /^tssync/i) {
			ircd::tssync();
		}

		elsif($msg =~ /^svsnick (\S+) (\S+)/i) {
			if(!adminserv::is_svsop($user, adminserv::S_ROOT() )) {
				notice($user, 'You do not have sufficient rank for this command');
				return;
			}
			ircd::svsnick($sbnick, $1, $2);
		}

		elsif($msg =~ /^tor-update/i) {
			notice($user, "Updating Tor server list.");
			update_tor_list();
		}
=cut
		elsif($msg =~ /^ss-update/i) {
			notice($user, "Updating SS definitions.");
			securitybot::ss2tkl::update_ss();
		}
=cut
		elsif($msg =~ /^tkl/i) {
			sb_tkl($user, $msg);
		}
}

sub list_conf() {
	my @k = keys(%conf);
	my @v = values(%conf);
	my @reply;

	for(my $i=0; $i<@k; $i++) {
		push @reply, $k[$i]." = ".$v[$i];
	}
	return @reply;
}

sub noticehandle {
	my ($rnick, $dst, $msg) = @_;

	if($msg =~ /^\x01(\S+)\s?(.*?)\x01?$/) {
		diagmsg( "Got $1 reply from $rnick: $2");
	}
}

sub sb_tkl($$) {
# This function is a hack to fit better our normal services coding style.
# Better fix is to rewrite msghandle in another cleanup patch.
	my ($user, $msg) = @_;
	# We discard first token 'tkl'
	my $cmd;
	(undef, $cmd, $msg) = split(/ /, $msg, 3);
	if(lc($cmd) eq 'list') {
		if($msg) {
			sb_tkl_glob($user, $msg);
		}
		else {
			sb_tkl_list($user);
		}
	}
	elsif(lc($cmd) eq 'del') {
		unless($msg) {
			notice($user, "You have to specify at least one parameter");
		}
		sb_tkl_glob_delete($user, $msg);
	}
}

sub sb_tkl_list($) {
	my ($user) = @_;
	my @reply;
	$get_all_tklban->execute();
	while(my ($type, $ident, $host, $setter, $expire, $time, $reason) = $get_all_tklban->fetchrow_array()) {
		if($type eq 'Q') {
			#push @reply, "$type $host $setter";
			next;
		}
		else {
			push @reply, "$type $ident\@$host $setter";
		}
		$time = gmtime2($time); $expire = time_rel($expire - time()) if $expire;
		push @reply, "  set: $time; ".($expire ? "expires in: $expire" : "Will not expire");
		push @reply, "  reason: $reason";
	}
	$get_all_tklban->finish();
	push @reply, "No results" unless @reply;

	notice($user, @reply);
}

sub sb_tkl_glob($$) {
	my ($user, $cmdline) = @_;

	my $sql_expr = "SELECT type, ident, host, setter, expire, time, reason FROM tklban ";

	my ($filters, $parms) = split(/ /, $cmdline, 2);
	my @filters = split(//, $filters);
	unless($filters[0] eq '+' or $filters[0] eq '-') {
		notice($user, "Invalid Syntax: First parameter must be a set of filters preceded by a + or -");
		return;
	}
	my @args = misc::parse_quoted($parms);

	my ($success, $expr) = make_tkl_query(\@filters, \@args);
	unless ($success) {
		notice($user, "Error: $expr");
		return;
	}
	$sql_expr .= $expr;

	my @reply;
	my $get_glob_tklban = $dbh->prepare($sql_expr);
	$get_glob_tklban->execute();
	while(my ($type, $ident, $host, $setter, $expire, $time, $reason) = $get_glob_tklban->fetchrow_array()) {
		if($type eq 'Q') {
			#push @reply, "$type $host $setter";
			next;
		}
		else {
			push @reply, "$type $ident\@$host $setter";
		}
		$time = gmtime2($time); $expire = time_rel($expire - time()) if $expire;
		push @reply, "  set: $time; ".($expire ? "expires in: $expire" : "Will not expire");
		push @reply, "  reason: $reason";
	}
	$get_glob_tklban->finish();

	push @reply, "No results" unless @reply;
	notice($user, @reply);
}

sub sb_tkl_glob_delete($$) {
	my ($user, $cmdline) = @_;

	my $sql_expr = "SELECT type, ident, host FROM tklban ";

	my ($filters, $parms) = split(/ /, $cmdline, 2);
	my @filters = split(//, $filters);
	unless($filters[0] eq '+' or $filters[0] eq '-') {
		notice($user, "Invalid Syntax: First parameter must be a set of filters preceded by a + or -");
		return;
	}
	my @args = misc::parse_quoted($parms);

	my ($success, $expr) = make_tkl_query(\@filters, \@args);
	unless ($success) {
		notice($user, "Error: $expr");
		return;
	}

	$sql_expr .= $expr;

	my $src = get_user_nick($user);
	my $get_glob_tklban = $dbh->prepare($sql_expr);
	$get_glob_tklban->execute();
	while(my ($type, $ident, $host) = $get_glob_tklban->fetchrow_array()) {
		if($type eq 'G') {
			ircd::unkline($src, $ident, $host);
		}
		elsif($type eq 'Z') {
			ircd::unzline($src, $host);
		}
	}
	$get_glob_tklban->finish();

}

sub make_tkl_query($$) {
	my ($parm1, $parm2) = @_;
	my @filters = @$parm1; my @args = @$parm2;

	my ($sign, $sql_expr, $sortby, $where, $and);
	while(my $filter = shift @filters) {
		my $condition;
		if ($filter eq '+') {
			$sign = +1;
			next;
		}
		elsif($filter eq '-') {
			$sign = 0;
			next;
		}

		my $parm = shift @args;
		unless (defined($parm)) {
			return (0, "Not enough arguments for filters.");
		}
		if($filter eq 'm') {
			my ($mident, $mhost) = parse_hostmask($parm);
			$mident = glob2sql($dbh->quote($mident)) if $mident;
			$mhost = glob2sql($dbh->quote($mhost)) if $mhost;
			
			$condition = ($mident ? ($sign ? '' : '!').
				"(ident LIKE $mident) " : '').
				($mhost ? ($sign ? '' : '!').
				"(host LIKE $mhost) " : '');
		}
		elsif($filter eq 'r') {
			my $reason = $dbh->quote($parm);
			$reason = glob2sql($reason);
			$condition = ($sign ? '' : '!')."(reason LIKE $reason) ";
			
		}
		elsif($filter eq 's') {
			my $setter = $dbh->quote($parm);
			$setter = glob2sql($setter);
			$condition = ($sign ? '' : '!')."(setter LIKE $setter) ";
			
		}
		if($filter eq 'M') {
			my ($mident, $mhost) = parse_hostmask($parm);
			$mident = $dbh->quote($mident) if $mident;
			$mhost = $dbh->quote($mhost) if $mhost;
			$condition = ($mident ? ($sign ? '' : '!').
				"(ident REGEXP $mident) " : '').
				($mhost ? ($sign ? '' : '!').
				"(host REGEXP $mhost) " : '');
		}
		elsif($filter eq 'R') {
			my $reason = $dbh->quote($parm);
			$condition = ($sign ? '' : '!')."(reason REGEXP $reason) ";
			
		}
		elsif($filter eq 'S') {
			my $setter = $dbh->quote($parm);
			$condition = ($sign ? '' : '!')."(setter REGEXP $setter) ";
			
		}
		elsif(lc $filter eq 'o') {
			$parm = lc $parm;
			next unless ($parm =~ /(type|ident|host|setter|expire|reason|time)/);
			if ($sortby) {
				$sortby .= ', ';
			} else {
				$sortby = 'ORDER BY ';
			}
			$sortby .= $parm.($sign ? ' ASC' : ' DESC');
			next;
		}
		if (!$where) {
			$sql_expr .= 'WHERE ';
			$where = 1;
		}
		if ($and) {
			$sql_expr .= 'AND ';
		} else {
			$and = 1;
		}
		$sql_expr .= $condition if $condition;
	}
	if (scalar(@args)) {
		return (0, "Too many arguments for filters.");
	}
	return (1, $sql_expr.((defined $sortby and $sortby ne '') ? $sortby : 'ORDER BY type, time, host'));
}

sub get_tkl_type_name($) {
	my %tkltype = (
		G => 'G:line',
		Z => 'GZ:line',
		s => 'Shun',
		Q => 'Q:line',
	);
	return $tkltype{$_[0]};
};

sub get_filter_action_name($) {
	my %filteraction = (
		Z => 'GZ:line',
		S => 'tempshun',
		s => 'shun',
		g => 'G:line',
		z => 'Z:line',
		k => 'K:line',
		K => 'Kill',
		b => 'Block',
		d => 'DCC Block',
		v => 'Virus Chan',
		w => 'Warn',
		#t => 'Test', # Should never show up, and not implemented in 3.2.4 yet.
	);
	return $filteraction{$_[0]};
};

sub handle_tkl($$@) {
	my ($type, $sign, @parms) = @_;
	return unless defined ($dbh);
	if ($type eq 'G' or $type eq 'Z' or $type eq 's' or $type eq 'Q') {
		if ($sign == +1) {
			my ($ident, $host, $setter, $expire, $time, $reason) = @parms;
			$add_tklban->execute($type, $ident, $host, $setter, $expire, $time, $reason);
			$add_tklban->finish();
			diagmsg( get_tkl_type_name($type)." added for $ident\@$host ".
				"from ($setter on ".gmtime2($time).
				($expire ? ' to expire at '.gmtime2($expire) : ' does not expire').": $reason)")
					if initial_synced() and $type ne 'Q';
		}
		elsif($sign == -1) {
			my ($ident, $host, $setter) = @parms;

			if ($type ne 'Q' and initial_synced()) {
				$get_tklban->execute($type, $ident, $host);
				my (undef, $expire, $time, $reason) = $get_tklban->fetchrow_array;
				$get_tklban->finish();

				diagmsg( "$setter removed ".get_tkl_type_name($type)." $ident\@$host ".
					"set at ".gmtime2($time)." - reason: $reason");
			}

			$del_tklban->execute($type, $ident, $host);
			$del_tklban->finish();
		}
	}
	elsif($type eq 'F') {
		if($sign == +1) {
			my ($target, $action, $setter, $expire, $time, $bantime, $reason, $mask) = @parms;
			$add_spamfilter->execute($target, $action, $setter, $expire, $time, $bantime, $reason, $mask);
			$add_spamfilter->finish();
			diagmsg( "Spamfilter added: '$mask' [target: $target] [action: ".
				get_filter_action_name($action)."] [reason: $reason] on ".gmtime2($time)."from ($setter)")
					if initial_synced();
		}
		elsif($sign == -1) {
			# TKL - F u Z tabris!northman@tabris.netadmin.SCnet.ops 0 0 :do_not!use@mask
			my ($target, $action, $setter, $mask) = @parms;
			if(initial_synced()) {
				$get_spamfilter->execute($target, $action, $mask);
				my ($time, $reason) = $get_spamfilter->fetchrow_array;
				$get_spamfilter->finish();
				$reason =~ tr/_/ /;
				diagmsg( "$setter removed Spamfilter (action: ".get_filter_action_name($action).
					", targets: $target) (reason: $reason) '$mask' set at: ".gmtime2($time));
			}
			$del_spamfilter->execute($target, $action, $mask);
			$del_spamfilter->finish();
		}
	}
}

sub saveconf() {
	writeHash(\%conf, "config/securitybot/sb.conf");
}

sub loadconf($) {
	my ($update) = @_;
	
	%conf = readHash("config/securitybot/sb.conf");
}

sub update_conf($$) {
	my ($k, $v) = @_;

	return 0 if($k eq 'EnableTor');

	$conf{$k} = $v;
	return 1;
}

sub expire_tkl() {
	$get_expired_tklban->execute();
	while (my ($type, $ident, $host, $setter, $expire, $time, $reason) = $get_expired_tklban->fetchrow_array()) {
		if ($type eq 'G' or $type eq 'Z' or $type eq 's') {
			diagmsg( "Expiring ".get_tkl_type_name($type)." $ident\@$host ".
				"set by $setter at ".gmtime2($time)." - reason: $reason");
			#$del_tklban->execute($type, $ident, $host);
			#$del_tklban->finish();
			}
	}
	$get_expired_tklban->finish();

	$del_expired_tklban->execute();
	$del_expired_tklban->finish();
}

sub expire_tkl_timed {
	my ($time) = @_;
	$time = 10 unless $time;

	add_timer('10', $time, __PACKAGE__, "securitybot::expire_tkl_timed");

	expire_tkl();
}

sub diagmsg(@) {
	ircd::privmsg($sbnick, main_conf_diag, @_);
	write_log('diag', '<'.main_conf_local.'>', @_);
}

sub end { }
sub unload { saveconf(); }

1;
