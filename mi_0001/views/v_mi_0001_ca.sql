CREATE OR REPLACE VIEW xxi.v_mi_0001_ca
AS 
WITH q AS (
   SELECT
       x.icusnum,
       x.ccuslast_name,
       x.ccusfirst_name,
       x.ccusmiddle_name,
       x.dcusbirthday,
       x.dcusopen
   FROM xxi."CUS" x
   WHERE x.ccusnumnal IS NULL
     AND x.ccusflag IN ('1', '4')
     AND EXISTS ( SELECT 1 FROM xxi."ACC" a WHERE a.iacccus = x.icusnum AND a.caccprizn = 'О' )
)
SELECT
    x.icusnum,
    x.ccuslast_name   AS last_name,
    x.ccusfirst_name  AS first_name,
    x.ccusmiddle_name AS middle_name,
    x.dcusbirthday    AS birth_date,
    NULL::varchar     AS birth_place,
    d.doc_ser,
    d.doc_num,
    to_number(pud.cpudcode9) 
                      AS doc_type_code,
    d.doc_date        AS doc_issue_date,
    d.doc_agency      AS doc_issuer_name,
    d.doc_subdiv      AS doc_issuer_code,
    pud.cpuddoc       AS doc_type_name,
    x.dcusopen
FROM q x JOIN LATERAL (
   SELECT
       d.id_doc_tp,
       d.doc_ser,
       d.doc_num,
       d.doc_date,
       d.doc_agency,
       d.doc_subdiv
   FROM xxi.cus_docum d
   WHERE d.icusnum = x.icusnum
     AND (d.doc_period IS NULL OR d.doc_period <= current_date)
   ORDER BY
       CASE
          WHEN d.pref = 'Y' THEN current_date + 10
          ELSE d.doc_date
       END 
          DESC NULLS LAST,
       d.id_doc
   LIMIT 1
) d ON TRUE
JOIN xxi.pud
  ON pud.ipudid = d.id_doc_tp
 AND pud.cpudcode9 IS NOT NULL
;
-- Comments
COMMENT ON VIEW xxi.v_mi_0001_ca is 
   'СМЭВ 3. Список клиентов без ИНН, по которым не было запросов в СМЭВ $id: {3.0.0} {29.05.2026} Sulimoff$'
;
-- Grants
grant select on xxi.v_mi_0001_ca to odb
;