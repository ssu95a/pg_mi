--
-- Таблица    : xxi.mi_0007
-- Назначение : Элементы запросов паспорта физ лиц
-- Описание   : Запросы на валидность паспортов РФ
--
CREATE TABLE IF NOT EXISTS xxi.mi_0007 (
-- +------------------------------------------------------------------------------------
-- |   column      |  type      |   null  | default 
-- +------------------------------------------------------------------------------------
      itm_id        numeric(12)   NOT NULL   DEFAULT nextval('xxi.s_mi_item'::regclass),
      external_uuid uuid          NOT NULL   DEFAULT uuidv7(),
      req_id        numeric(12)   NOT NULL,
      
      person_id     numeric(12)   NOT NULL,
      
      created_at    timestamp     NOT NULL   DEFAULT current_timestamp,
   -- бизнес ответ на запрос
      message_uuid  uuid              NULL,

      ires_code     numeric(3)        NULL,
      tres_time     timestamptz       NULL,
      cres_info     text              NULL,
      -- код обработки при ошибке
      error_code    varchar(100)      NULL

-- constraints
-- PK
   CONSTRAINT pk_mi_0007 PRIMARY KEY (itm_id) using index tablespace indexes,
-- UK
   CONSTRAINT uk_0007_external_uuid UNIQUE (external_uuid) using index tablespace indexes,
-- FK      
   CONSTRAINT fk_mi_0007__req_id FOREIGN KEY (req_id   ) REFERENCES xxi.mi_req_id (req_id   ) ON DELETE CASCADE,
   CONSTRAINT fk_mi_0007__person FOREIGN KEY (person_id) REFERENCES xxi.mi_person (person_id)
)
TABLESPACE users
;
-- Indexes
CREATE INDEX IF NOT EXISTS fx_mi_0007__req_id ON xxi.mi_0007 USING btree ( req_id ) TABLESPACE indexes
;
CREATE INDEX IF NOT EXISTS fx_mi_0007__person_id ON xxi.mi_0007 USING btree ( person_id ) TABLESPACE indexes
;
-- Grants
ALTER TABLE xxi.mi_0007 owner to "XXI"
;
-- Comments
COMMENT ON TABLE xxi.mi_0007 is 
   'СМЭВ-3. Запросы валидности физ лиц $id: {3.1.0} {01.05.2026} Sulimoff$'
;
COMMENT ON COLUMN xxi.mi_0007.itm_id is 
   'ID элемента запроса'
;
COMMENT ON COLUMN xxi.mi_0007.req_id is 
   'ID запроса /mi_req/'
;
COMMENT ON COLUMN xxi.mi_0007.person_id is 
   'ID физ лица /mi_person/'
;
COMMENT ON COLUMN xxi.mi_0007.ires_code is 
   'Код результата из СМЭВ или -1 в случае ошибки при обработке элемента'
;
COMMENT ON COLUMN xxi.mi_0007.cres_info is 
   'Информация о результате'
;
COMMENT ON COLUMN xxi.mi_0007.tres_time is 
   'Дата/время получения результата'
;