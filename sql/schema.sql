-- Bibliotech database schema
-- Required server version is 4.1.13-standard or better

-- You will need to start with these commands on first use:
DROP DATABASE bibliotech;
CREATE DATABASE bibliotech;
USE bibliotech;

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `author`
--

DROP TABLE IF EXISTS `author`;
CREATE TABLE `author` (
  `author_id` int(7) unsigned NOT NULL auto_increment,
  `firstname` varchar(60) default NULL,
  `forename` varchar(60) default NULL,
  `initials` varchar(10) default NULL,
  `middlename` varchar(60) default NULL,
  `lastname` varchar(60) default NULL,
  `suffix` varchar(20) default NULL,
  `misc` varchar(255) default NULL,
  `postal_address` varchar(255) default NULL,
  `affiliation` varchar(255) default NULL,
  `email` varchar(255) default NULL,
  `user` int(7) unsigned default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`author_id`),
  KEY `firstname_idx` (`firstname`),
  KEY `forename_idx` (`forename`),
  KEY `lastname_idx` (`lastname`),
  KEY `name_combo_idx` (`lastname`,`forename`,`firstname`),
  KEY `email_idx` (`email`),
  KEY `author_user_fk` (`user`),
  CONSTRAINT `author_user_fk` FOREIGN KEY (`user`) REFERENCES `user` (`user_id`)
  -- SEARCH: FULLTEXT INDEX `name_ft` (`firstname`, `forename`, `lastname`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `article`
--

DROP TABLE IF EXISTS `article`;
CREATE TABLE `article` (
  `article_id` int(7) unsigned NOT NULL auto_increment,
  `hash` varchar(32) NOT NULL default '',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`article_id`),
  KEY `hash_idx` (`hash`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `bookmark`
--

DROP TABLE IF EXISTS `bookmark`;
CREATE TABLE `bookmark` (
  `bookmark_id` int(7) unsigned NOT NULL auto_increment,
  `url` varchar(255) NOT NULL default '',
  `hash` varchar(32) NOT NULL default '',
  `first_user` int(7) unsigned default NULL,
  `citation` int(7) unsigned default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`bookmark_id`),
  UNIQUE KEY `url_idx` (`url`),
  KEY `hash_idx` (`hash`),
  KEY `citation_idx` (`citation`),
  KEY `first_user_idx` (`first_user`),
  CONSTRAINT `bookmark_citation_fk` FOREIGN KEY (`citation`) REFERENCES `citation` (`citation_id`),
  CONSTRAINT `bookmark_first_user_fk` FOREIGN KEY (`first_user`) REFERENCES `user` (`user_id`)
  -- SEARCH: FULLTEXT INDEX `url_ft` (`url`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `bookmark_details`
--

DROP TABLE IF EXISTS `bookmark_details`;
CREATE TABLE `bookmark_details` (
  `bookmark_id` int(7) unsigned NOT NULL default '0',
  `title` text,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`bookmark_id`),
  KEY `title_idx` (`title`(100)),
  KEY `combo_idx` (`bookmark_id`,`title`(100)),
  CONSTRAINT `bookmark_details_bookmark_id_fk` FOREIGN KEY (`bookmark_id`) REFERENCES `bookmark` (`bookmark_id`)
  -- SEARCH: FULLTEXT INDEX `title_ft` (`title`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `citation`
--

DROP TABLE IF EXISTS `citation`;
CREATE TABLE `citation` (
  `citation_id` int(7) unsigned NOT NULL auto_increment,
  `title` varchar(255) default NULL,
  `journal` int(7) unsigned default NULL,
  `volume` varchar(40) default NULL,
  `issue` varchar(40) default NULL,
  `start_page` varchar(40) default NULL,
  `end_page` varchar(40) default NULL,
  `pubmed` varchar(255) default NULL,
  `doi` varchar(255) default NULL,
  `asin` varchar(100) default NULL,
  `ris_type` varchar(4) default NULL,
  `raw_date` varchar(40) default NULL,
  `date` date default NULL,
  `last_modified_date` date default NULL,
  `user_supplied` int(1) unsigned NOT NULL default '0',
  `cs_module` varchar(40) default NULL,
  `cs_type` varchar(255) default NULL,
  `cs_source` varchar(255) default NULL,
  `cs_score` int(7) default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`citation_id`),
  KEY `title_idx` (`title`),
  KEY `journal_idx` (`journal`),
  KEY `pubmed_idx` (`pubmed`),
  KEY `doi_idx` (`doi`),
  KEY `asin_idx` (`asin`),
  KEY `ris_type_idx` (`ris_type`),
  KEY `user_supplied_idx` (`user_supplied`),
  KEY `cs_module_idx` (`cs_module`),
  CONSTRAINT `citation_journal_fk` FOREIGN KEY (`journal`) REFERENCES `journal` (`journal_id`)
  -- SEARCH: FULLTEXT INDEX `title_ft` (`title`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `citation_author`
--

DROP TABLE IF EXISTS `citation_author`;
CREATE TABLE `citation_author` (
  `citation_author_id` int(7) unsigned NOT NULL auto_increment,
  `citation` int(7) unsigned NOT NULL default '0',
  `author` int(7) unsigned NOT NULL default '0',
  `displayorder` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`citation_author_id`),
  KEY `citation_idx` (`citation`),
  KEY `author_idx` (`author`),
  KEY `combo_idx` (`citation`,`author`,`displayorder`),
  CONSTRAINT `citation_author_author_fk` FOREIGN KEY (`author`) REFERENCES `author` (`author_id`),
  CONSTRAINT `citation_author_citation_fk` FOREIGN KEY (`citation`) REFERENCES `citation` (`citation_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `comment`
--

DROP TABLE IF EXISTS `comment`;
CREATE TABLE `comment` (
  `comment_id` int(7) unsigned NOT NULL auto_increment,
  `entry` text,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`comment_id`),
  KEY `combo_idx` (`comment_id`,`created`)
  -- SEARCH: FULLTEXT INDEX `entry_ft` (`entry`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `gang`
--

DROP TABLE IF EXISTS `gang`;
CREATE TABLE `gang` (
  `gang_id` int(7) unsigned NOT NULL auto_increment,
  `name` varchar(255) NOT NULL default '',
  `owner` int(7) unsigned NOT NULL default '0',
  `description` text,
  `private` int(1) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`gang_id`),
  UNIQUE KEY `name_idx` (`name`),
  KEY `private_idx` (`private`),
  KEY `combo_idx` (`gang_id`,`name`,`owner`)
  -- SEARCH: FULLTEXT INDEX `name_ft` (`name`)
  -- SEARCH: FULLTEXT INDEX `description_ft` (`description`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `journal`
--

DROP TABLE IF EXISTS `journal`;
CREATE TABLE `journal` (
  `journal_id` int(7) unsigned NOT NULL auto_increment,
  `name` varchar(255) default NULL,
  `issn` varchar(255) default NULL,
  `coden` varchar(255) default NULL,
  `country` varchar(255) default NULL,
  `medline_code` varchar(255) default NULL,
  `medline_ta` varchar(255) default NULL,
  `nlm_unique_id` varchar(255) default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`journal_id`),
  KEY `name_idx` (`name`),
  KEY `issn_idx` (`issn`),
  KEY `medline_ta_idx` (`medline_ta`),
  KEY `name_combo_idx` (`journal_id`,`name`,`medline_ta`),
  KEY `issn_combo_idx` (`journal_id`,`issn`)
  -- SEARCH: FULLTEXT INDEX `name_ft` (`name`)
  -- SEARCH: FULLTEXT INDEX `medline_ta_ft` (`medline_ta`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `tag`
--

DROP TABLE IF EXISTS `tag`;
CREATE TABLE `tag` (
  `tag_id` int(7) unsigned NOT NULL auto_increment,
  `name` varchar(255) NOT NULL default '',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`tag_id`),
  UNIQUE KEY `name_idx` (`name`),
  KEY `combo_idx` (`tag_id`,`name`)
  -- SEARCH: FULLTEXT INDEX `name_ft` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `user`
--

DROP TABLE IF EXISTS `user`;
CREATE TABLE `user` (
  `user_id` int(7) unsigned NOT NULL auto_increment,
  `username` varchar(40) NOT NULL default '',
  `password` varchar(40) NOT NULL default '',
  `active` int(1) unsigned NOT NULL default '1',
  `firstname` varchar(40) default NULL,
  `lastname` varchar(40) default NULL,
  `email` varchar(255) default NULL,
  `verifycode` varchar(16) default NULL,
  `author` int(7) unsigned default NULL,
  `openurl_resolver` varchar(255) default NULL,
  `openurl_name` varchar(20) default NULL,
  `captcha_karma` decimal(6,2) NOT NULL default '0.00',
  `library_comment` int(7) unsigned default NULL,
  `reminder_email` datetime default NULL,
  `last_deletion` datetime default NULL,
  `quarantined` datetime default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_id`),
  UNIQUE KEY `username_idx` (`username`),
  UNIQUE KEY `email_idx` (`email`),
  KEY `active_idx` (`active`),
  KEY `name_combo_idx` (`lastname`,`firstname`),
  KEY `verifycode_idx` (`verifycode`),
  KEY `author_idx` (`author`),
  KEY `library_comment` (`library_comment`),
  KEY `auth_combo_idx` (`username`,`active`,`password`,`user_id`),
  KEY `quarantined_idx` (`quarantined`),
  CONSTRAINT `user_author_fk` FOREIGN KEY (`author`) REFERENCES `author` (`author_id`),
  CONSTRAINT `user_library_comment_fk` FOREIGN KEY (`library_comment`) REFERENCES `comment` (`comment_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `user_bookmark`
--

DROP TABLE IF EXISTS `user_bookmark`;
CREATE TABLE `user_bookmark` (
  `user_bookmark_id` int(7) unsigned NOT NULL auto_increment,
  `user` int(7) unsigned NOT NULL default '0',
  `bookmark` int(7) unsigned NOT NULL default '0',
  `citation` int(7) unsigned default NULL,
  `user_is_author` int(1) unsigned NOT NULL default '0',
  `def_public` int(1) unsigned NOT NULL default '1',
  `private` int(1) unsigned NOT NULL default '0',
  `private_gang` int(7) unsigned default NULL,
  `private_until` datetime default NULL,
  `quarantined` datetime default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_bookmark_id`),
  UNIQUE KEY `user_bookmark_idx` (`user`,`bookmark`),
  KEY `user_idx` (`user`),
  KEY `bookmark_idx` (`bookmark`),
  KEY `citation_idx` (`citation`),
  KEY `private_idx` (`private`),
  KEY `private_gang_idx` (`private_gang`),
  KEY `created_idx` (`created`),
  KEY `updated_idx` (`updated`),
  KEY `quarantined_idx` (`quarantined`),
  KEY `def_public_idx` (`def_public`),
  CONSTRAINT `user_bookmark_bookmark_fk` FOREIGN KEY (`bookmark`) REFERENCES `bookmark` (`bookmark_id`),
  CONSTRAINT `user_bookmark_citation_fk` FOREIGN KEY (`citation`) REFERENCES `citation` (`citation_id`),
  CONSTRAINT `user_bookmark_private_gang_fk` FOREIGN KEY (`private_gang`) REFERENCES `gang` (`gang_id`),
  CONSTRAINT `user_bookmark_user_fk` FOREIGN KEY (`user`) REFERENCES `user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `user_bookmark_comment`
--

DROP TABLE IF EXISTS `user_bookmark_comment`;
CREATE TABLE `user_bookmark_comment` (
  `user_bookmark_comment_id` int(7) unsigned NOT NULL auto_increment,
  `user_bookmark` int(7) unsigned NOT NULL default '0',
  `comment` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_bookmark_comment_id`),
  KEY `user_bookmark_idx` (`user_bookmark`),
  KEY `comment_idx` (`comment`),
  CONSTRAINT `user_bookmark_comment_comment_fk` FOREIGN KEY (`comment`) REFERENCES `comment` (`comment_id`),
  CONSTRAINT `user_bookmark_comment_user_bookmark_fk` FOREIGN KEY (`user_bookmark`) REFERENCES `user_bookmark` (`user_bookmark_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `user_bookmark_details`
--

DROP TABLE IF EXISTS `user_bookmark_details`;
CREATE TABLE `user_bookmark_details` (
  `user_bookmark_id` int(7) unsigned NOT NULL default '0',
  `title` text,
  `description` text,
  PRIMARY KEY  (`user_bookmark_id`),
  KEY `title_idx` (`title`(100)),
  KEY `combo_idx` (`user_bookmark_id`,`title`(100)),
  CONSTRAINT `user_bookmark_details_user_bookmark_fk` FOREIGN KEY (`user_bookmark_id`) REFERENCES `user_bookmark` (`user_bookmark_id`)
  -- SEARCH: FULLTEXT INDEX `title_ft` (`title`)
  -- SEARCH: FULLTEXT INDEX `description_ft` (`description`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `user_bookmark_tag`
--

DROP TABLE IF EXISTS `user_bookmark_tag`;
CREATE TABLE `user_bookmark_tag` (
  `user_bookmark_tag_id` int(7) unsigned NOT NULL auto_increment,
  `user_bookmark` int(7) unsigned NOT NULL default '0',
  `tag` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_bookmark_tag_id`),
  UNIQUE KEY `user_bookmark_tag_idx` (`user_bookmark`,`tag`),
  KEY `user_bookmark_idx` (`user_bookmark`),
  KEY `tag_idx` (`tag`),
  CONSTRAINT `user_bookmark_tag_tag_fk` FOREIGN KEY (`tag`) REFERENCES `tag` (`tag_id`),
  CONSTRAINT `user_bookmark_tag_user_bookmark_fk` FOREIGN KEY (`user_bookmark`) REFERENCES `user_bookmark` (`user_bookmark_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `user_gang`
--

DROP TABLE IF EXISTS `user_gang`;
CREATE TABLE `user_gang` (
  `user_gang_id` int(7) unsigned NOT NULL auto_increment,
  `user` int(7) unsigned NOT NULL default '0',
  `gang` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_gang_id`),
  UNIQUE KEY `user_gang_idx` (`user`,`gang`),
  KEY `user_idx` (`user`),
  KEY `gang_idx` (`gang`),
  CONSTRAINT `user_gang_gang_fk` FOREIGN KEY (`gang`) REFERENCES `gang` (`gang_id`),
  CONSTRAINT `user_gang_user_fk` FOREIGN KEY (`user`) REFERENCES `user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `user_tag_annotation`
--

DROP TABLE IF EXISTS `user_tag_annotation`;
CREATE TABLE `user_tag_annotation` (
  `user_tag_annotation_id` int(7) unsigned NOT NULL auto_increment,
  `user` int(7) unsigned NOT NULL default '0',
  `tag` int(7) unsigned NOT NULL default '0',
  `comment` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_tag_annotation_id`),
  KEY `user_idx` (`user`),
  KEY `tag_idx` (`tag`),
  KEY `comment_idx` (`comment`),
  KEY `user_tag_idx` (`user`,`tag`),
  CONSTRAINT `user_tag_annotation_comment_fk` FOREIGN KEY (`comment`) REFERENCES `comment` (`comment_id`),
  CONSTRAINT `user_tag_annotation_tag_fk` FOREIGN KEY (`tag`) REFERENCES `tag` (`tag_id`),
  CONSTRAINT `user_tag_annotation_user_fk` FOREIGN KEY (`user`) REFERENCES `user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
