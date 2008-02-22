-- ALTER commands to update your database to accommodate the current version.
-- This file is not needed for first-time installers.
-- Change the following line to your database name:
USE bibliotech;


-- Since 1.0.1:
-- Note the following is destructive of citation data, use 'retro' afterwards to reimport data

set FOREIGN_KEY_CHECKS = 0;

CREATE TABLE gang (
  gang_id int(7) unsigned NOT NULL auto_increment,
  name varchar(255) NOT NULL default '',
  owner int(7) unsigned NOT NULL default '0',
  description text,
  private int(1) unsigned NOT NULL default '0',
  created datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (gang_id),
  UNIQUE KEY name_idx (name),
  KEY private_idx (private)
) TYPE=InnoDB;

CREATE TABLE user_gang (
  user_gang_id int(7) unsigned NOT NULL auto_increment,
  user int(7) unsigned NOT NULL default '0',
  gang int(7) unsigned NOT NULL default '0',
  created datetime NOT NULL default '0000-00-00 00:00:00',
  updated datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (user_gang_id),
  UNIQUE KEY user_gang_idx (user,gang),
  KEY user_idx (user),
  KEY gang_idx (gang),
  CONSTRAINT FOREIGN KEY (`user`) REFERENCES `user` (`user_id`),
  CONSTRAINT FOREIGN KEY (`gang`) REFERENCES `gang` (`gang_id`)
) TYPE=InnoDB;

CREATE TABLE citation (
  citation_id int(7) unsigned NOT NULL auto_increment,
  title varchar(255) default NULL,
  journal int(7) unsigned default NULL,
  volume varchar(40) default NULL,
  issue varchar(40) default NULL,
  start_page varchar(40) default NULL,
  end_page varchar(40) default NULL,
  pubmed varchar(255) default NULL,
  doi varchar(255) default NULL,
  asin varchar(100) default NULL,
  ris_type char(4) default NULL,
  raw_date varchar(40) default NULL,
  date date default NULL,
  last_modified_date date default NULL,
  user_supplied int(1) unsigned NOT NULL default '0',
  cs_module varchar(40),
  cs_type varchar(255),
  cs_source varchar(255),
  created datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (citation_id),
  KEY journal_idx (journal),
  KEY pubmed_idx (pubmed),
  KEY doi_idx (doi),
  KEY ris_type_idx (ris_type),
  KEY user_supplied_idx (user_supplied),
  KEY cs_module_idx (cs_module),
  CONSTRAINT FOREIGN KEY (`journal`) REFERENCES `journal` (`journal_id`)
) TYPE=InnoDB;

CREATE TABLE citation_author (
  citation_author_id int(7) unsigned NOT NULL auto_increment,
  citation int(7) unsigned NOT NULL default '0',
  author int(7) unsigned NOT NULL default '0',
  displayorder int(7) unsigned NOT NULL default '0',
  created datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (citation_author_id),
  KEY citation_idx (citation),
  KEY author_idx (author),
  CONSTRAINT FOREIGN KEY (`citation`) REFERENCES `citation` (`citation_id`),
  CONSTRAINT FOREIGN KEY (`author`) REFERENCES `author` (`author_id`)
) TYPE=InnoDB;

alter table user_bookmark add column citation int(7) unsigned after bookmark;
alter table user_bookmark add key citation_idx (citation);
alter table user_bookmark add constraint foreign key (citation) references citation (citation_id);
alter table user_bookmark add column private int(1) unsigned not null default '0' after user_is_author;
alter table user_bookmark add key private_idx (private);
alter table user_bookmark add column private_gang int(7) unsigned after private;
alter table user_bookmark add key private_gang_idx (private_gang);
alter table user_bookmark add constraint foreign key (private_gang) references gang (gang_id);
alter table user_bookmark add column private_until datetime after private_gang;
alter table bookmark add column citation int(7) unsigned after hash;
alter table bookmark add key citation_idx (citation);
alter table bookmark add constraint foreign key (citation) references citation (citation_id);
alter table bookmark add column first_user int(7) unsigned after hash;
alter table bookmark add key first_user_idx (first_user);
alter table bookmark add constraint foreign key (first_user) references user (user_id);
alter table bookmark add column updated datetime not null after created;

drop table bookmark_citation;
drop table bookmark_author;

set FOREIGN_KEY_CHECKS = 1;


-- Since 1.2.1 (internal):

