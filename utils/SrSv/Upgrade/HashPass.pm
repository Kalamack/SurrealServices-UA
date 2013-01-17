package SrSv::Upgrade::HashPass;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT = qw(hash_all_passwords) }

use SrSv::Hash::SaltedHash;
use SrSv::Hash::Passwords qw( hash_pass validate_pass is_hashed );
use SrSv::MySQL '$dbh';
use SrSv::Process::Init;
use SrSv::Conf 'main';

my ($get_nicks, $replace_pass);

proc_init {
	$get_nicks = $dbh->prepare("SELECT nick, id, pass FROM nickreg ORDER BY id");
	$replace_pass = $dbh->prepare("UPDATE nickreg SET pass=? WHERE id=?");
};

sub hash_all_passwords() {
	return unless $main_conf{'hashed-passwords'};

	print "Updating passwords...\n";

	$dbh->do("LOCK TABLES nickreg WRITE");

	$get_nicks->execute();
	while (my ($nick, $nrid, $pass) = $get_nicks->fetchrow_array() ) {
		next if is_hashed($pass);
		
		my $hashedPass = hash_pass($pass);

		#print STDOUT "$nick, $nrid, $pass, $hashedPass\n";
		#print STDOUT (validate_pass($hashedPass, $pass) ? "hash is valid" : "hash is not valid" )."\n";
		#print STDOUT " ----------------- \n";
		validate_pass($hashedPass, $pass) or die "Internal error while converting password ($pass, $hashedPass)";

		$replace_pass->execute($hashedPass, $nrid);
	}

	$dbh->do("UNLOCK TABLES");
}

1;
