ALTER TABLE  `chanreg` ADD  `bantime` BIGINT( 20 ) UNSIGNED NOT NULL;

CREATE TABLE IF NOT EXISTS `tmpban` (
  `channel` varchar(20) NOT NULL,
  `banmask` varchar(20) NOT NULL,
  `expiry` bigint(20) unsigned NOT NULL,
  `timeset` bigint(20) unsigned NOT NULL,
  KEY `banmask` (`banmask`),
  KEY `timeset` (`timeset`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

REPLACE INTO `srsv_schema` (`ver`) VALUES (4003004);
