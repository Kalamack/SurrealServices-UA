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
package services;
use strict;
use Data::Dumper;
use SrSv::Conf::services;

use SrSv::MySQL qw($dbh);
use SrSv::Conf qw(main services sql);
use SrSv::Conf2Consts qw(main services sql);
use SrSv::Timer qw(add_timer);
use SrSv::Agent;
use SrSv::IRCd::Event qw(addhandler);
use SrSv::Log;
use SrSv::User qw( :flood __flood_expire );

use modules::serviceslibs::adminserv;
use modules::serviceslibs::nickserv;
use modules::serviceslibs::chanserv;
use modules::serviceslibs::operserv;
use modules::serviceslibs::botserv;
use modules::serviceslibs::memoserv;
use modules::serviceslibs::hostserv;
use modules::nullserv;
*conf = \%services_conf; # only used in some help docs

our @agents = (
	[$nickserv::nsnick_default, '+opqzBHS', 'Nick Registration Agent'],
	[$chanserv::csnick_default, '+pqzBS', 'Channel Registration Agent'],
	[$operserv::osnick_default, '+opqzBHS', 'Operator Services Agent'],
	[$memoserv::msnick_default, '+pqzBS', 'Memo Exchange Agent'],
	[$botserv::bsnick_default, '+pqzBS', 'Channel Bot Control Agent'],
	[$adminserv::asnick_default, '+pqzBS', 'Services\' Administration Agent'],
	[$hostserv::hsnick_default, '+pqzBS', 'vHost Agent']
);
if(services_conf_nickserv) {
	push @agents, [services_conf_nickserv, '+opqzBHS', 'Nick Registration Agent'];
	$nickserv::nsnick = services_conf_nickserv;
}
if(services_conf_chanserv) {
	push @agents, [services_conf_chanserv, '+pqzBS', 'Channel Registration Agent'];
	$chanserv::csnick = services_conf_chanserv;
}
if(services_conf_operserv) {
	push @agents, [services_conf_operserv, '+opqzBHS', 'Operator Services Agent'];
	$operserv::osnick = services_conf_operserv;
}
if(services_conf_memoserv) {
	push @agents, [services_conf_memoserv, '+pqzBS', 'Memo Exchange Agent'];
	$memoserv::msnick = services_conf_memoserv;
}
if(services_conf_botserv) {
	push @agents, [services_conf_botserv, '+pqzBS', 'Channel Bot Control Agent'];
	$botserv::bsnick = services_conf_botserv;
}
if(services_conf_adminserv) {
	push @agents, [services_conf_adminserv, '+pqzBS', 'Services\' Administration Agent'];
	$adminserv::asnick = services_conf_adminserv;
}
if(services_conf_hostserv) {
	push @agents, [services_conf_hostserv, '+pqzBS', 'vHost Agent'];
	$hostserv::hsnick = services_conf_hostserv;
}

our $qlreason = 'Reserved for Services';

foreach my $a (@agents) {
	agent_connect($a->[0], 'services', undef, $a->[1], $a->[2]);
	ircd::sqline($a->[0], $qlreason);
	agent_join($a->[0], main_conf_diag);
	my $rsUser = { NICK => $main::rsnick, ID => 1 };
	my $agent = { NICK => $a->[0], ID => 2 };
	ircd::setmode($agent, main_conf_diag, '+o', $agent);
}

addhandler('ENDBURST', undef, undef, 'services::ev_connect');
sub ev_connect {
	botserv::eos();
	nickserv::cleanup_users();
	nickserv::fix_vhosts();
	chanserv::eos();
	operserv::expire();
}

addhandler('ENDBURST', undef, undef, 'services::eos');
sub eos {
	chanserv::eos($_[0]);
}

addhandler('KILL', undef, undef, 'nickserv::killhandle');

addhandler('NICKCONN', undef, undef, 'services::ev_nickconn');
sub ev_nickconn {
    nickserv::nick_create(@_[0,2..4,8,5..7,9,10,11]);
}

# NickServ
addhandler('NICKCHANGE', undef, undef, 'nickserv::nick_change');
addhandler('QUIT', undef, undef, 'nickserv::nick_delete');
addhandler('UMODE', undef, undef, 'nickserv::umode');
addhandler('CHGHOST', undef, undef, 'nickserv::chghost');
addhandler('CHGIDENT', undef, undef, 'nickserv::chgident');
addhandler('USERIP', undef, undef, 'nickserv::userip');
addhandler('SQUIT', undef, undef, 'nickserv::squit') if ircd::NOQUIT();
addhandler("OPERUP", undef, undef, 'nickserv::handle_oper');
addhandler('PRIVMSG', undef, undef, 'core::dispatch');
addhandler('PRIVMSG', undef, undef, 'nickserv::dispatch');
addhandler('PRIVMSG', undef, lc services_conf_nickserv, 'nickserv::dispatch') if services_conf_nickserv;

