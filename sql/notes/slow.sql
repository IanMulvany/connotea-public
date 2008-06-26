
-- original query per http://www.connotea.org/data/bookmarks?num=2&start=0
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     bookmark b
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article AND ((((ua.private = 0 AND ua.private_gang IS NULL) OR
                                       ua.private_gang IN ('360','899','1312') OR
                                       (ua.private_until IS NOT NULL AND ua.private_until <= NOW())) AND
                                       ua.quarantined IS NULL) OR ua.user = '6468'))
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article AND ((((ua2.private = 0 AND ua2.private_gang IS NULL) OR
                                        ua2.private_gang IN ('360','899','1312') OR
                                        (ua2.private_until IS NOT NULL AND ua2.private_until <= NOW())) AND
                                        ua2.quarantined IS NULL) OR ua2.user = '6468'))
WHERE    b.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 0, 2;

+----+-------------+-------+--------+-----------------------------------------------------------------------------------------------------------------------+----------------------+---------+-----------------------------+--------+----------------------------------------------+
| id | select_type | table | type   | possible_keys                                                                                                         | key                  | key_len | ref                         | rows   | Extra                                        |
+----+-------------+-------+--------+-----------------------------------------------------------------------------------------------------------------------+----------------------+---------+-----------------------------+--------+----------------------------------------------+
|  1 | SIMPLE      | ua    | ALL    | PRIMARY,user_article_idx,user_idx,article_idx,private_idx,private_gang_idx,quarantined_idx,privacy_combo_idx,rss2_idx | NULL                 | NULL    | NULL                        | 692845 | Using where; Using temporary; Using filesort | 
|  1 | SIMPLE      | a     | eq_ref | PRIMARY                                                                                                               | PRIMARY              | 4       | connotea.ua.article         |      1 | Using where; Using index                     | 
|  1 | SIMPLE      | b     | ref    | PRIMARY,article_idx                                                                                                   | article_idx          | 5       | connotea.a.article_id       |      1 | Using where                                  | 
|  1 | SIMPLE      | uat2  | ref    | user_article_tag_idx,user_article_idx                                                                                 | user_article_tag_idx | 4       | connotea.ua.user_article_id |      1 |                                              | 
|  1 | SIMPLE      | t2    | eq_ref | PRIMARY,combo_idx                                                                                                     | PRIMARY              | 4       | connotea.uat2.tag           |      1 |                                              | 
|  1 | SIMPLE      | a2    | eq_ref | PRIMARY                                                                                                               | PRIMARY              | 4       | connotea.a.article_id       |      1 | Using index                                  | 
|  1 | SIMPLE      | ua2   | ref    | user_article_idx,user_idx,article_idx,private_idx,private_gang_idx,quarantined_idx,privacy_combo_idx,rss2_idx         | article_idx          | 4       | connotea.a2.article_id      |      1 |                                              | 
+----+-------------+-------+--------+-----------------------------------------------------------------------------------------------------------------------+----------------------+---------+-----------------------------+--------+----------------------------------------------+

-- no privacy
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     bookmark b
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article)
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article)
WHERE    b.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 0, 2;


-- no privacy, subselect to start off bookmarks (wrong)
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     (SELECT bookmark_id FROM bookmark ORDER BY created DESC LIMIT 0, 2) as bi
         LEFT JOIN bookmark b ON (bi.bookmark_id=b.bookmark_id)
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article)
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article)
WHERE    b.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 0, 2;

--  b1 ua(u1,b1)
--     ua(u2,b1)
--  b2 NULL
--  b3 ua(u1,b3)


-- no privacy, subselect to start off bookmarks (wrong)
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     (
SELECT   bookmark_id
FROM     bookmark FORCE INDEX(created_idx)
WHERE    article IS NOT NULL
ORDER BY created DESC
LIMIT 40000
) as bi2
         LEFT JOIN bookmark b ON (bi2.bookmark_id=b.bookmark_id)
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article)
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article)
WHERE    b.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 1000, 1000;

-- bookmarks, that i can see logged in, that have been confirmed with user_article's (not transient)
-- of those, page to a certain point and limit results
-- of those, give me stats on all tags used with them and how many user_articles posted with them

--  b1 ua(u1,b1)
--     ua(u2,b1)
--  b2 NULL
--  b3 ua(u1,b3)

--  xoooxoxoxxoxXxoxooxooXxxxoxoxoxxoxoxoxoxxxooxxxxoooxxxoxoxoxo
--  x   x x xx xXx x  x  Xxxx x x xx x x x xxx  xxxx   xxx x x x 
--  x   x x xx x x x  x   xxx x x xx x x x xxx  xxxx   xxx x x x 
--             . . .  .   ... . . .. . . . ...  ...
--  LIMIT 6, 20 [26]


-- no privacy, subselect to start off bookmarks
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     (
SELECT   bi.bookmark_id, (SELECT COUNT(uai.user_article_id) FROM article ai LEFT JOIN user_article uai ON (ai.article_id = uai.article) WHERE bi.article = ai.article_id AND uai.def_public = 1) AS cnt
FROM     bookmark bi
HAVING   cnt > 0
ORDER BY bi.created DESC
LIMIT    1000
) as bi2
         LEFT JOIN bookmark b ON (bi2.bookmark_id=b.bookmark_id)
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article)
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article)
WHERE    b.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC;



-- no privacy
EXPLAIN
SELECT   STRAIGHT_JOIN SQL_BIG_RESULT
         b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     bookmark b
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article)
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article)
WHERE    b.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 0, 2;


