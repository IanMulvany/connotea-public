-- Since 1.8:

set FOREIGN_KEY_CHECKS = 0;

USE connotea_search;

CREATE TABLE `article` (
  `article_id` int(7) unsigned NOT NULL auto_increment,
  `hash` varchar(32) NOT NULL default '',
  `citation` int(7) unsigned default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`article_id`),
  KEY `hash_idx` (`hash`)
) ENGINE=MyISAM;

USE connotea;

CREATE TABLE IF NOT EXISTS `article` (
  `article_id` int(7) unsigned NOT NULL auto_increment,
  `hash` varchar(32) NOT NULL default '',
  `citation` int(7) unsigned default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`article_id`),
  KEY `hash_idx` (`hash`),
  CONSTRAINT `citation_fk` FOREIGN KEY (`citation`) REFERENCES `citation` (`citation_id`)
) ENGINE=InnoDB;

alter table bookmark add column article int(7) unsigned default NULL after hash,
      	             add key article_idx (article),
                     add constraint article_fk foreign key (article) references article (article_id),
                     change column url url varchar(400) NOT NULL default '';

USE connotea_search;

CREATE TABLE `user_article` (
  `user_article_id` int(7) unsigned NOT NULL auto_increment,
  `user` int(7) unsigned NOT NULL default '0',
  `article` int(7) unsigned NOT NULL default '0',
  `bookmark` int(7) unsigned NOT NULL default '0',
  `citation` int(7) unsigned default NULL,
  `user_is_author` int(1) unsigned NOT NULL default '0',
  `def_public` int(1) unsigned NOT NULL default '1',
  `private` int(1) unsigned NOT NULL default '0',
  `private_gang` int(7) unsigned default NULL,
  `private_until` datetime default NULL,
  `quarantined` datetime default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`user_article_id`),
  UNIQUE KEY `user_article_idx` (`user`,`article`),
  KEY `user_idx` (`user`),
  KEY `article_idx` (`article`),
  KEY `citation_idx` (`citation`),
  KEY `private_idx` (`private`),
  KEY `private_gang_idx` (`private_gang`),
  KEY `created_idx` (`created`),
  KEY `quarantined_idx` (`quarantined`),
  KEY `updated_idx` (`updated`),
  KEY `privacy_combo_idx` (`private`,`private_gang`,`private_until`,`quarantined`),
  KEY `def_public_idx` (`def_public`),
  KEY `rss1_idx` (`def_public`,`created`),
  KEY `rss2_idx` (`private_until`,`def_public`)
) ENGINE=MyISAM;

CREATE TABLE `user_article_details` (
  `user_article_id` int(7) unsigned NOT NULL default '0',
  `title` text,
  `description` text,
  PRIMARY KEY  (`user_article_id`),
  KEY `title_idx` (`title`(100)),
  KEY `combo_idx` (`user_article_id`,`title`(100)),
  FULLTEXT INDEX `title_ft` (`title`),
  FULLTEXT INDEX `description_ft` (`description`)
) ENGINE=MyISAM;

CREATE TABLE `user_article_tag` (
  `user_article_tag_id` int(7) unsigned NOT NULL auto_increment,
  `user_article` int(7) unsigned NOT NULL default '0',
  `tag` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_article_tag_id`),
  UNIQUE KEY `user_article_tag_idx` (`user_article`,`tag`),
  KEY `user_article_idx` (`user_article`),
  KEY `tag_idx` (`tag`)
) ENGINE=MyISAM;

CREATE TABLE `user_article_comment` (
  `user_article_comment_id` int(7) unsigned NOT NULL auto_increment,
  `user_article` int(7) unsigned NOT NULL default '0',
  `comment` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_article_comment_id`),
  KEY `user_article_idx` (`user_article`),
  KEY `comment_idx` (`comment`)
) ENGINE=MyISAM;

USE connotea;

