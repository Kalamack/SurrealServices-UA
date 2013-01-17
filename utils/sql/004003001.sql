CREATE TABLE usertags (
	`userid` bigint NOT NULL,
	`tag` char(30) NOT NULL,
	PRIMARY KEY USING HASH (`userid`, `tag`)
) ENGINE=HEAP;

REPLACE INTO `srsv_schema` (`ver`) VALUES (4003001);
