--
-- Таблица    : xxi.mi_0001
-- Назначение : Элементы запросов ИНН физ лиц
-- Описание   : Запросы на получения ИНН по данным физ лица
--
CREATE TABLE IF NOT EXISTS xxi.mi_0001 (
-- +---------------------------------------------------------------------------
-- |   column      |  type      |   null  | default 
-- +---------------------------------------------------------------------------
      itm_id        numeric(12)   NOT NULL  DEFAULT nextval('xxi.s_mi_item'::regclass),
      external_uuid uuid          NOT NULL  DEFAULT gen_random_uuid(),    
      req_id        numeric(12)   NOT NULL,
      person_id     numeric(12)   NOT NULL, 
      icusnum       numeric(12)   NOT NULL, 
      created_at    timestamp     NOT NULL  DEFAULT current_timestamp,
      inn           varchar(13)       NULL,      
      ires_code     numeric(3)        NULL,  
      tres_time     timestamp         NULL,  
      cres_info     text              NULL,

-- constraints
-- PK
   CONSTRAINT pk_mi_0001 PRIMARY KEY (itm_id) using index tablespace indexes,
-- UK
   CONSTRAINT uk_0001_external_uuid UNIQUE (external_uuid) using index tablespace indexes,
-- FK      
   CONSTRAINT fk_mi_0001__req_id FOREIGN KEY (req_id   ) REFERENCES xxi.mi_req_id (req_id   ) ON DELETE CASCADE,
   CONSTRAINT fk_mi_0001__person FOREIGN KEY (person_id) REFERENCES xxi.mi_person (person_id),
   CONSTRAINT fk_mi_0001__cus    FOREIGN KEY (icusnum  ) REFERENCES xxi."CUS" (icusnum)
)
TABLESPACE users
;
-- Indexes
CREATE INDEX IF NOT EXISTS fx_mi_0001__req_id ON xxi.mi_0001 USING btree ( req_id ) TABLESPACE indexes
;
CREATE INDEX IF NOT EXISTS fx_mi_0001__person_id ON xxi.mi_0001 USING btree ( person_id ) TABLESPACE indexes
;
CREATE INDEX IF NOT EXISTS fx_mi_0001__icusnum ON xxi.mi_0001 USING btree ( icusnum ) TABLESPACE indexes
;
-- Grants
ALTER TABLE xxi.mi_0001 owner to "XXI"
;
-- Comments
COMMENT ON TABLE xxi.mi_0001 is 
   'СМЭВ-3. Запрос cведений об ИНН физ лица $id: {4.0.0} {26.05.2026} Sulimoff$'
;
COMMENT ON COLUMN xxi.mi_0001.itm_id is 
   'ID элемента запроса'
;
COMMENT ON COLUMN xxi.mi_0001.req_id is 
   'ID запроса /mi_req/'
;
COMMENT ON COLUMN xxi.mi_0001.person_id is 
   'ID физ лица /mi_person/'
;
COMMENT ON COLUMN xxi.mi_0001.icusnum is 
   'ID клиента XXI /CUS/'
;
COMMENT ON COLUMN xxi.mi_0001.inn is 
   'Инн полученный в качестве ответа'
;
COMMENT ON COLUMN xxi.mi_0001.ires_code is 
   'Код результата из СМЭВ'
;
COMMENT ON COLUMN xxi.mi_0001.cres_info is 
   'Информация о результате'
;
COMMENT ON COLUMN xxi.mi_0001.tres_time is 
   'Дата/время получения результата'
;
COMMENT ON COLUMN xxi.mi_0001.inn is 
   'ИНН полученный из СМЭВ'
;
