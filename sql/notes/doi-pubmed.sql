SELECT MAX(ua.user_article_id) as max_user_article_id, MAX(UNIX_TIMESTAMP(ua.created)) as sortvalue
FROM user_article ua
LEFT JOIN bookmark b ON (ua.bookmark=b.bookmark_id)
LEFT JOIN article a ON (b.article=a.article_id)
LEFT JOIN citation ct2 ON (a.citation=ct2.citation_id)
WHERE (( ( ( ct2.doi is not null ) OR ( ct2.pubmed is not null ) ) )) AND ua.user_article_id IS NOT NULL AND ua.def_public = 1
GROUP BY b.article
ORDER BY sortvalue DESC
LIMIT 0, 10;

SELECT MAX(ua.user_article_id) as max_user_article_id, MAX(UNIX_TIMESTAMP(ua.created)) as sortvalue
FROM user_article ua
LEFT JOIN bookmark b ON (ua.bookmark=b.bookmark_id)
LEFT JOIN article a ON (b.article=a.article_id)
LEFT JOIN citation ct2 ON (a.citation=ct2.citation_id)
WHERE (( ( ( ct2.doi is not null ) OR ( ct2.pubmed is not null ) ) )) AND ua.user_article_id IS NOT NULL AND ua.def_public = 1
GROUP BY b.article
ORDER BY ua.created DESC
LIMIT 0, 10;

EXPLAIN
SELECT MAX(ua.user_article_id) as max_user_article_id, MAX(UNIX_TIMESTAMP(ua.created)) as sortvalue
FROM user_article ua
LEFT JOIN bookmark b ON (ua.bookmark=b.bookmark_id)
LEFT JOIN article a ON (b.article=a.article_id)
LEFT JOIN citation ct2 ON (a.citation=ct2.citation_id)
WHERE (ct2.doi is not null OR ct2.pubmed is not null) AND ua.user_article_id IS NOT NULL AND ua.def_public = 1
GROUP BY b.article
ORDER BY ua.created DESC
LIMIT 0, 10;

SELECT MAX(ua.user_article_id) as max_user_article_id, MAX(UNIX_TIMESTAMP(ua.created)) as sortvalue
FROM (SELECT * FROM user_article ORDER BY created DESC LIMIT 1000) ua
LEFT JOIN bookmark b ON (ua.bookmark=b.bookmark_id)
LEFT JOIN article a ON (b.article=a.article_id)
LEFT JOIN citation ct2 ON (a.citation=ct2.citation_id)
WHERE (( ( ( ct2.doi is not null ) OR ( ct2.pubmed is not null ) ) )) AND ua.user_article_id IS NOT NULL AND ua.def_public = 1
GROUP BY b.article
ORDER BY sortvalue DESC
LIMIT 0, 10;

SELECT MAX(ua.user_article_id) as max_user_article_id, MAX(UNIX_TIMESTAMP(ua.created)) as sortvalue
FROM (SELECT user_article.* FROM user_article LEFT JOIN ) ua
LEFT JOIN bookmark b ON (ua.bookmark=b.bookmark_id)
LEFT JOIN article a ON (b.article=a.article_id)
LEFT JOIN citation ct2 ON (a.citation=ct2.citation_id)
WHERE (( ( ( ct2.doi is not null ) OR ( ct2.pubmed is not null ) ) )) AND ua.user_article_id IS NOT NULL AND ua.def_public = 1
GROUP BY b.article
ORDER BY sortvalue DESC
LIMIT 0, 10;


