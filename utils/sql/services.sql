CREATE TABLE `akick` (
  `chan` varchar(32) NOT NULL default '',
  `nick` varchar(30) NOT NULL default '',
  `ident` varchar(10) NOT NULL default '',
  `host` varchar(64) NOT NULL default '',
  `adder` varchar(30) NOT NULL default '',
  `reason` text,
  `time` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`chan`,`nick`,`ident`,`host`)
) ENGINE=MyISAM;


CREATE TABLE `bot` (
  `nick` char(30) NOT NULL default '',
  `ident` char(10) NOT NULL default '',
  `vhost` char(64) NOT NULL default '',
  `gecos` char(50) NOT NULL default '',
  `flags` mediumint NOT NULL default '1',
  PRIMARY KEY  (`nick`)
) ENGINE=MyISAM;

CREATE TABLE `chanacc` (
  `chan` char(32) NOT NULL default '',
  `nrid` int(11) unsigned NOT NULL default '0',
  `level` tinyint(3) NOT NULL default '0',
  `adder` char(30) NOT NULL default '',
  `time` int(10) unsigned NOT NULL default '0',
  `last` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`chan`,`nrid`)
) ENGINE=MyISAM;

CREATE TABLE `chanclose` (
  `chan` char(30) NOT NULL default '',
  `nick` char(30) NOT NULL default '',
  `reason` text NOT NULL default '',
  `time` int(11) unsigned NOT NULL default '0',
  `type` tinyint(3) unsigned NOT NULL default '0',
  PRIMARY KEY (`chan`)
) ENGINE=MyISAM;

CREATE TABLE `chanlvl` (
  `chan` char(32) NOT NULL default '',
  `perm` smallint(5) unsigned NOT NULL default '0',
  `level` tinyint(4) NOT NULL default '0',
  PRIMARY KEY  (`chan`,`perm`)
) ENGINE=MyISAM;

CREATE TABLE `chanperm` (
  `name` char(10) NOT NULL default '',
  `id` smallint(5) unsigned NOT NULL auto_increment,
  `level` tinyint(4) NOT NULL default '0',
  `max` tinyint(3) unsigned NOT NULL default 0,
  PRIMARY KEY  (`name`),
  UNIQUE KEY `id` (`id`)
) ENGINE=MyISAM;

CREATE TABLE `chanreg` (
  `chan` varchar(32) NOT NULL default '',
  `descrip` varchar(255) default NULL,
  `regd` int(11) unsigned NOT NULL default '0',
  `last` int(11) unsigned NOT NULL default '0',
  `topicer` varchar(30) NOT NULL default '',
  `topicd` int(11) unsigned NOT NULL default '0',
  `modelock` varchar(63) binary NOT NULL default '+ntr',
  `founderid` int(11) unsigned NOT NULL default '0',
  `successorid` int(11) unsigned NOT NULL default '0',
  `bot` varchar(30) NOT NULL default '',
  `flags` mediumint(8) unsigned NOT NULL default '0',
  `bantype` tinyint(8) unsigned NOT NULL default '0',
  PRIMARY KEY  (`chan`)
) ENGINE=MyISAM;


CREATE TABLE `ircop` (
  `nick` char(30) NOT NULL default '',
  `level` tinyint(3) unsigned NOT NULL default '0',
  `pass` char(127) binary NOT NULL default '',
  PRIMARY KEY  (`nick`)
) ENGINE=MyISAM;

CREATE TABLE `logonnews` (
  `setter` char(30) NOT NULL default '',
  `type` char(1) NOT NULL default 'u',
  `id` tinyint(3) unsigned NOT NULL default 0,
  `time` int(11) unsigned NOT NULL default '0',
  `expire` int(11) unsigned NOT NULL default '0',
  `msg` text NOT NULL
) ENGINE=MyISAM;

CREATE TABLE `memo` (
  `src` varchar(30) NOT NULL default '',
  `dstid` int(11) unsigned NOT NULL default '0',
  `chan` varchar(32) NOT NULL default '',
  `time` int(11) unsigned NOT NULL default '0',
  `flag` tinyint(3) unsigned NOT NULL default '0',
  `msg` text NOT NULL,
  PRIMARY KEY  (`src`,`dstid`,`chan`,`time`),
  KEY `dst` (`dstid`)
) ENGINE=MyISAM;

CREATE TABLE `ms_ignore` (
  `nrid` int(11) unsigned NOT NULL default '0',
  `ignoreid` int(11) unsigned NOT NULL default '0',
  `time` int(11) unsigned NOT NULL default '0',
  PRIMARY KEY  (`nrid`,`ignoreid`)
) ENGINE=MyISAM;

