SELECT ua.user_article_id, ua.user, ua.article
FROM (SELECT uas.user_article_id FROM (SELECT user_article AS user_article_id FROM user_article_tag WHERE tag = 62) AS uas NATURAL JOIN user_article uao WHERE ((((uao.private = 0 AND uao.private_gang IS NULL) OR uao.private_gang IN ('4','22') OR (uao.private_until IS NOT NULL AND uao.private_until <= NOW())) AND uao.quarantined IS NULL) OR uao.user = '978') AND uao.user_article_id IS NOT NULL ORDER BY uao.created DESC LIMIT 0, 1000) AS uap
LEFT JOIN user_article ua ON (uap.user_article_id=ua.user_article_id)
LEFT JOIN user u ON (ua.user=u.user_id)

LEFT JOIN user_gang ug ON (u.user_id=ug.user)
LEFT JOIN gang g ON (ug.gang=g.gang_id)
LEFT JOIN article a2 ON (ua.article=a2.article_id)
LEFT JOIN user_article ua2 ON (a2.article_id=ua2.article AND ((((ua2.private = 0 AND ua2.private_gang IS NULL) OR ua2.private_gang IN ('4','22') OR (ua2.private_until IS NOT NULL AND ua2.private_until <= NOW())) AND ua2.quarantined IS NULL) OR ua2.user = '978'))
LEFT JOIN user_article_comment uac2 ON (ua2.user_article_id=uac2.user_article)
LEFT JOIN comment c2 ON (uac2.comment=c2.comment_id)
LEFT JOIN user_article ua3 ON (uac2.user_article=ua3.user_article_id AND ua3.user = '978')
LEFT JOIN user_article_tag uat4 ON (ua.user_article_id=uat4.user_article)
LEFT JOIN tag t4 ON (uat4.tag=t4.tag_id AND t4.name = 'geotagged')

LEFT JOIN user_article_tag uat2 ON (ua.user_article_id=uat2.user_article)
LEFT JOIN tag t2 ON (uat2.tag=t2.tag_id)
LEFT JOIN user_article_details uad ON (ua.user_article_id=uad.user_article_id)
LEFT JOIN citation ct ON (ua.citation=ct.citation_id)
LEFT JOIN citation_author cta ON (ct.citation_id=cta.citation)
LEFT JOIN author au ON (cta.author=au.author_id)
LEFT JOIN journal j ON (ct.journal=j.journal_id)
LEFT JOIN article a ON (ua.article=a.article_id)
LEFT JOIN bookmark b ON (ua.bookmark=b.bookmark_id)
LEFT JOIN bookmark_details bd ON (b.bookmark_id=bd.bookmark_id)
LEFT JOIN citation ct2 ON (a.citation=ct2.citation_id)
LEFT JOIN citation_author cta2 ON (ct2.citation_id=cta2.citation)
LEFT JOIN author au2 ON (cta2.author=au2.author_id)
LEFT JOIN journal j2 ON (ct2.journal=j2.journal_id)
LEFT JOIN citation ct3 ON (b.citation=ct3.citation_id)
LEFT JOIN citation_author cta3 ON (ct3.citation_id=cta3.citation)
LEFT JOIN author au3 ON (cta3.author=au3.author_id)
LEFT JOIN journal j3 ON (ct3.journal=j3.journal_id)

WHERE ua.user_article_id IS NOT NULL;
-- GROUP BY ua.user_article_id
-- ORDER BY ua.user_article_id DESC;
