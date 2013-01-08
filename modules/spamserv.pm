package spamserv;

use strict;
use Storable;

use SrSv::MySQL '$dbh';
use SrSv::Timer qw(add_timer);
use SrSv::IRCd::Event qw( addhandler );
use SrSv::Agent;
use SrSv::Conf2Consts qw( main services );
use SrSv::Shared qw($fakehost %conf $idlelength);
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );
use SrSv::SimpleHash qw(readHash writeHash);

my $ssnick = 'SpamServ';
my %chanlist;

use SrSv::Process::InParent qw(list_conf loadconf loadchans saveconf savechans);

# should load both spamserv.conf and chans.conf (if available)
loadconf();
loadchans();

addhandler('PRIVMSG', undef, undef, 'spamserv::ss_privmsg');
addhandler('NOTICE', undef, undef, 'spamserv::ss_notice');

agent_connect($ssnick, 'services', undef, '+pqzBGHS', 'Spam Serv');
agent_join($ssnick, main_conf_diag);
ircd::setmode($ssnick, main_conf_diag, '+o', $ssnick);

add_timer('', 5, __PACKAGE__, 'spamserv::ss_newclient');

sub ss_newclient {
	unless (!module::is_loaded('services')) {
		open ((my $SSNICKFILE), main::PREFIX()."/config/spamserv/nicklist.txt");
		my ($nick, $ident, $hostmask) = ('','','');
		my @hexset = ('A'..'F','0'..'9');
		srand;
		rand($.) < 1 and ($nick=$_) while <$SSNICKFILE>;
		chomp $nick;
		close $SSNICKFILE;
		if (!nickserv::is_registered($nick) && !nickserv::is_online($nick)) {
			$ident = "htIRC-".lc(misc::gen_uuid(1,4));
			for (my $i = 1;$i <= 3;$i++) {
				for (my $x = 1;$x <= 8;$x++) {
					$hostmask .= $hexset[rand @hexset];
				}
				$hostmask .= ".";
			}
			$hostmask .= "IP";
			$fakehost = $nick."!".$ident."@".$hostmask;

			agent_connect($nick, $ident, $hostmask,'+pqH', 'WWW user');
			agent_join($nick, main_conf_diag);
			ircd::setmode($ssnick, main_conf_diag, '+h', $nick);

			$idlelength = int(rand($conf{'idlemax'} - $conf{'idlemin'})) + $conf{'idlemin'};

			add_timer($fakehost, $idlelength, __PACKAGE__, 'spamserv::ss_respawn');

			join_chans();
		}
		else {
			add_timer('', 30, __PACKAGE__, 'spamserv::ss_newclient');
		}
	}
}

sub ss_privmsg {
	my ($src, $dst, $msg) = @_;
	if (lc $dst eq lc((split /!/,$fakehost)[0])) {
		ircd::privmsg("SpamServ", main_conf_diag, "Received PRIVMSG: <$src> $msg");
	}
	elsif (lc $dst eq "spamserv") {
		my $user = { NICK => $src, AGENT => $dst };
		unless(adminserv::is_ircop($user)) {
			notice($user, "Permission denied");
			return;
		}
		my @args = split(/\s+/, $msg);
		my $cmd = shift @args;

		if ($cmd =~ /^help$/i) {
			sendhelp($user, 'spamserv', @args);
		}

		elsif ($cmd =~ /^rehash/i) {
			notice($user, "Loading configuration");
			loadconf();
		}

		if ($cmd =~ /^listconf$/i) {
			notice($user, "Configuration:", list_conf);
		}

		elsif ($cmd =~ /^save/i) {
			notice($user, "Saving configuration");
			saveconf();
		}

		elsif ($msg =~ /^set (\S+) (.*)/i) {
			if (!adminserv::is_svsop($user, adminserv::S_ROOT())) {
				notice($user, 'You do not have sufficient rank for this command');
				return;
			}
			if (update_conf($1, $2)) {
				notice($user, "Configuration: $1 = $2");
			} else {
				notice($user, "This appears to be an invalid option");
			}
		}
		elsif ($cmd =~ /^watch$/i) {
			ss_watch($user, shift @args, @args);
		}
	}
}