CREATE TABLE `nickalias` (
  `nrid` int(11) unsigned NOT NULL default '0',
  `alias` char(30) NOT NULL default '',
  `protect` tinyint(4) NOT NULL default '1',
  `last` int(11) unsigned NOT NULL default 0,
  PRIMARY KEY  (`nrid`,`alias`),
  UNIQUE KEY `alias` (`alias`)
) ENGINE=MyISAM;

CREATE TABLE `nickid` (
  `id` int(10) unsigned NOT NULL default '0',
  `nrid` int(11) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id`,`nrid`),
  KEY `nrid` (`nrid`)
) ENGINE=HEAP;

CREATE TABLE `nickreg` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `nick` char(30) NOT NULL default '',
  `pass` char(127) binary NOT NULL default '',
  `email` char(127) NOT NULL default '',
  `regd` int(11) unsigned NOT NULL default '0',
  `last` int(11) unsigned NOT NULL default '0',
  `flags` mediumint(3) unsigned NOT NULL default '1',
  `ident` char(10) NOT NULL default '',
  `vhost` char(64) NOT NULL default '',
  `gecos` char(50) NOT NULL default '',
  `quit` char(127) NOT NULL default '',
  `nearexp` tinyint(3) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `nick` (`nick`)
) ENGINE=MyISAM;

CREATE TABLE `sesexname` (
  `host` varchar(64) NOT NULL default '',
  `serv` tinyint(1) NOT NULL default 0,
  `adder` varchar(3) NOT NULL default '',
  `lim` mediumint(8) unsigned NOT NULL default 0,
  `reason` varchar(255) NOT NULL default '',
  PRIMARY KEY (`host`)
);

CREATE TABLE `sesexip` (
  `ip` int(10) unsigned NOT NULL default 0,
  `mask` tinyint(3) NOT NULL default 0,
  `adder` varchar(3) NOT NULL default '',
  `lim` mediumint(8) unsigned NOT NULL default 0,
  `reason` varchar(255) NOT NULL default '',
  PRIMARY KEY (`ip`)
);

CREATE TABLE `qline` (
  `mask` varchar(30) NOT NULL default '',
  `setter` varchar(30) NOT NULL default '',
  `time` int(11) unsigned NOT NULL default '0',
  `expire` int(11) unsigned NOT NULL default '0',
  `reason` text NOT NULL,
  PRIMARY KEY  (`mask`),
  KEY `time` (`time`),
  KEY `expire` (`expire`)
) ENGINE=MyISAM;

CREATE TABLE `silence` (
  `nrid` int(11) unsigned NOT NULL default '0',
  `mask` char(106) NOT NULL default '',
  `time` int(10) unsigned NOT NULL default '0',
  `expiry` int(10) unsigned NOT NULL default '0',
  `comment` char(100) default NULL,
  PRIMARY KEY  (`nrid`,`mask`)
) ENGINE=MyISAM;


CREATE TABLE `svsop` (
  `nrid` int(11) unsigned NOT NULL default '0',
  `level` tinyint(3) unsigned NOT NULL default '0',
  `adder` char(30) NOT NULL default '',
  PRIMARY KEY  (`nrid`)
) ENGINE=MyISAM;

CREATE TABLE `vhost` (
  `nrid` int(11) unsigned NOT NULL default '0',
  `ident` char(10) NOT NULL default '',
  `vhost` char(64) NOT NULL default '',
  `adder` char(30) NOT NULL default '',
  `time` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`nrid`)
) ENGINE=MyISAM;

CREATE TABLE `watch` (
  `nrid` int(11) unsigned NOT NULL default '0',
  `mask` char(106) NOT NULL default '',
  `time` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`nrid`,`mask`)
) ENGINE=MyISAM;

CREATE TABLE `welcome` (
  `chan` varchar(32) NOT NULL default '',
  `id` tinyint(3) NOT NULL default '0',
  `adder` varchar(30) NOT NULL default '',
  `time` int(10) NOT NULL default '0',
  `msg` text NOT NULL,
  PRIMARY KEY  (`chan`,`id`)
) ENGINE=MyISAM;

CREATE TABLE `nicktext` (
  `nrid` int(11) unsigned NOT NULL default 0,
  `type` tinyint(3) unsigned NOT NULL default 0,
  `id` mediumint(8) unsigned NOT NULL default 0,
  `chan` varchar(32) default NULL,
  `data` text default NULL,
  PRIMARY KEY (`nrid`, `type`, `id`, `chan`)
) ENGINE=MyISAM;

#################################################
# Volatile tables

DROP TABLE IF EXISTS `chan`;
CREATE TABLE `chan` (
  `chan` char(32) NOT NULL default '',
  `modes` char(63) binary NOT NULL default '',
  `seq` mediumint(8) unsigned NOT NULL default '0',
  PRIMARY KEY  (`chan`)
) ENGINE=HEAP;

DROP TABLE IF EXISTS `chanban`;
CREATE TABLE `chanban` (
  `chan` varchar(32) NOT NULL default '',
  `mask` varchar(110) NOT NULL default '',
  `setter` varchar(30) NOT NULL default '',
  `time` int(10) unsigned NOT NULL default '0',
  `type` tinyint(3) unsigned NOT NULL default '0',
  PRIMARY KEY  (`chan`,`mask`,`type`)
) ENGINE=HEAP;

#DROP TABLE IF EXISTS `chantext`;
CREATE TABLE `chantext` (
  `chan` varchar(32) NOT NULL default '',
  `type` tinyint(3) unsigned NOT NULL default 0,
  `key` varchar(32) default NULL,
  `data` text default NULL,
  PRIMARY KEY (`chan`, `type`, `key`)
) ENGINE=MyISAM;

DROP TABLE IF EXISTS `chanuser`;
CREATE TABLE `chanuser` (
  `seq` mediumint(8) unsigned NOT NULL default '0',
  `nickid` int(11) unsigned NOT NULL default '0',
  `chan` char(32) NOT NULL default '',
  `joined` tinyint(3) unsigned NOT NULL default '0',
  `op` tinyint(4) NOT NULL default '0',
  PRIMARY KEY  (`nickid`,`chan`),
  KEY `chan` (`chan`),
  KEY `nickid` (`nickid`)
) ENGINE=HEAP;

DROP TABLE IF EXISTS `nickchg`;
CREATE TABLE `nickchg` (
  `seq` mediumint(8) unsigned NOT NULL default '0',
  `nickid` int(11) unsigned NOT NULL default '0',
  `nick` char(30) NOT NULL default '',
  PRIMARY KEY  (`nick`)
) ENGINE=HEAP;

DROP TABLE IF EXISTS `tklban`;
CREATE TABLE `tklban` (
  `type` char(1) NOT NULL default '',
  `ident` char(10) NOT NULL default '',
  `host` char(64) NOT NULL default '',
  `setter` char(106) NOT NULL default '',
  `expire` int(11) unsigned NOT NULL default 0,
  `time` int(11) unsigned NOT NULL default 0,
  `reason` char(255) NOT NULL default '',
  PRIMARY KEY (`type`, `ident`, `host`)
) ENGINE = HEAP;

DROP TABLE IF EXISTS `spamfilter`;
CREATE TABLE `spamfilter` (
  `target` char(20) NOT NULL default '',
  `action` char(20) NOT NULL default '',
  `setter` char(106) NOT NULL default '',
  `expire` int(11) unsigned NOT NULL default 0,
  `time` int(11) unsigned NOT NULL default 0,
  `bantime` int(11) unsigned NOT NULL default 0,
  `reason` char(255) NOT NULL default '',
  `mask` char(255) NOT NULL default '',
  PRIMARY KEY (`target`, `action`, `mask`)
) ENGINE = HEAP;

# Keep this even though it is volatile; it still contains useful data
CREATE TABLE `user` (
  `id` int(11) unsigned NOT NULL default '0',
  `nick` char(30) NOT NULL default '',
  `time` int(11) unsigned NOT NULL default '0',
  `inval` tinyint(4) NOT NULL default '0',
  `ident` char(10) NOT NULL default '',
  `host` char(64) NOT NULL default '',
  `vhost` char(64) NOT NULL default '',
  `cloakhost` char(64) default NULL,
  `ip` int(8) unsigned NOT NULL default '0',
  `server` char(64) NOT NULL default '',
  `modes` char(30) NOT NULL default '',
  `gecos` char(50) NOT NULL default '',
  `guest` tinyint(1) NOT NULL default '0',
  `online` tinyint(1) unsigned NOT NULL default '0',
  `quittime` int(11) unsigned NOT NULL default '0',
  `flood` tinyint(1) unsigned NOT NULL default '0',
  `flags` mediumint(10) unsigned NOT NULL,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `nick` (`nick`),
  KEY `ip` (`ip`)
) ENGINE=HEAP;

#################################################
# Not used

DROP TABLE IF EXISTS `olduser`;

DROP TABLE IF EXISTS `chanlog`;
#CREATE TABLE `chanlog` (
#    `chan` char(30) NOT NULL default '',
#    `adder` char(30) NOT NULL default '',
#    `time` unsigned int NOT NULL default 0,
#    `email` varchar(100) NOT NULL default ''
#    PRIMARY KEY (`chan`)
#) ENGINE = MyISAM;

#################################################
# Upgrades

# 0.4.2
ALTER TABLE chanperm MODIFY `name` char(16) NOT NULL default '';
UPDATE chanperm SET name='AkickEnforce' WHERE name LIKE 'AkickEn%';
ALTER TABLE `ms_ignore` DROP KEY `nickid`, DROP COLUMN id;
