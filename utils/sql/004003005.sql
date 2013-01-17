ALTER TABLE  `chanreg` DROP `bantime`;
ALTER TABLE `chanreg` ADD  `bantime` int(11) UNSIGNED default 0;

DROP TABLE IF EXISTS `tmpban`;
CREATE TABLE IF NOT EXISTS `tmpban` (
  `channel` varchar(32) NOT NULL,
  `banmask` varchar(110) NOT NULL,
  `expiry` bigint(20) unsigned NOT NULL,
  `timeset` bigint(20) unsigned NOT NULL,
  UNIQUE KEY `banmask` (`channel`, `banmask`),
  KEY `expiry` (`expiry`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

REPLACE INTO `srsv_schema` (`ver`) VALUES (4003005);
