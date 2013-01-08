#!/usr/bin/perl

use strict;
use XML::Twig;
use DBI;

BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename;
	my %constants = (
		CWD => getcwd(),
		PREFIX => abs_path(dirname(abs_path($0)).'/..'),
	);
	require constant; import constant(\%constants);
}
chdir PREFIX;
use lib PREFIX;

use SrSv::Conf 'sql';

my $db = 1;

my ($dbh);
my (
	$is_chan_reg, $regchan, $add_topic, $create_acc,

	$is_nick_reg, $regnick, $create_alias
);
my ($time);

if($db) {
	eval {
		$dbh = DBI->connect("DBI:mysql:".$sql_conf{'mysql-db'}, $sql_conf{'mysql-user'}, $sql_conf{'mysql-pass'},
			{  AutoCommit => 1, RaiseError => 1 });
	};
	if($@) {
		print "FATAL: Can't connect to database:\n$@\n";
		print "You must edit config/sql.conf and create a corresponding\nMySQL user and database!\n\n";
		exit;
	}

	$is_chan_reg = $dbh->prepare("SELECT 1 FROM chanreg WHERE chan=?");
	$regchan = $dbh->prepare("INSERT IGNORE INTO chanreg (chan, descrip, founderid, regd, last, topicer, topicd)
		SELECT ?, ?, nickreg.id, ?, ?, ?, ? FROM nickalias
		JOIN nickreg ON (nickalias.nrid=nickreg.id)
		WHERE nickalias.alias=?");

	$add_topic = $dbh->prepare("INSERT INTO chantext SET chan=?, type=1, data=?");
	$create_acc = $dbh->prepare("INSERT INTO chanacc (chan,nrid,level)
		SELECT ?, nickreg.id, ? FROM nickalias
		JOIN nickreg ON (nickreg.id=nickalias.nrid)
		WHERE alias=?");

	$is_nick_reg = $dbh->prepare("SELECT 1 FROM nickalias WHERE alias=?");
	$regnick = $dbh->prepare("INSERT INTO nickreg
		SET nick=?, pass=?, email=?, regd=?, last=?, flags=1, ident='unknown', vhost='unknown', gecos=''");
	$create_alias = $dbh->prepare("INSERT INTO nickalias (nrid, alias, protect, last)
		SELECT id, ?, 1, 0 FROM nickreg WHERE nick=?");

	$time = time();
}

my %nickids;
my %ignorenicks;

open ((my $FBN), '>', "nicks.forbid");
open ((my $FBC), '>', "chans.forbid");

my $crap;
{
	local $/;
	$crap = <>;
}

$crap =~ s/\%/%%/g;
$crap =~ s/&#/%/g;

my $twig=XML::Twig->new(
	twig_handlers =>
		{ nickgroupinfo => \&insert_nick,
		  channelinfo => \&insert_chan
		},
	keep_encoding => 1
);
$twig->parse($crap);
$twig->purge;

sub insert_nick {
	my ($t, $section) = @_;

	my $id = $section->first_child_text('id');
	print "ID: $id\n";

	my $root;
	my $nickst = $section->first_child('nicks');
	my @nickts = $nickst->children('array-element');
	my @aliases;
	foreach my $nt (@nickts) {
		my $nick = $nt->text;
		print "Alias: $nick\n";
		
		if($db) {
			$is_nick_reg->execute($nick);
			if($is_nick_reg->fetchrow_array) {
				print "Already registered!\n\n";
				$ignorenicks{$id} = 1;
				return;
			}
		}

		push @aliases, $nick;
	}
	my $root = @aliases[0];

	$nickids{$id} = $root;

	my $pass = $section->first_child_text('pass');

	if($pass eq '') {
		print "Forbidden!\n\n";
		print $FBN "$root\n";
		return;
	}

	print "Pass: $pass\n";

	my $email = $section->first_child_text('email');
	print "Email: $email\n";

	if($db) {
		$regnick->execute($root, $pass, $email, $time, $time);

		foreach my $alias (@aliases) {
			$create_alias->execute($alias, $root);
		}
	}

	print "\n";

	$t->purge;
}

sub insert_chan {
	my ($t, $section) = @_;

	my $chan = $section->first_child_text('name');
	print "Chan: $chan\n";

	if($db) {
		$is_chan_reg->execute($chan);
		if($is_chan_reg->fetchrow_array) {
			print "Already registered!\n\n";
			return;
		}
	}

	my $founderid = $section->first_child_text('founder');

	if($founderid == 0) {
		print "Forbidden!\n\n";
		print $FBC "$chan\n";
		return;
	}

	if($ignorenicks{$founderid}) {
		print "Founder nick was already registered!\n\n";
		return;
	}
	
	my $founder = $nickids{$founderid};
	print "Founder: $founder\n";
	die("No founder!") unless $founder;

	my $topic = $section->first_child_text('last_topic');
	$topic =~ s/%(\d+);/chr($1)/eg;
	$topic =~ s/%%/%/g;
	my $topictime = $section->first_child_text('last_topic_time');
	my $topicset = $section->first_child_text('last_topic_setter');
	my $desc = $section->first_child_text('desc');
	my $pass = $section->first_child_text('founderpass');
	my $last = $section->first_child_text('last_used');
	my $regd = $section->first_child_text('time_registered');

	if($db) {
		$regchan->execute($chan, $desc, $regd, $last, $topicset, $topictime, $founder);
		$add_topic->execute($chan, $topic);
		$create_acc->execute($chan, 7, $founder);
	}

	print "\n";

	$t->purge;
}
