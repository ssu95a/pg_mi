CREATE OR REPLACE VIEW xxi.v_mi_0007
AS 
SELECT m.itm_id, 
       m.req_id, 
       m.created_at, 
       m.person_id, 
       m.ires_code, 
       m.tres_time, 
       m.cres_info, 
       m.external_uuid,
       p.icusnum, 
       p.last_name, 
       p.first_name, 
       p.middle_name, 
       p.birth_date, 
       p.doc_issue_date, 
       p.doc_ser, 
       p.doc_num, 
       p.doc_type_id,
       p.region_code   
   FROM mi_0007 m
       INNER JOIN 
         mi_person p ON m.person_id = p.person_id
;
-- Comments
COMMENT ON VIEW xxi.v_mi_0007 is 
   'СМЭВ 3. Список запросов Валидации паспортов физ лиц,74, 75 провайдеры $id: {3.1.0} {24.03.2026} Sulimoff$';