SELECT *
FROM
(
SELECT   t.tag_id, t.name,
         COUNT(ubt.user_bookmark_tag_id) as filtered_count,
         COUNT(DISTINCT ub.user) as filtered_user_count,
         COUNT(DISTINCT ub.bookmark) as filtered_bookmark_count,
         MAX(ubt.created) as rss_date_override
FROM
(
SELECT   user_bookmark_id
FROM     user_bookmark
WHERE    created >= NOW() - INTERVAL 30 DAY
AND      created <= NOW() - INTERVAL 10 MINUTE
UNION
SELECT   user_bookmark_id
FROM     user_bookmark
WHERE    updated >= NOW() - INTERVAL 30 DAY
AND      updated <= NOW() - INTERVAL 10 MINUTE
) AS ubi
	 LEFT JOIN user_bookmark ub ON (ubi.user_bookmark_id=ub.user_bookmark_id AND (ub.def_public = 1 OR ub.private_until <= NOW()))
       	 LEFT JOIN user_bookmark_tag ubt ON ( ubt.user_bookmark = ub.user_bookmark_id )
         LEFT JOIN tag t ON ( ubt.tag = t.tag_id )
GROUP BY t.tag_id
HAVING   filtered_count > filtered_user_count AND filtered_count >= '5' AND filtered_user_count >= '5' AND filtered_bookmark_count >= '5'
ORDER BY filtered_count DESC
LIMIT    101
) AS ti
WHERE  	 name NOT IN ('uploaded')
ORDER BY filtered_count DESC
LIMIT    100;


SELECT   tag_id, name,
         filtered_count,
         filtered_user_count,
         filtered_bookmark_count,
         rss_date_override
FROM
(
SELECT   t.tag_id, t.name,
         COUNT(ubt.user_bookmark_tag_id) as filtered_count,
         COUNT(DISTINCT ub.user) as filtered_user_count,
         COUNT(DISTINCT ub.bookmark) as filtered_bookmark_count,
         MAX(ubt.created) as rss_date_override
FROM
(
SELECT   user_bookmark_id
FROM     user_bookmark
WHERE    created BETWEEN NOW() - INTERVAL 20 DAY AND NOW() - INTERVAL 10 MINUTE
UNION
SELECT   user_bookmark_id
FROM     user_bookmark
WHERE    updated BETWEEN NOW() - INTERVAL 20 DAY AND NOW() - INTERVAL 10 MINUTE
) AS ubi
	 LEFT JOIN user_bookmark ub ON (ubi.user_bookmark_id=ub.user_bookmark_id AND (ub.def_public = 1 OR ub.private_until <= NOW()))
       	 LEFT JOIN user_bookmark_tag ubt ON ( ubt.user_bookmark = ub.user_bookmark_id )
         LEFT JOIN tag t ON ( ubt.tag = t.tag_id )
WHERE    ub.user_bookmark_id IS NOT NULL
GROUP BY t.tag_id
HAVING   filtered_count > filtered_user_count
AND      filtered_count >= '5'
AND      filtered_user_count >= '5'
AND      filtered_bookmark_count >= '5'
ORDER BY filtered_count DESC
LIMIT    101
) AS ti
WHERE  	 name NOT IN ('uploaded')
LIMIT    100;



SELECT   tag_id, name,
         filtered_count,
         filtered_user_count,
         filtered_bookmark_count,
         rss_date_override
FROM
(
SELECT   t.tag_id, t.name,
         COUNT(ubt.user_bookmark_tag_id) as filtered_count,
         COUNT(DISTINCT ub.user) as filtered_user_count,
         COUNT(DISTINCT ub.bookmark) as filtered_bookmark_count,
         MAX(ubt.created) as rss_date_override
FROM     user_bookmark_tag ubt
	 LEFT JOIN user_bookmark ub ON (ubt.user_bookmark=ub.user_bookmark_id AND (ub.def_public = 1 OR ub.private_until <= NOW()))
         LEFT JOIN tag t ON ( ubt.tag = t.tag_id )
WHERE    ubt.created BETWEEN NOW() - INTERVAL 30 DAY AND NOW() - INTERVAL 10 MINUTE
AND      ub.user_bookmark_id IS NOT NULL
GROUP BY t.tag_id
HAVING   filtered_count > filtered_user_count
AND      filtered_count >= '5'
AND      filtered_user_count >= '5'
AND      filtered_bookmark_count >= '5'
ORDER BY filtered_count DESC
LIMIT    101
) AS ti
WHERE  	 name NOT IN ('uploaded')
LIMIT    100;