sub ss_notice {
	my ($src, $dst, $msg) = @_;
	if (lc $dst eq lc((split /!/,$fakehost)[0])) {
		ircd::privmsg("SpamServ", main_conf_diag, "Received NOTICE: -$src- $msg");
	}
	elsif ($dst =~ /^(?:\+|%|@|&|~)?(#.*)/ and exists($chanlist{lc $1})) {
		ircd::privmsg("SpamServ", main_conf_diag, "Received NOTICE: -$src:$dst- $msg");
	}
	
}

sub ss_chnotice {
	my ($nick, $cn, $msgs) = @_;
	$cn =~ s/^[+%@&~]+//;
	return unless exists($chanlist{lc $cn});
	foreach my $message (@$msgs) {
		my $message = "-$nick:$cn- $message";
	}
	ircd::privmsg("SpamServ", main_conf_diag, @$msgs);
}

sub ss_respawn($) {
        my ($fakehost) = @_;
	if (defined($fakehost)) {
		foreach my $cn (keys(%chanlist)) {
			agent_part((split /!/, $fakehost)[0], $cn, '');
		}
		agent_quit((split /!/, $fakehost)[0], '');
		add_timer('', 120, __PACKAGE__, 'spamserv::ss_newclient');
		undef $fakehost;
	}
}

sub ss_watch($$@) {
	my ($user, $cmd, @args) = @_;
	if ($cmd =~ /^add$/i) {
		if (@args == 1) {
			add_channel($user,$args[0]);
		} else {
			notice($user, 'Syntax: WATCH ADD <#chan>');
		}
	}
	if ($cmd =~ /^del(ete)?$/i) {
		if (@args == 1) {
			del_channel($user,$args[0]);
		} else {
			notice($user, 'Syntax: WATCH DEL <#chan>');
		}
	}
	elsif ($cmd =~ /^list$/i) {
		ss_list($user);
	}
}

sub ss_list($) {
	my ($user) = @_;
	notice($user, 'Channels currently being watched');
	foreach my $cn (keys(%chanlist)) {
		notice($user, '  '.$cn);
	}
}

sub add_channel($$) {
	my ($user, $cn) = @_;
	if (!exists($chanlist{lc $cn})) {
		$chanlist{lc $cn} = 1;
		agent_join((split /!/, $fakehost)[0], $cn) if defined $fakehost;
		notice($user, "Channel \002$cn\002 will now be watched");
		savechans();
		return 1;
	} else {
		notice($user, "Channel \002$cn\002 is already being watched");
		return 0;
	}
}

sub del_channel($$) {
	my ($user, $cn) = @_;
	if (exists($chanlist{lc $cn})) {
		delete($chanlist{lc $cn});
		agent_part((split /!/, $fakehost)[0], $cn, '') if defined $fakehost;
		notice($user, "Channel \002$cn\002 will not be watched");
		savechans();
		return 1;
	} else {
		notice($user, "Channel \002$cn\002 is not being watched");
		return 0;
	}
}

sub savechans() {
	my @channels = keys(%chanlist);
	Storable::nstore(\@channels, "config/spamserv/chans.conf");
}

sub saveconf() {
	writeHash(\%conf, "config/spamserv/spamserv.conf");
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

sub loadconf() {
	# doesn't seem to pick up any of the values
	%conf = readHash("config/spamserv/spamserv.conf");
}

sub loadchans() {
	return unless(-f "config/spamserv/chans.conf");
	my @channels = @{Storable::retrieve("config/spamserv/chans.conf")};
	foreach my $cn (@channels) {
		$chanlist{lc $cn} = 1;
	}
}

sub update_conf($$) {
	my ($k,$v) = @_;
	if (exists($conf{$k})) {
		$conf{$k} = $v;
		return 1;
	} else {
		return 0;
	}
}

sub join_chans() {
	foreach my $cn (keys(%chanlist)) {
		agent_join((split /!/, $fakehost)[0], $cn);
	}
}

sub init { }
sub begin { }
sub end { }
sub unload { savechans(); saveconf(); }

1;
