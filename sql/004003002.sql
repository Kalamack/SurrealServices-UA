ALTER TABLE `user` MODIFY `ip` bigint unsigned,
	ADD COLUMN `ipv6` char(39) default NULL;

REPLACE INTO `srsv_schema` (`ver`) VALUES (4003002);