-- with ua first
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     user_article ua
	 LEFT JOIN bookmark b ON (b.article=ua.article)
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article AND ((((ua2.private = 0 AND ua2.private_gang IS NULL) OR
                                        ua2.private_gang IN ('360','899','1312') OR
                                        (ua2.private_until IS NOT NULL AND ua2.private_until <= NOW())) AND
                                        ua2.quarantined IS NULL) OR ua2.user = '6468'))
WHERE    b.bookmark_id IS NOT NULL
AND      ((((ua.private = 0 AND ua.private_gang IS NULL) OR
         ua.private_gang IN ('360','899','1312') OR
         (ua.private_until IS NOT NULL AND ua.private_until <= NOW())) AND
         ua.quarantined IS NULL) OR ua.user = '6468')
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 0, 2;


-- with ua first
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     (
SELECT   bi.bookmark_id
FROM     user_article uai
	 LEFT JOIN bookmark bi ON (bi.article=uai.article)
WHERE    ((((uai.private = 0 AND uai.private_gang IS NULL) OR
         uai.private_gang IN ('360','899','1312') OR
         (uai.private_until IS NOT NULL AND uai.private_until <= NOW())) AND
         uai.quarantined IS NULL) OR uai.user = '6468')
HAVING   bi.bookmark_id IS NOT NULL
ORDER BY bi.created DESC
LIMIT 0, 2
) AS bi2
         LEFT JOIN bookmark b ON (bi2.bookmark_id=b.bookmark_id)
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article)
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article AND ((((ua2.private = 0 AND ua2.private_gang IS NULL) OR
                                        ua2.private_gang IN ('360','899','1312') OR
                                        (ua2.private_until IS NOT NULL AND ua2.private_until <= NOW())) AND
                                        ua2.quarantined IS NULL) OR ua2.user = '6468'))
WHERE    b.bookmark_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 0, 2;

-- http://www.connotea.org/data/bookmarks/user/Declan?num=2&start=0
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     user u
         LEFT JOIN user_article ua ON (u.user_id=ua.user AND ((((ua.private = 0 AND ua.private_gang IS NULL) OR
                                       ua.private_gang IN ('4','22') OR (ua.private_until IS NOT NULL AND
                                       ua.private_until <= NOW())) AND ua.quarantined IS NULL) OR ua.user = '978'))
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN bookmark b ON (ua.bookmark=b.bookmark_id)
	 LEFT JOIN article a2 ON (b.article=a2.article_id)
         LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article AND ((((ua2.private = 0 AND ua2.private_gang IS NULL) OR
                                        ua2.private_gang IN ('4','22') OR (ua2.private_until IS NOT NULL AND
                                        ua2.private_until <= NOW())) AND ua2.quarantined IS NULL) OR ua2.user = '978'))
WHERE    (( ( ( u.user_id = '1015' ) ) )) AND b.bookmark_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 0, 2;

-- just mess with order by
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated
FROM     bookmark b
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article AND ((((ua.private = 0 AND ua.private_gang IS NULL) OR
                                       ua.private_gang IN ('360','899','1312') OR
                                       (ua.private_until IS NOT NULL AND ua.private_until <= NOW())) AND
                                       ua.quarantined IS NULL) OR ua.user = '6468'))
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article AND ((((ua2.private = 0 AND ua2.private_gang IS NULL) OR
                                        ua2.private_gang IN ('360','899','1312') OR
                                        (ua2.private_until IS NOT NULL AND ua2.private_until <= NOW())) AND
                                        ua2.quarantined IS NULL) OR ua2.user = '6468'))
ORDER BY b.created DESC
LIMIT 0, 2;


-- time hack
EXPLAIN
SELECT   b.bookmark_id, b.url, b.hash, b.article, b.citation, b.first_user, b.created, b.updated,
         COUNT(DISTINCT ua2.user_article_id) as user_article_count_packed,
         IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL')
                             ORDER BY uat2.created SEPARATOR '///'), '') AS tags_packed,
         UNIX_TIMESTAMP(b.created) AS sortvalue
FROM     bookmark b
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article AND ((((ua.private = 0 AND ua.private_gang IS NULL) OR
                                       ua.private_gang IN ('360','899','1312') OR
                                       (ua.private_until IS NOT NULL AND ua.private_until <= NOW())) AND
                                       ua.quarantined IS NULL) OR ua.user = '6468'))
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article AND ((((ua2.private = 0 AND ua2.private_gang IS NULL) OR
                                        ua2.private_gang IN ('360','899','1312') OR
                                        (ua2.private_until IS NOT NULL AND ua2.private_until <= NOW())) AND
                                        ua2.quarantined IS NULL) OR ua2.user = '6468'))
WHERE    b.created > NOW() - INTERVAL 7 DAY AND b.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
GROUP BY b.bookmark_id
ORDER BY sortvalue DESC
LIMIT 0, 2;


-- (count) no privacy, subselect to start off bookmarks
EXPLAIN
SELECT   COUNT(DISTINCT b.bookmark_id)
FROM     (
SELECT   bi.bookmark_id, (SELECT COUNT(uai.user_article_id) FROM article ai LEFT JOIN user_article uai ON (ai.article_id = uai.article) WHERE bi.article = ai.article_id AND uai.def_public = 1) AS cnt
FROM     bookmark bi
HAVING   cnt > 0
) as bi2
         LEFT JOIN bookmark b ON (bi2.bookmark_id=b.bookmark_id)
	 LEFT JOIN article a ON (b.article=a.article_id)
	 LEFT JOIN user_article ua ON (a.article_id=ua.article)
	 LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
	 LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
	 LEFT JOIN article a2 ON (ua.article=a2.article_id)
	 LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article)
WHERE    b.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL;
