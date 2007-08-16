-- Use this to wipe a bibliotech database.

-- The advantage of this script over a DROP DATABASE; SOURCE schema.sql
-- is that this set of commands can be run on the main InnoDB database and allowed
-- to replicate to the MyISAM database and the correct thing will happen; whereas
-- with a schema rebuild replication must be off otherwise the MyISAM database
-- gets wiped and rebuilt with InnoDB tables as it faithfully replicates the CREATE
-- TABLE commands.

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE author;
TRUNCATE TABLE bookmark;
TRUNCATE TABLE bookmark_details;
TRUNCATE TABLE citation;
TRUNCATE TABLE citation_author;
TRUNCATE TABLE comment;
TRUNCATE TABLE gang;
TRUNCATE TABLE journal;
TRUNCATE TABLE tag;
TRUNCATE TABLE user;
TRUNCATE TABLE user_bookmark;
TRUNCATE TABLE user_bookmark_comment;
TRUNCATE TABLE user_bookmark_details;
TRUNCATE TABLE user_bookmark_tag;
TRUNCATE TABLE user_gang;
TRUNCATE TABLE user_tag_annotation;
SET FOREIGN_KEY_CHECKS = 1;
