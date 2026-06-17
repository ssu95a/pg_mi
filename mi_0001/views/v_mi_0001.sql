CREATE OR REPLACE VIEW xxi.v_mi_0001
AS 
SELECT m.itm_id, 
       m.req_id, 
       m.created_at, 
       m.person_id, 
       m.icusnum, 
       m.inn,
       m.ires_code, 
       m.tres_time, 
       m.cres_info, 
       m.external_uuid item_uuid,
       p.last_name, 
       p.first_name, 
       p.middle_name, 
       p.birth_date, 
       p.birth_place,
       p.doc_type_id,
       p.doc_ser, 
       p.doc_num, 
       p.doc_issue_date,
       p.doc_issuer_code,
       p.doc_issuer_name
   FROM mi_0001 m
      INNER JOIN 
         mi_person p ON m.person_id = p.person_id
;
-- Comments
COMMENT ON VIEW xxi.v_mi_0001 is 
   'СМЭВ 3. Список запросов ИНН паспортов физ лиц. 12, 13 провайдеры $id: {4.0.0} {26.05.2026} Sulimoff$'
;