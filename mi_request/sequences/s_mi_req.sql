-- Генератор ID для заголовков запроса в СМЭВ
-- Sulimoff, 12.03.26
CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_req START WITH 1 INCREMENT BY 1 MINVALUE 1 CACHE 50 NO CYCLE
;
ALTER SEQUENCE xxi.s_mi_req OWNER TO "XXI"
;