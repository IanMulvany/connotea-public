
DROP TEMPORARY TABLE IF EXISTS qq1;
CREATE TEMPORARY TABLE qq1 AS
  SELECT   user_bookmark_id
  FROM     user_bookmark
  WHERE    user = 978;
ALTER TABLE qq1 ADD INDEX user_bookmark_id_idx (user_bookmark_id);
DROP TEMPORARY TABLE IF EXISTS qq2;
CREATE TEMPORARY TABLE qq2 AS
  SELECT   ubs.user_bookmark_id
  FROM     qq1 AS ubs
           NATURAL JOIN user_bookmark ubo
  WHERE    ((((ubo.private = 0 AND ubo.private_gang IS NULL)
              OR ubo.private_gang IN (4,22,25)
              OR (ubo.private_until IS NOT NULL AND ubo.private_until <= NOW()))
             AND ubo.quarantined IS NULL) OR ubo.user = ?)
  AND      ubo.user_bookmark_id IS NOT NULL
  ORDER BY ubo.created DESC
  LIMIT 0, 10;
ALTER TABLE qq2 ADD INDEX user_bookmark_id_idx (user_bookmark_id);

SELECT ub.user_bookmark_id, ub.user, ub.bookmark, ub.updated, ub.citation,
       ub.user_is_author, ub.def_public, ub.private, ub.private_gang,
       ub.private_until, ub.quarantined, ub.created,
       u.user_id, u.username, u.openurl_resolver, u.openurl_name, u.updated,
       IFNULL(GROUP_CONCAT(DISTINCT CONCAT(g.gang_id),':/:',IFNULL(g.name, '+NULL'),':/:',IFNULL(g.owner, '+NULL'),':/:',IFNULL(g.private, '+NULL'),':/:',IFNULL(g.updated, '+NULL') ORDER BY ug.created SEPARATOR '///'), '') AS _u_gangs_packed,
       b.bookmark_id, b.url, b.hash, b.updated, b.citation,
       ubd.user_bookmark_id, ubd.title, ubd.description,
       bd.bookmark_id, bd.title, bd.created,
       ct.citation_id, ct.title, ct.journal, ct.volume, ct.issue, ct.start_page,
       ct.end_page, ct.pubmed, ct.doi, ct.asin, ct.ris_type, ct.raw_date,
       ct.date, ct.last_modified_date, ct.user_supplied, ct.cs_module,
       ct.cs_type, ct.cs_source, ct.created,
       j.journal_id, j.name, j.issn, j.coden, j.country, j.medline_code,
       j.medline_ta, j.nlm_unique_id,
       cta.citation_author_id, cta.citation, cta.author, cta.displayorder,
       IFNULL(GROUP_CONCAT(DISTINCT CONCAT(a.author_id),':/:',IFNULL(a.firstname, '+NULL'),':/:',IFNULL(a.forename, '+NULL'),':/:',IFNULL(a.initials, '+NULL'),':/:',IFNULL(a.middlename, '+NULL'),':/:',IFNULL(a.lastname, '+NULL'),':/:',IFNULL(a.suffix, '+NULL'),':/:',IFNULL(a.misc, '+NULL'),':/:',IFNULL(a.postal_address, '+NULL'),':/:',IFNULL(a.affiliation, '+NULL'),':/:',IFNULL(a.email, '+NULL'),':/:',IFNULL(a.user, '+NULL') ORDER BY cta.displayorder SEPARATOR '///'), '') AS _ct_authors_packed,
       ct2.citation_id, ct2.title, ct2.journal, ct2.volume, ct2.issue,
       ct2.start_page, ct2.end_page, ct2.pubmed, ct2.doi, ct2.asin,
       ct2.ris_type, ct2.raw_date, ct2.date, ct2.last_modified_date,
       ct2.user_supplied, ct2.cs_module, ct2.cs_type, ct2.cs_source,
       ct2.created,
       j2.journal_id, j2.name, j2.issn, j2.coden, j2.country, j2.medline_code,
       j2.medline_ta, j2.nlm_unique_id,
       cta2.citation_author_id, cta2.citation, cta2.author, cta2.displayorder,
       IFNULL(GROUP_CONCAT(DISTINCT CONCAT(a2.author_id),':/:',IFNULL(a2.firstname, '+NULL'),':/:',IFNULL(a2.forename, '+NULL'),':/:',IFNULL(a2.initials, '+NULL'),':/:',IFNULL(a2.middlename, '+NULL'),':/:',IFNULL(a2.lastname, '+NULL'),':/:',IFNULL(a2.suffix, '+NULL'),':/:',IFNULL(a2.misc, '+NULL'),':/:',IFNULL(a2.postal_address, '+NULL'),':/:',IFNULL(a2.affiliation, '+NULL'),':/:',IFNULL(a2.email, '+NULL'),':/:',IFNULL(a2.user, '+NULL') ORDER BY cta2.displayorder SEPARATOR '///'), '') AS _ct2_authors_packed,
       IFNULL(GROUP_CONCAT(DISTINCT CONCAT(t2.tag_id),':/:',IFNULL(t2.name, '+NULL') ORDER BY ubt2.created SEPARATOR '///'), '') AS _ub_tags_packed,
       COUNT(DISTINCT ub2.user_bookmark_id) as _ub_user_bookmarks_count,
       COUNT(DISTINCT c2.comment_id) as _ub_comments_count,
       COUNT(DISTINCT ub3.user_bookmark_id) as _ub_bookmark_is_linked_by_current_user,
       COUNT(DISTINCT t4.tag_id) as _ub_is_geotagged
