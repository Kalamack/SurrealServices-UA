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

package SrSv::Unreal::Tokens;

use strict;

use SrSv::Conf::main;
use SrSv::Conf2Consts qw( main );

use Exporter 'import';

#=cut
our $tkn = main_conf_tokens;

our %tkn;
#=cut
BEGIN {
# TODO: Turn these into constants.
my %unrealTokens = (
	PRIVMSG 	=> ['PRIVMSG',	'!'],
	WHOIS 		=> ['WHOIS',	'#'],
	WHOWAS		=> ['WHOWAS',	'$'],
	USER		=> ['USER',	'%'],
	NICK		=> ['NICK',	'&'],
	SERVER		=> ['SERVER',	"\'"],
	LIST		=> ['LIST',	'('],
	TOPIC		=> ['TOPIC',	')'],
	INVITE		=> ['INVITE',	'*'],
	VERSION		=> ['VERSION',	'+'],
	QUIT		=> ['QUIT', 	','],
	SQUIT		=> ['SQUIT',	'-'],
	KILL		=> ['KILL',	'.'],
	INFO		=> ['INFO',	'/'],
	LINKS		=> ['LINKS',	'0'],
	STATS		=> ['STATS',	'2'],
	USERS		=> ['USERS',	'3'],
	ERROR		=> ['ERROR',	'5'],
	AWAY		=> ['AWAY',	'6'],
	CONNECT		=> ['CONNECT',	'7'],
	PING		=> ['PING',	'8'],
	PONG 		=> ['PONG',	'9'],
	OPER		=> ['OPER',	';'],
	PASS		=> ['PASS',	'<'],
	WALLOPS		=> ['WALLOPS',	'='],
	GLOBOPS		=> ['GLOBOPS',	']'],
	TIME		=> ['TIME',	'>'],
	NAMES		=> ['NAMES',	'?'],
	SJOIN		=> ['SJOIN',	'~'],
	NOTICE 		=> ['NOTICE',	'B'],
	JOIN		=> ['JOIN',	'C'],
	PART		=> ['PART',	'D'],
	MODE		=> ['MODE',	'G'],
	KICK		=> ['KICK',	'H'],
	USERHOST	=> ['USERHOST',	'J'],
	SQLINE		=> ['SQLINE',	'c'],
	UNSQLINE	=> ['UNSQLINE',	'd'],
	SVSNICK		=> ['SVSNICK',	'e'],
	SVSNOOP		=> ['SVSNOOP',	'f'],
	SVSKILL		=> ['SVSKILL',	'h'],
	SVSMODE		=> ['SVSMODE',	'n'],
	SVS2MODE	=> ['SVS2MODE',	'v'],
	CHGHOST		=> ['CHGHOST', 	'AL'],
	CHGIDENT	=> ['CHGIDENT',	'AZ'],
	NETINFO		=> ['NETINFO',	'AO'],
	TSCTL		=> ['TSCTL',	'AW'],
	SWHOIS		=> ['SWHOIS',	'BA'],
	SVSO		=> ['SVSO',	'BB'],
	# One may note... that although there is a TKL Token
	# it does not appear to always be used.
	# Maybe b/c 2 vs 3 chars, nobody cares.
	TKL		=> ['TKL',	'BD'],
	SHUN		=> ['SHUN',	'BL'],
	SVSJOIN		=> ['SVSJOIN',	'BX'],
	SVSPART		=> ['SVSPART',	'BT'],
	SVSSILENCE	=> ['SVSSILENCE','Bs'],
	SVSWATCH	=> ['SVSWATCH',	'Bw'],
	SVSSNO		=> ['SVSSNO',	'BV'],
	SENDSNO		=> ['SENDSNO',	'Ss'],

	EOS		=> ['EOS',	'ES'],
	ENDBURST => ['ENDBURST'],
	UMODE2		=> ['UMODE2',	"\|"],

	REHASH		=> ['REHASH',	'O'],

	SVSNOLAG	=> ['SVSNOLAG', 'sl'],
	SVS2NOLAG	=> ['SVS2NOLAG', 'SL'],
);

	%tkn = %unrealTokens;
	my %msgs; map { $msgs{"MSG_$_"} = $unrealTokens{$_}->[0] } keys(%unrealTokens);
	my %toks;
	if(main_conf_tokens) {
		map { $toks{"TOK_$_"} = $unrealTokens{$_}->[1] } keys(%unrealTokens);
	} else {
		map { $toks{"TOK_$_"} = $unrealTokens{$_}->[0] } keys(%unrealTokens);
	}
	require constant;
	import constant \%toks;
	import constant \%msgs;

	our @EXPORT_OK = (
		keys(%toks),
		keys(%msgs),
		qw( %tkn $tkn )
	);
	our %EXPORT_TAGS = (
		tokens => [keys(%toks)],
		messages => [keys(%msgs)],
	);
}

1;
