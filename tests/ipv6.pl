#!/usr/bin/perl

use strict;
use warnings;
use MIME::Base64 qw( decode_base64 encode_base64 );
use Socket;
use Socket6;

BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename qw( dirname );
	use constant { PREFIX => abs_path(dirname(abs_path($0)).'/../') };
}
use lib PREFIX;

use SrSv::Conf::main;
use SrSv::IPv6;

my $IPstring = 'AAAAAAAAAAAAAAAAAAAAAQ==';
my $IPstring2 = 'CgECgw==';
my $IPstring3 = 'IAEZOAJdvu8AAAAAAAEABA';

#print length(decode_base64($IPstring)), "\n", length(decode_base64($IPstring2)), "\n";
#exit;
#print Socket6::inet_ntop(AF_INET6, decode_base64($IPstring)), "\n";
#print Socket6::inet_ntop(AF_INET, decode_base64($IPstring2)), "\n";
print Socket6::inet_ntop(AF_INET6, decode_base64($IPstring3)), "\n";
print get_ipv6_net(Socket6::inet_ntop(AF_INET6, decode_base64($IPstring3))), "\n";