FROM qq2 AS ubp
LEFT JOIN user_bookmark ub ON (ubp.user_bookmark_id=ub.user_bookmark_id)
LEFT JOIN user u ON (ub.user=u.user_id)
LEFT JOIN user_bookmark_tag ubt2 ON (ub.user_bookmark_id=ubt2.user_bookmark)
LEFT JOIN tag t2 ON (ubt2.tag=t2.tag_id)
LEFT JOIN user_bookmark_details ubd ON (ub.user_bookmark_id=ubd.user_bookmark_id)
LEFT JOIN citation ct ON (ub.citation=ct.citation_id)
LEFT JOIN citation_author cta ON (ct.citation_id=cta.citation)
LEFT JOIN author a ON (cta.author=a.author_id)
LEFT JOIN journal j ON (ct.journal=j.journal_id)
LEFT JOIN bookmark b ON (ub.bookmark=b.bookmark_id)
LEFT JOIN bookmark_details bd ON (b.bookmark_id=bd.bookmark_id)
LEFT JOIN citation ct2 ON (b.citation=ct2.citation_id)
LEFT JOIN citation_author cta2 ON (ct2.citation_id=cta2.citation)
LEFT JOIN author a2 ON (cta2.author=a2.author_id)
LEFT JOIN journal j2 ON (ct2.journal=j2.journal_id)
LEFT JOIN user_gang ug ON (u.user_id=ug.user)
LEFT JOIN gang g ON (ug.gang=g.gang_id)
LEFT JOIN bookmark b2 ON (ub.bookmark=b2.bookmark_id)
LEFT JOIN user_bookmark ub2 ON (b2.bookmark_id=ub2.bookmark AND ((((ub2.private = 0 AND ub2.private_gang IS NULL) OR ub2.private_gang IN (4,22,25) OR (ub2.private_until IS NOT NULL AND ub2.private_until <= NOW())) AND ub2.quarantined IS NULL) OR ub2.user = 978))
LEFT JOIN user_bookmark_comment ubc2 ON (ub2.user_bookmark_id=ubc2.user_bookmark)
LEFT JOIN comment c2 ON (ubc2.comment=c2.comment_id)
LEFT JOIN user_bookmark ub3 ON (ubc2.user_bookmark=ub3.user_bookmark_id AND ub3.user = 978)
LEFT JOIN user_bookmark_tag ubt4 ON (ub.user_bookmark_id=ubt4.user_bookmark)
LEFT JOIN tag t4 ON (ubt4.tag=t4.tag_id AND t4.name = 'geotagged')
WHERE ub.user_bookmark_id IS NOT NULL
GROUP BY ubp.user_bookmark_id
ORDER BY ub.created DESC;

SELECT   COUNT(*)
FROM     (SELECT   ubs.user_bookmark_id
          FROM     qq1 AS ubs
                   NATURAL JOIN user_bookmark ubo
          WHERE    ((((ubo.private = 0 AND ubo.private_gang IS NULL)
                      OR ubo.private_gang IN (4,22,25)
                      OR (ubo.private_until IS NOT NULL AND ubo.private_until <= NOW()))
                     AND ubo.quarantined IS NULL) OR ubo.user = ?)
          AND      ubo.user_bookmark_id IS NOT NULL) AS ubp
         LEFT JOIN user_bookmark ub ON (ubp.user_bookmark_id=ub.user_bookmark_id)
WHERE    ub.user_bookmark_id IS NOT NULL;

DROP TEMPORARY TABLE IF EXISTS qq1;
DROP TEMPORARY TABLE IF EXISTS qq2;
COMMIT;
