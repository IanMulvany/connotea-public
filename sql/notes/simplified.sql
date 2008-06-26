table abbrevs same as official connotea queries (pre-user_article)
select clause abbrevs more user-friendly
some select clause fields joined, etc to be user-friendly, and not necessarily same as connotea, or even complete (e.g. pages, author names)
some select clause fields dropped

SELECT u.username AS u_username,
       b.url AS b_url, b.hash AS b_hash,
       GROUP_CONCAT(DISTINCT t2.name ORDER BY ubt2.created SEPARATOR ',') AS ub_tags,
       ub.created AS ub_created,
       IF(ub.user_is_author,'Y','N') as ub_user_is_author,
       bd.title AS b_title,
       ubd.title AS ub_title, ubd.description AS ub_description,
     # user citation:
       ct.title AS uc_title,
       IF(j.name, j.name, j.medline_ta) AS uc_j_name,
       ct.volume AS uc_volume, ct.issue AS uc_issue,
       IF(ct.start_page, CONCAT_WS('-', ct.start_page, ct.end_page), NULL) AS uc_pages,
       ct.pubmed AS uc_pubmed, ct.doi AS uc_doi, ct.asin AS uc_asin, ct.ris_type AS uc_ris_type,
       ct.date AS uc_date, ct.raw_date AS uc_raw_date, ct.last_modified_date AS uc_last_mod_date,
       IF(COUNT(cta.citation), GROUP_CONCAT(DISTINCT IF(a.misc, a.misc, CONCAT_WS(' ', IF(a.firstname, a.firstname, a.forename), a.lastname)) ORDER BY cta.displayorder SEPARATOR ', '), NULL) AS uc_authors,
     # authoritative citation:
       ct2.title AS ac_title,
       IF(j2.name, j2.name, j2.medline_ta) AS ac_j_name,
       ct2.volume AS ac_volume, ct2.issue AS ac_issue,
       IF(ct2.start_page, CONCAT_WS('-', ct2.start_page, ct2.end_page), NULL) AS ac_pages,
       ct2.pubmed AS ac_pubmed, ct2.doi AS ac_doi, ct2.asin AS ac_asin, ct2.ris_type AS ac_ris_type,
       ct2.date AS ac_date, ct2.raw_date AS ac_raw_date, ct2.last_modified_date AS ac_last_mod_date,
       IF(COUNT(cta2.citation), GROUP_CONCAT(DISTINCT IF(a2.misc, a2.misc, CONCAT_WS(' ', IF(a2.firstname, a2.firstname, a2.forename), a2.lastname)) ORDER BY cta2.displayorder SEPARATOR ', '), NULL) AS ac_authors
FROM (SELECT user_bookmark_id FROM user_bookmark WHERE def_public=1 LIMIT 1000) as ubp
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
WHERE ub.user_bookmark_id IS NOT NULL
GROUP BY ub.user_bookmark_id
ORDER BY ub.created DESC;

