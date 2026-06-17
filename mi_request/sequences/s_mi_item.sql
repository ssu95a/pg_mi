-- Генерация ID для элементов запроса
CREATE SEQUENCE IF NOT EXISTS xxi.s_mi_item START WITH 1 INCREMENT BY 1 MINVALUE 1 CACHE 50 NO CYCLE
;
ALTER SEQUENCE xxi.s_mi_item owner to "XXI"
;