ALTER TABLE `user` DROP COLUMN guest;

REPLACE INTO `srsv_schema` (`ver`) VALUES (4003003);
