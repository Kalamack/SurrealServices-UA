#0.4.3
alter table user
  modify column id bigint unsigned not null auto_increment,
  drop primary key,
  add primary key using btree (id),
  drop key nick,
  add key nick using hash (nick),
  drop key ip,
  add key using btree (ip);

# Duplicate key given PRIMARY already indexes this column first.
ALTER TABLE `nickalias` DROP KEY `root`;

# Duplicate keys given PRIMARY already indexes this column first.
ALTER TABLE `akick` DROP INDEX `chan`;
ALTER TABLE `silence` DROP KEY `nick`;
ALTER TABLE `nickid` DROP INDEX `id`, ADD KEY `nrid` (`nrid`);
ALTER TABLE `watch` DROP KEY `nick`;

# merged into above 'alter table user'
#ALTER TABLE `user` MODIFY `id` bigint unsigned NOT NULL auto_increment;
DROP TABLE `srsv_schema`;
CREATE table `srsv_schema` (
	`ver` int unsigned NOT NULL,
	`singleton` int unsigned default 0,
	PRIMARY KEY (`singleton`)
) ENGINE=MyISAM;
REPLACE INTO `srsv_schema` (`ver`) VALUES (4003000);
