EXPLAIN
SELECT COUNT(DISTINCT ua.bookmark)
FROM (SELECT fmat.user_article_id, MAX(score)*1000000000+UNIX_TIMESTAMP(ua.created) as sortvalue
FROM
(
SELECT user_article_id, MAX(score) as score, 1 as positive FROM (SELECT   uad_s.user_article_id, 100 as score
FROM     user_article_details uad_s
WHERE    uad_s.title = 'evolution'
UNION
SELECT   ua.user_article_id, 100 as score
FROM     bookmark_details bd_s
         LEFT JOIN bookmark b_s ON (bd_s.bookmark_id=b_s.bookmark_id)
         LEFT JOIN user_article ua ON (b_s.article=ua.article)
WHERE    bd_s.title = 'evolution' AND b_s.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 99 as score
FROM     citation c_s
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
         LEFT JOIN user_article ua ON (ua.article=b_s.article)
WHERE    c_s.title = 'evolution' AND b_s.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 99 as score
FROM     citation c_s
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    c_s.title = 'evolution' AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 98 as score
FROM     journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    j_s.name = 'evolution' AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 98 as score
FROM     journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    j_s.name = 'evolution' AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 98 as score
FROM     journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    j_s.medline_ta = 'evolution' AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 98 as score
FROM     journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    j_s.medline_ta = 'evolution' AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 97 as score
FROM     author au_s
         LEFT JOIN citation_author cta_s ON (au_s.author_id=cta_s.author)
         LEFT JOIN citation c_s ON (c_s.citation_id=cta_s.citation)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    au_s.lastname = 'evolution' AND cta_s.citation_author_id IS NOT NULL AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 97 as score
FROM     author au_s
         LEFT JOIN citation_author cta_s ON (au_s.author_id=cta_s.author)
         LEFT JOIN citation c_s ON (c_s.citation_id=cta_s.citation)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    au_s.lastname = 'evolution' AND cta_s.citation_author_id IS NOT NULL AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   uad_s.user_article_id, 50 as score
FROM     connotea_search.user_article_details uad_s
WHERE    MATCH(uad_s.title) AGAINST ('evolution' IN BOOLEAN MODE)
UNION
SELECT   ua.user_article_id, 50 as score
FROM     connotea_search.bookmark_details bd_s
         LEFT JOIN bookmark b_s ON (bd_s.bookmark_id=b_s.bookmark_id)
         LEFT JOIN user_article ua ON (b_s.article=ua.article)
WHERE    MATCH(bd_s.title) AGAINST ('evolution' IN BOOLEAN MODE) AND b_s.bookmark_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 49 as score
FROM     connotea_search.citation c_s
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    MATCH(c_s.title) AGAINST ('evolution' IN BOOLEAN MODE) AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 49 as score
FROM     connotea_search.citation c_s
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    MATCH(c_s.title) AGAINST ('evolution' IN BOOLEAN MODE) AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 48 as score
FROM     connotea_search.journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    MATCH(j_s.name) AGAINST ('evolution' IN BOOLEAN MODE) AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 48 as score
FROM     connotea_search.journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    MATCH(j_s.name) AGAINST ('evolution' IN BOOLEAN MODE) AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 48 as score
FROM     connotea_search.journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    MATCH(j_s.medline_ta) AGAINST ('evolution' IN BOOLEAN MODE) AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 48 as score
FROM     connotea_search.journal j_s
         LEFT JOIN citation c_s ON (c_s.journal=j_s.journal_id)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    MATCH(j_s.medline_ta) AGAINST ('evolution' IN BOOLEAN MODE) AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 47 as score
FROM     connotea_search.bookmark b_s
         LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (a_s.article_id=ua.article)
WHERE    MATCH(b_s.url) AGAINST ('evolution' IN BOOLEAN MODE) AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   uad_s.user_article_id, 45 as score
FROM     connotea_search.user_article_details uad_s
WHERE    MATCH(uad_s.description) AGAINST ('evolution' IN BOOLEAN MODE)
UNION
SELECT   ua.user_article_id, 44 as score
FROM     connotea_search.comment c_s
         LEFT JOIN user_article_comment uac_s ON (c_s.comment_id=uac_s.comment)
         LEFT JOIN user_article ua ON (uac_s.user_article=ua.user_article_id)
WHERE    MATCH(c_s.entry) AGAINST ('evolution' IN BOOLEAN MODE) AND uac_s.user_article_comment_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 43 as score
FROM     connotea_search.author au_s
         LEFT JOIN citation_author cta_s ON (au_s.author_id=cta_s.author)
         LEFT JOIN citation c_s ON (c_s.citation_id=cta_s.citation)
         LEFT JOIN bookmark b_s ON (b_s.citation=c_s.citation_id)
	 LEFT JOIN article a_s ON (b_s.article=a_s.article_id)
         LEFT JOIN user_article ua ON (ua.article=a_s.article_id)
WHERE    MATCH(au_s.lastname, au_s.forename, au_s.firstname) AGAINST ('evolution' IN BOOLEAN MODE) AND cta_s.citation_author_id IS NOT NULL AND c_s.citation_id IS NOT NULL AND b_s.bookmark_id IS NOT NULL AND a_s.article_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   ua.user_article_id, 43 as score
FROM     connotea_search.author au_s
         LEFT JOIN citation_author cta_s ON (au_s.author_id=cta_s.author)
         LEFT JOIN citation c_s ON (c_s.citation_id=cta_s.citation)
         LEFT JOIN user_article ua ON (ua.citation=c_s.citation_id)
WHERE    MATCH(au_s.lastname, au_s.forename, au_s.firstname) AGAINST ('evolution' IN BOOLEAN MODE) AND cta_s.citation_author_id IS NOT NULL AND c_s.citation_id IS NOT NULL AND ua.user_article_id IS NOT NULL
UNION
SELECT   uat_s.user_article as user_article_id, 20 as score
FROM     tag t_s
         LEFT JOIN user_article_tag uat_s ON (uat_s.tag=t_s.tag_id)
WHERE    t_s.name = 'evolution' AND uat_s.user_article_tag_id IS NOT NULL
UNION
SELECT   uat_s.user_article as user_article_id, 20 as score
FROM     connotea_search.tag t_s
         LEFT JOIN user_article_tag uat_s ON (uat_s.tag=t_s.tag_id)
WHERE    MATCH(t_s.name) AGAINST ('evolution' IN BOOLEAN MODE) AND uat_s.user_article_tag_id IS NOT NULL
) as fmot1 GROUP BY user_article_id
) as fmat
LEFT JOIN user_article ua ON (fmat.user_article_id=ua.user_article_id)
GROUP BY fmat.user_article_id
HAVING SUM(fmat.positive) = '1' AND MIN(fmat.positive) = '1'
 ORDER BY sortvalue) as fm
LEFT JOIN user_article uaj ON (fm.user_article_id=uaj.user_article_id)
LEFT JOIN bookmark b ON (uaj.bookmark=b.bookmark_id)
LEFT JOIN user_article ua ON (b.bookmark_id=ua.bookmark AND ((((ua.private = 0 AND ua.private_gang IS NULL) OR ua.private_gang IN ('4','22') OR (ua.private_until IS NOT NULL AND ua.private_until <= NOW())) AND ua.quarantined IS NULL) OR ua.user = '978'));
