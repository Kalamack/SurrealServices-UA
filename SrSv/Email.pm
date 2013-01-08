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
package SrSv::Email;
use strict;

use SrSv::Conf2Consts qw(main);
use SrSv::IRCd::State qw( %IRCd_capabilities );

use Exporter 'import';
BEGIN { our @EXPORT = qw( send_email validate_email ) }

sub send_email($$$) {
	my ($dst, $subj, $msg) = @_;
	return if main_conf_nomail;

	open ((my $EMAIL), '|-', '/usr/sbin/sendmail', '-t');
	print $EMAIL 'From: '.main_conf_email."\n";
	print $EMAIL 'To: '.$dst."\n";
	print $EMAIL 'Reply-to: '.main_conf_replyto."\n" if main_conf_replyto;
	print $EMAIL 'Subject: '.$subj."\n\n";
	print $EMAIL "This is an automated mailing from the IRC services at " . $IRCd_capabilities{NETWORK} . ".\n\n";
	print $EMAIL $msg;
	print $EMAIL "\n\n" . main_conf_sig . "\n";
	close $EMAIL;
}

sub validate_email($) {
	my ($email) = @_;

	$email =~ /.+\.(\w+)$/;
	my $tld = $1;
	if(
#		$email =~ /^(?:[0-9a-z]+[-._+&])*[0-9a-z]+@(?:[-0-9a-z]+[.])+[a-z]{2,6}$/i and
		$email =~ /^[^@]+@(?:[-0-9a-z]+[.])+[a-z]{2,6}$/i and
		$email !~ /^(?:abuse|postmaster|noc|security|spamtrap)\@/i and
		defined($core::ccode{uc $tld})
	) {
		return 1;
	} else {
		return 0;
	}
}

1;