set FOREIGN_KEY_CHECKS = 0;

alter table user_bookmark add key created_idx (created);
alter table user_bookmark add key privacy_combo_idx (user,private,private_gang,private_until);
alter table user_bookmark add constraint foreign key (citation) references citation (citation_id);
alter table user_bookmark add constraint foreign key (private_gang) references gang (gang_id);

alter table user add column openurl_resolver varchar(255) after author;
alter table user add column openurl_name varchar(20) after openurl_resolver;

CREATE TABLE `user_tag_annotation` (
  user_tag_annotation_id int(7) unsigned NOT NULL auto_increment,
  user int(7) unsigned NOT NULL default '0',
  tag int(7) unsigned NOT NULL default '0',
  comment int(7) unsigned NOT NULL default '0',
  created datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (user_tag_annotation_id),
  KEY user_idx (user),
  KEY tag_idx (tag),
  KEY comment_idx (comment),
  KEY user_tag_idx (user, tag),
  CONSTRAINT FOREIGN KEY (`user`) REFERENCES `user` (`user_id`),
  CONSTRAINT FOREIGN KEY (`tag`) REFERENCES `tag` (`tag_id`),
  CONSTRAINT FOREIGN KEY (`comment`) REFERENCES `comment` (`comment_id`)
) TYPE=InnoDB;

alter table user add column library_comment int(7) unsigned after openurl_name;
alter table user add constraint foreign key (library_comment) references comment (comment_id);

alter table user change column email email varchar(255);

set FOREIGN_KEY_CHECKS = 1;


-- Since 1.7.1:

set FOREIGN_KEY_CHECKS = 0;

alter table user add column reminder_email datetime after library_comment;

alter table gang add column updated datetime after created;
alter table tag  add column updated datetime after created;

alter table user add column captcha_karma decimal(6,2) not null default 0 after openurl_name;

alter table user_bookmark add key updated_idx (updated);
alter table user_bookmark add column quarantined datetime default null after private_until;
alter table user_bookmark add key quarantined_idx (quarantined);
alter table user add column quarantined datetime default null after last_deletion;
alter table user add key quarantined_idx (quarantined);

alter table author add column misc varchar(255) after suffix;
alter table user_bookmark add column def_public int(1) unsigned not null default 1 after user_is_author;
alter table user_bookmark add key def_public_idx (def_public);
update user_bookmark set def_public = 0 where private = 1 or private_gang is not null or private_until is not null or quarantined is not null;

alter table citation add column cs_score int(7) after cs_source;

set FOREIGN_KEY_CHECKS = 1;


-- Since 1.8:
-- Run article_upgrade.pl afterwards to complete

set FOREIGN_KEY_CHECKS = 0;

USE bibliotech_search;

CREATE TABLE `article` (
  `article_id` int(7) unsigned NOT NULL auto_increment,
  `hash` varchar(32) NOT NULL default '',
  `citation` int(7) unsigned default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`article_id`),
  KEY `hash_idx` (`hash`)
) ENGINE=MyISAM;

USE bibliotech;

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

USE bibliotech_search;

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

USE bibliotech;

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
insert into article select bookmark_id as article_id, hash, created, updated from bookmark;
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

USE bibliotech_search;

CREATE TABLE `user_openid` (
  `user` int(7) unsigned NOT NULL,
  `openid` varchar(255) default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user`),
  KEY `openid_idx` (`openid`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

USE bibliotech;

CREATE TABLE `user_openid` (
  `user` int(7) unsigned NOT NULL,
  `openid` varchar(255) default NULL,
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`user`),
  KEY `openid_idx` (`openid`),
  CONSTRAINT `user_fk` FOREIGN KEY (`user`) REFERENCES `user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

alter table user add origin enum('normal','openid') not null default 'normal' after quarantined;

-- fix issue with citation source module system where some hashes were not correct
create temporary table tmp_a as select distinct article from bookmark where hash != md5(url) and article is not null;
alter table tmp_a add key article_idx (article);
update bookmark set hash = md5(url) where hash != md5(url);
update article a set hash = (select b1.hash from bookmark b1 where b1.article = a.article_id order by b1.created limit 1) where a.article_id in (select article from tmp_a) and a.hash not in (select b2.hash from bookmark b2 where b2.article = a.article_id);
drop temporary table tmp_a;

set FOREIGN_KEY_CHECKS = 1;
