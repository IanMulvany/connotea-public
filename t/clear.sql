SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE author;
TRUNCATE bookmark;
TRUNCATE bookmark_details;
TRUNCATE citation;
TRUNCATE citation_author;
TRUNCATE comment;
TRUNCATE gang;
TRUNCATE journal;
TRUNCATE tag;
TRUNCATE user;
TRUNCATE user_bookmark;
TRUNCATE user_bookmark_comment;
TRUNCATE user_bookmark_details;
TRUNCATE user_bookmark_tag;
TRUNCATE user_gang;
TRUNCATE user_tag_annotation;
#TRUNCATE user_bookmark_spam;

SET FOREIGN_KEY_CHECKS = 1;
