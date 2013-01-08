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
package sql;
use strict;

use Time::HiRes qw( time );

use SrSv::MySQL qw( $dbh );
use SrSv::Text::Format qw( columnar );
use SrSv::IRCd::Event qw( addhandler );
use SrSv::Agent;
use SrSv::Conf2Consts qw( main );
use SrSv::User qw( get_user_nick );
use SrSv::User::Notice;

# these are really a layer violation
# but there's not much else way to requeue our events
use SrSv::Process::Worker qw( multi );
use SrSv::IRCd::Event qw( callfuncs );

use SrSv::Process::InParent qw( ev_privmsg );

our %users;

our $sqlnick = 'SQLServ';

agent_connect($sqlnick, 'services', undef, '+pqzBGHS', 'Database Query Agent');
agent_join($sqlnick, main_conf_diag);
ircd::setmode($sqlnick, main_conf_diag, '+o', $sqlnick);

addhandler('PRIVMSG', undef, lc $sqlnick, 'sql::ev_privmsg');
sub ev_privmsg {
	my ($src, $dst, $payload) = @_;
	my $user = { NICK => $src, AGENT => $sqlnick };
	#FIXME: More fine grained permissions needed.
	# SELECT is relatively safe. EXPLAIN is too.
	unless(adminserv::is_svsop($user, adminserv::S_ROOT())) {
		notice($user, "Permission denied"); #FIXME: need $err_deny
		return;
	}
	#irssi's splitlong uses ... for beginning and end of a split payload
	$payload =~ s/(^\.\.\.|\.\.\.$)//g;
	if($payload =~ /^help/) {
		notice($user, "Sorry, no documentation yet.");
	}
	elsif($payload =~ /^(SELECT|SHOW CREATE|SHOW TABLES|UPDATE|INSERT|ALTER|EXPLAIN) ?(.*)$/i) {
		my $cmd = $1;
		my $statement = $2;
		$users{$src}{STMT} = $statement;
		$users{$src}{CMD} = uc $cmd;
	} else {
		$users{$src}{STMT} .= ' '.$payload;
	}
	if ($payload =~ /(\\G|;)$/) {
		if(!multi) {
			ev_loopback($src, $dst, "$users{$src}{CMD} $users{$src}{STMT}");
		} else {
			callfuncs('LOOPBACK', 0, 1, 0,
				[$src, $sqlnick, "$users{$src}{CMD} $users{$src}{STMT}"]);
		}
		delete($users{$src});
	}
}

addhandler('LOOPBACK', undef, lc $sqlnick, 'sql::ev_loopback');
sub ev_loopback {
	my ($src, $dst, $payload) = @_;
	my $user = { NICK => $src, AGENT => $sqlnick };
	if($payload =~ /^SELECT (.*)$/i) {
		my $statement = $1;
		if ($statement =~ /(\\G|;)$/) {
			my $mode = ($1 eq ';' ? 1 : 2);
			SELECT($user, $statement, $mode);
		}
	} elsif($payload =~ /^SHOW (CREATE|TABLES) ?(.*)$/i) {
		my $cmd = $1;
		my $statement = $2;
		if ($statement =~ /(\\G|;)$/) {
			my $mode = ($1 eq ';' ? 1 : 2);
			if(uc($cmd) eq 'CREATE') {
				SHOW_CREATE($user, $statement, $mode);
			}
			elsif(uc($cmd) eq 'TABLES') {
				SHOW_TABLES($user, $statement, $mode);
			}
		}
	} elsif($payload =~ /^UPDATE (.*)$/i) {
		my $statement = $1;
		if ($statement =~ /(\\G|;)$/) {
			UPDATE($user, $statement);
		}
	} elsif($payload =~ /^INSERT (.*)$/i) {
		my $statement = $1;
		if ($statement =~ /(\\G|;)$/) {
			INSERT($user, $statement);
		}
	} elsif($payload =~ /^ALTER (.*)$/i) {
		my $statement = $1;
		if ($statement =~ /(\\G|;)$/) {
			ALTER($user, $statement);
		}
	} elsif($payload =~ /^EXPLAIN (.*)$/i) {
		my $statement = $1;
		if ($statement =~ /(\\G|;)$/) {
			my $mode = ($1 eq ';' ? 1 : 2);
			EXPLAIN($user, $statement, $mode);
		}
	}
}

sub queryMode2($$) {
	my ($inRef, $namesRef) = @_;
	my @out;
	for(my $i = 1; $i <= scalar(@$inRef); $i++) {
		my @rowIn = @{$inRef->[$i-1]};
		my @rowTmp;
		push @out, "*************************** $i. row ***************************";
		for(my $j = 0; $j < scalar(@rowIn); $j++) {
			push @rowTmp, [$namesRef->[$j].':', $rowIn[$j]];
		}
		push @out, columnar( { JUSTIFIED => 1, NOHIGHLIGHT => 1 }, @rowTmp );
	}
	return @out;
}

sub UPDATE {
	my ($user, $statement) = @_;
	notice($user, "Unsupported command");
}
sub ALTER {
	my ($user, $statement) = @_;
	notice($user, "Unsupported command");
}
sub EXPLAIN {
	my ($user, $statement, $mode) = @_;
	readonlyQuery($user, 'EXPLAIN', $statement, $mode);
}
sub INSERT {
	my ($user, $statement) = @_;
	notice($user, "Unsupported command");
}

sub SELECT {
	my ($user, $statement, $mode) = @_;
	readonlyQuery($user, 'SELECT', $statement, $mode);
}

sub readonlyQuery {
	my ($user, $cmd, $statement, $mode) = @_;
	my ($arrayRef, $namesRef);
	$statement =~ s/(;|\\G)$//;
	my ($startTime, $endTime, $error);
	eval {
		local $SIG{__WARN__} = sub { $error = \@_ };
		my $sth = $dbh->prepare("$cmd $statement");
		$startTime = time();
		my $ret = $sth->execute();
		if(defined($ret)) {
			$namesRef = $sth->FETCH('NAME');
			$arrayRef = $sth->fetchall_arrayref();
			$endTime = time();
		}
	};
	if($@) {
		#ircd::debug("AIEEEEE! $@");
		notice($user, "AIEEEEE!", "$cmd $statement", $@, '--');
	} elsif(!defined($arrayRef)) {
		notice($user, 'Error:', @$error, '--');
	} elsif(scalar(@$arrayRef)) {
		my @out;
		if($mode == 2) {
			@out = queryMode2($arrayRef, $namesRef);
		} else {
			@out = columnar( { BORDER => 1, NOHIGHLIGHT => 1 }, $namesRef, @$arrayRef );
		}
		my $elapsed = $endTime-$startTime;
		$elapsed = sprintf('%.2f sec%s', $elapsed, $elapsed == 1 ? '' : 's');
		notice($user, @out, scalar(@$arrayRef).' rows in set ('.$elapsed.')');
	} else {
		my $elapsed = $endTime-$startTime;
		$elapsed = sprintf('%.2f sec%s', $elapsed, $elapsed == 1 ? '' : 's');
		notice($user, "Empty result. ($elapsed)");
	}
}

sub SHOW_CREATE {
	my ($user, $statement, $mode) = @_;
	readonlyQuery($user, 'SHOW CREATE', $statement, $mode);
}

sub SHOW_TABLES {
	my ($user, $statement, $mode) = @_;
	readonlyQuery($user, 'SHOW TABLES', $statement, $mode);
}


sub init { }
sub begin { }
sub end { }
sub unload { }

1;
