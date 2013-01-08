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
package hostserv;

use strict;

use SrSv::Text::Format qw(columnar);
use SrSv::Errors;

use SrSv::HostMask qw(parse_mask);

use SrSv::User qw(get_user_nick get_user_id :flood);
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::NickReg::Flags qw(NRF_NOHIGHLIGHT nr_chk_flag_user);
use SrSv::NickReg::User qw(is_identified);
use SrSv::IRCd::State qw($ircline synced initial_synced %IRCd_capabilities);
use SrSv::MySQL '$dbh';
use SrSv::MySQL::Glob;
require SrSv::DB::StubGen;


our $hsnick_default = 'HostServ1';
our $hsnick = $hsnick_default;
our $hsuser = { NICK => $hsnick, ID => ircd::getAgentUuid($hsnick) };
sub init() {
$hsuser = { NICK => $hsnick, ID => ircd::getAgentUuid($hsnick) };
import SrSv::DB::StubGen (
	dbh => $dbh,
	generator => 'services_mysql_stubgen',
);

services_mysql_stubgen(
	[set_vhost => 'INSERT', "REPLACE INTO vhost SELECT id, ?, ?, ?, UNIX_TIMESTAMP() FROM nickreg WHERE nick=?"],
	[get_vhost => 'ROW',  "SELECT vhost.ident, vhost.vhost
		FROM vhost, nickalias
		WHERE nickalias.nrid=vhost.nrid AND nickalias.alias=?"],
	[del_vhost => 'NULL', "DELETE FROM vhost USING vhost, nickreg WHERE nickreg.nick=? AND vhost.nrid=nickreg.id"],
	[get_matching_vhosts => 'ARRAY', "SELECT nickreg.nick, vhost.ident, vhost.vhost, vhost.adder, vhost.time
		FROM vhost JOIN nickreg ON (vhost.nrid=nickreg.id)
		WHERE nickreg.nick LIKE ? AND vhost.ident LIKE ? AND vhost.vhost LIKE ?
		ORDER BY nickreg.nick"],
);
}

sub dispatch($$$) {
	my ($user, $dstUser, $msg) = @_;
	my $src = $user->{NICK};
	$msg =~ s/^\s+//;
	my @args = split(/\s+/, $msg);
	my $cmd = shift @args;
	$user->{AGENT} = $hsuser;
	get_user_id ($user);
	return if flood_check($user);
	return unless (lc $dstUser->{NICK} eq lc $hsnick);
	if(lc $cmd eq 'on') {
		hs_on($user, $src, 0);
	}
	elsif(lc $cmd eq 'off') {
		hs_off($user);
	}
	elsif($cmd =~ /^(add|set(host))?$/i) {
		if (@args == 2) {
			hs_sethost($user, @args);
		}
		else {
			notice($user, 'Syntax: SETHOST <nick> <[ident@]vhost>');
		}
	}
	elsif($cmd =~ /^del(ete)?$/i) {
		if (@args == 1) {
			hs_delhost($user, @args);
		}
		else {
			notice($user, 'Syntax: DELETE <nick>');
		}
	}
	elsif($cmd =~ /^list$/i) {
		if (@args == 1) {
			hs_list($user, @args);
		}
		else {
			notice($user, 'Syntax: LIST <nick!vident@vhost>');
		}
	}	
        elsif($cmd =~ /^help$/i) {
		sendhelp($user, 'hostserv', @args)
        }
	else { notice($user, "Unknown command."); }
}

sub hs_on($$;$) {
	my ($user, $nick, $identify) = @_;
	my $src = get_user_nick($user);
	
	unless(nickserv::is_registered($nick)) {
		notice($user, "Your nick, \002$nick\002, is not registered.");
		return;
	}

	if(!$identify and !is_identified($user, $nick)) {
		notice($user, "You are not identified to \002$nick\002.");
		return;
	}
	if ($IRCd_capabilities{"CHGHOST"} eq "" || $IRCd_capabilities{"CHGIDENT"} eq "" || $IRCd_capabilities{"CLOAKHOST"} eq "" || $IRCd_capabilities{"CLOAK"} eq "") {
		notice ($user, "The IRCd is not properly configured to support vhosts. Please contact your friendly network administrators.");
		notice ($user, "CHGHOST, CHGIDENT, CLOAKHOST and CLOAK need to be enabled for proper vhost support.");
		return;
	}
	my ($vident, $vhost) = get_vhost($nick);
	unless ($vhost) {
		notice($user, "You don't have a vHost.") unless $identify;
		return;
	}
	
	if ($vident) {
		ircd::chgident($hsuser, $user, $vident);
	}
	ircd::chghost($hsuser, $user, $vhost);

	notice($user, "Your vHost has been changed to \002".($vident?"$vident\@":'')."$vhost\002");
}

sub hs_off($) {
	my ($user) = @_;
	my $src = get_user_nick($user);
	if (!$IRCd_capabilities{"CHGHOST"} || !$IRCd_capabilities{"CHGIDENT"} || !$IRCd_capabilities{"CLOAKHOST"} || !$IRCd_capabilities{"CLOAK"}) {
		notice ($user, "The IRCd is not properly configured to support vhosts. Please contact your friendly network administrators.");
		notice ($user, "CHGHOST, CHGIDENT, CLOAKHOST and CLOAK need to be enabled for proper vhost support.");
		return;
	}
	# This requires a hack that is only known to work in UnrealIRCd 3.2.6 and later.
	# And insp!
	ircd::reset_cloakhost($hsuser, $user);

	notice($user, "vHost reset to cloakhost.");
}

sub hs_sethost($$$) {
	my ($user, $target, $vhost) = @_;
	unless(adminserv::is_svsop($user, adminserv::S_OPER())) {
		notice($user, $err_deny);
		return;
	}
	if (!$IRCd_capabilities{"CHGHOST"} || !$IRCd_capabilities{"CHGIDENT"} || !$IRCd_capabilities{"CLOAKHOST"} || !$IRCd_capabilities{"CLOAK"}) {
		notice ($user, "The IRCd is not properly configured to support vhosts. Please contact your friendly network administrators.");
		notice ($user, "CHGHOST, CHGIDENT, CLOAKHOST and CLOAK need to be enabled for proper vhost support.");
		return;
	}
	my $rootnick = nickserv::get_root_nick($target);

	unless ($rootnick) {
		notice($user, "\002$target\002 is not registered.");
		return;
	}

	my $vident = '';
	if($vhost =~ /\@/) {
	    ($vident, $vhost) = split(/\@/, $vhost);
	}
	my $src = get_user_nick($user);
	set_vhost($vident, $vhost, $src, $rootnick);
	
	notice($user, "vHost for \002$target ($rootnick)\002 set to \002".($vident?"$vident\@":'')."$vhost\002");
}

sub hs_delhost($$) {
	my ($user, $target) = @_;
	unless(adminserv::is_svsop($user, adminserv::S_OPER())) {
		notice($user, $err_deny);
		return;
	}
	my $rootnick = nickserv::get_root_nick($target);

	unless ($rootnick) {
		notice($user, "\002$target\002 is not registered.");
		return;
	}

	del_vhost($rootnick);
	
	notice($user, "vHost for \002$target ($rootnick)\002 deleted.");
}

sub hs_list($$) {
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
	foreach my $vhostEnt (get_matching_vhosts($mnick, $mident, $mhost)) {
		my ($rnick, $vident, $vhost) = @$vhostEnt;
		push @data, [$rnick, ($vident?"$vident\@":'').$vhost];
	}

	notice($user, columnar({TITLE => "vHost list matching \002$mask\002:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data));
}


### MISCELLANEA ###

    
    
## IRC EVENTS ##

1;
