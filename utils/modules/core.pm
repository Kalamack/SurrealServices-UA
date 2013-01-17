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
package core;
use strict;

#use SrSv::Conf 'main';
use SrSv::Conf2Consts 'main';
use SrSv::RunLevel 'main_shutdown';
use SrSv::IRCd::Event 'addhandler';
use SrSv::IRCd::IO 'ircsend';
use SrSv::Timer 'add_timer';
use SrSv::Time 'time_rel_long_all';
use SrSv::Agent;
use SrSv::Process::Init; #FIXME - only needed for ccode
use SrSv::User::Notice;
use SrSv::Help;

my $startTime = time();

our %ccode; #FIXME - Split out
proc_init {
	open ((my $COUNTRY), main::PREFIX()."/data/country-codes.txt");
	while(my $x = <$COUNTRY>) {
		chomp $x;
		my($code, $country) = split(/   /, $x);
		$ccode{uc $code} = $country;
	}
	close $COUNTRY;
};

our $rsnick = 'ServServ';

addhandler('STATS', undef, undef, 'core::stats');
sub stats($$) {
	my ($src, $token) = @_;
	if($token eq 'u') {
		ircsend('242 '.$src.' :Server up '.time_rel_long_all($startTime),
			'219 '.$src.' u :End of /STATS report')
	}
}

addhandler('PING', undef, undef, 'ircd::pong', 1);

sub pingtimer($) {
	ircd::ping();
	add_timer('perlserv__pingtimer', 60, __PACKAGE__, 
			"core::pingtimer");
}

agent_connect($rsnick, 'service', undef, '+ABHSNaopqz', 'Services Control Agent');
agent_join($rsnick, main_conf_diag);
ircd::setmode($rsnick, main_conf_diag, '+o', $rsnick);

addhandler('SEOS', undef, undef, 'core::ev_connect', 1);

sub ev_connect {
	add_timer('perlserv__pingtimer', 60, __PACKAGE__,
			"core::pingtimer");
}

addhandler('PRIVMSG', undef, 'servserv', 'core::dispatch', 1);

sub dispatch {
	my ($src, $dst, $msg) = @_;
	my $user = { NICK => $src, AGENT => $rsnick };
	if(!adminserv::is_ircop($user)) {
		notice($user, 'Access Denied');
		ircd::globops($rsnick, "\002$src\002 failed access to $rsnick $msg");
		return;
	}
	if($msg =~ /^lsmod/i) {
		notice($user, main_conf_load);
	}

	if($msg =~ /^shutdown/i) {
		if(!adminserv::is_svsop($user, adminserv::S_ADMIN() )) {
			notice($user, 'You do not have sufficient rank for this command');
			return;
		}
		
		main_shutdown;
	}
	if($msg =~ /^raw/i) {
		if(!adminserv::is_svsop($user, adminserv::S_ROOT() )) {
			notice($user, 'You do not have sufficient rank for this command');
			return;
		}
		my $cmd = $msg;
		$cmd =~ s/raw\s+//i;
		ircsend($cmd);
	}
	if($msg =~ /^help$/) {
		sendhelp($user, lc 'core');
		return;
	}
	if(main::DEBUG and $msg =~ /^eval\s+(.*)/) {
		my $out = eval($1);
		notice($user, split(/\n/, $out.$@));
	}
}

sub init { }
sub begin { }
sub end { }
sub unload { }

1;