addhandler('BACK', undef, undef, 'nickserv::notify_auths');

# ChanServ
addhandler('JOIN', undef, undef, 'chanserv::user_join');
addhandler('SJOIN', undef, undef, 'chanserv::handle_sjoin');
addhandler('PART', undef, undef, 'chanserv::user_part');
addhandler('KICK', undef, undef, 'chanserv::process_kick');
addhandler('MODE', undef, qr/^#/, 'chanserv::chan_mode');
addhandler('TOPIC', undef, undef, 'chanserv::chan_topic');

addhandler('PRIVMSG', undef, undef, 'chanserv::dispatch');
addhandler('PRIVMSG', undef, lc services_conf_chanserv, 'chanserv::dispatch') if services_conf_chanserv;

# OperServ
addhandler('PRIVMSG', undef, undef, 'operserv::dispatch');
addhandler('PRIVMSG', undef, lc services_conf_operserv, 'operserv::dispatch') if services_conf_operserv;

add_timer('flood_expire', 10, __PACKAGE__, 'services::flood_expire');

sub flood_expire(;$) {
	add_timer('flood_expire', 10, __PACKAGE__, 'services::flood_expire');
	__flood_expire();
}

# MemoServ
addhandler('PRIVMSG', undef, undef, 'memoserv::dispatch');
addhandler('PRIVMSG', undef, lc services_conf_memoserv, 'memoserv::dispatch') if services_conf_memoserv;
addhandler('BACK', undef, undef, 'memoserv::notify');

# BotServ
addhandler('PRIVMSG', undef, undef, 'botserv::dispatch');
# botserv takes all PRIVMSG and NOTICEs, so no special dispatch is needed.
addhandler('NOTICE', undef, qr/^#/, 'botserv::chan_msg');

# AdminServ
addhandler('PRIVMSG', undef, undef, 'adminserv::dispatch');
addhandler('PRIVMSG', undef, lc services_conf_adminserv, 'adminserv::dispatch') if services_conf_adminserv;

add_timer('', 30, __PACKAGE__, 'services::maint');
#add_timer('', 20, __PACKAGE__, 'nickserv::cleanup_users');
add_timer('', 60, __PACKAGE__, 'nickserv::expire_silence_timed');

# HostServ
addhandler('PRIVMSG', undef, undef, 'hostserv::dispatch');
addhandler('PRIVMSG', undef, lc services_conf_hostserv, 'hostserv::dispatch') if services_conf_hostserv;

# $nick should be a registered root nick, if applicable
# $src is the nick or nickid that sent the command
sub ulog($$$$;$$) {
	
	my ($service, $level, $text) = splice(@_, 0, 3);
	
	my $hostmask = nickserv::get_hostmask($_[0]);
	# TODO - Record this in the database
	
	wlog($service, $level, "$hostmask - $text");
}

sub maint {
	wlog($main::rsnick, LOG_INFO(), " -- Running maintenance routines.");
	add_timer('', 3600, __PACKAGE__, 'services::maint');

	nickserv::expire();
	chanserv::expire();

	wlog($main::rsnick, LOG_INFO(), " -- Maintenance routines complete.");
}

sub init {
	return if main::COMPILE_ONLY();
	my $tmpdbh = DBI->connect("DBI:mysql:".sql_conf_mysql_db, sql_conf_mysql_user, sql_conf_mysql_pass, {  AutoCommit => 1, RaiseError => 1 });

	$tmpdbh->do("TRUNCATE TABLE chanuser");
	$tmpdbh->do("TRUNCATE TABLE nickchg");
	$tmpdbh->do("TRUNCATE TABLE chan");
	$tmpdbh->do("TRUNCATE TABLE chanban");
	$tmpdbh->do("UPDATE user SET online=0, quittime=".time());

	$tmpdbh->disconnect;
}

sub begin {
	nickserv::init();
	chanserv::init();
	operserv::init();
	botserv::init();
	adminserv::init();
	memoserv::init();
	hostserv::init();
}

sub end {
	$dbh->disconnect;
}

sub unload { }

1;