CREATE TABLE IF NOT EXISTS `user_article` (
  `user_article_id` int(7) unsigned NOT NULL auto_increment,
  `user` int(7) unsigned NOT NULL default '0',
  `article` int(7) unsigned NOT NULL default '0',
  `bookmark` int(7) unsigned NOT NULL default '0',
  `citation` int(7) unsigned default NULL,
  `user_is_author` int(1) unsigned NOT NULL default '0',
  `def_public` int(1) unsigned NOT NULL default '1',
  `private` int(1) unsigned NOT NULL default '0',
  `private_gang` int(7) unsigned default NULL,
  `private_until` datetime default NULL,
  `quarantined` datetime default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`user_article_id`),
  UNIQUE KEY `user_article_idx` (`user`,`article`),
  KEY `user_idx` (`user`),
  KEY `article_idx` (`article`),
  KEY `citation_idx` (`citation`),
  KEY `private_idx` (`private`),
  KEY `private_gang_idx` (`private_gang`),
  KEY `created_idx` (`created`),
  KEY `quarantined_idx` (`quarantined`),
  KEY `updated_idx` (`updated`),
  KEY `privacy_combo_idx` (`private`,`private_gang`,`private_until`,`quarantined`),
  KEY `def_public_idx` (`def_public`),
  KEY `rss1_idx` (`def_public`,`created`),
  KEY `rss2_idx` (`private_until`,`def_public`),
  CONSTRAINT `user_article_article_fk` FOREIGN KEY (`article`) REFERENCES `article` (`article_id`),
  CONSTRAINT `user_article_citation_fk` FOREIGN KEY (`citation`) REFERENCES `citation` (`citation_id`),
  CONSTRAINT `user_article_private_gang_fk` FOREIGN KEY (`private_gang`) REFERENCES `gang` (`gang_id`),
  CONSTRAINT `user_article_user_fk` FOREIGN KEY (`user`) REFERENCES `user` (`user_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `user_article_details` (
  `user_article_id` int(7) unsigned NOT NULL default '0',
  `title` text,
  `description` text,
  PRIMARY KEY  (`user_article_id`),
  KEY `title_idx` (`title`(100)),
  KEY `combo_idx` (`user_article_id`,`title`(100)),
  CONSTRAINT `user_article_details_user_article_fk` FOREIGN KEY (`user_article_id`) REFERENCES `user_article` (`user_article_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `user_article_tag` (
  `user_article_tag_id` int(7) unsigned NOT NULL auto_increment,
  `user_article` int(7) unsigned NOT NULL default '0',
  `tag` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_article_tag_id`),
  UNIQUE KEY `user_article_tag_idx` (`user_article`,`tag`),
  KEY `user_article_idx` (`user_article`),
  KEY `tag_idx` (`tag`),
  CONSTRAINT `user_article_tag_tag_fk` FOREIGN KEY (`tag`) REFERENCES `tag` (`tag_id`),
  CONSTRAINT `user_article_tag_user_article_fk` FOREIGN KEY (`user_article`) REFERENCES `user_article` (`user_article_id`)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `user_article_comment` (
  `user_article_comment_id` int(7) unsigned NOT NULL auto_increment,
  `user_article` int(7) unsigned NOT NULL default '0',
  `comment` int(7) unsigned NOT NULL default '0',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user_article_comment_id`),
  KEY `user_article_idx` (`user_article`),
  KEY `comment_idx` (`comment`),
  CONSTRAINT `user_article_comment_comment_fk` FOREIGN KEY (`comment`) REFERENCES `comment` (`comment_id`),
  CONSTRAINT `user_article_comment_user_article_fk` FOREIGN KEY (`user_article`) REFERENCES `user_article` (`user_article_id`)
) ENGINE=InnoDB;

-- transfer of old user_bookmark data:
insert into article select bookmark_id as article_id, hash, citation, created, updated from bookmark;
update bookmark set article=bookmark_id;
insert into user_article select user_bookmark_id as user_article_id, user, bookmark as article, bookmark, citation, user_is_author, def_public, private, private_gang, private_until, quarantined, created, updated from user_bookmark;
drop table user_bookmark;
insert into user_article_tag select user_bookmark_tag_id as user_article_tag_id, user_bookmark as user_article, tag, created from user_bookmark_tag;
drop table user_bookmark_tag;
insert into user_article_details select user_bookmark_id as user_article_id, title, description from user_bookmark_details;
drop table user_bookmark_details;
insert into user_article_comment select user_bookmark_comment_id as user_article_comment_id, user_bookmark as user_article, comment, created from user_bookmark_comment;
drop table user_bookmark_comment;
--- data should work now, just won't be combined; run article_upgrade.pl to complete

set FOREIGN_KEY_CHECKS = 1;
