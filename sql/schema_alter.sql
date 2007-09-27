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

set FOREIGN_KEY_CHECKS = 0;

CREATE TABLE `article` (
  `article_id` int(7) unsigned NOT NULL auto_increment,
  `hash` varchar(32) NOT NULL default '',
  `created` datetime NOT NULL default '0000-00-00 00:00:00',
  `updated` datetime default NULL,
  PRIMARY KEY  (`article_id`),
  KEY `hash_idx` (`hash`)
) ENGINE=InnoDB;

alter table citation add column article int(7) after hash;

set FOREIGN_KEY_CHECKS = 1;
