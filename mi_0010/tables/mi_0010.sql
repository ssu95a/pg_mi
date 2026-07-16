--
-- Таблица    : xxi.mi_0010
-- Назначение : ЕГР ЗАГС
-- Описание   : Сведения в кредитные организации о снятии с учета в налоговом органе физического лица 
--             - владельца счета на основании сведений о смерти
--
CREATE TABLE IF NOT EXISTS xxi.mi_0010 (
-- +---------------------------------------------------------------------------
-- |   column      |  type      |   null  | default 
-- +---------------------------------------------------------------------------
      itm_id        numeric(12)   NOT NULL  DEFAULT nextval('xxi.s_mi_item'::regclass),
      external_uuid uuid          NOT NULL  DEFAULT uuidv7(),
      req_id        numeric(12)   NOT NULL,

      created_at    timestamp     NOT NULL  DEFAULT current_timestamp,

      person_id     numeric(12)   NOT NULL,
      icusnum       numeric(12)       NULL,

      rec_num       varchar(22)       NULL,
      rec_date      date              NULL,

      zags_code     varchar(8)        NULL,
      zags_name     varchar(1000)     NULL,

      dereg_date    date              null,

      ipr_dbth      numeric(1)        null, 
      ipr_ddth      numeric(1)        null, 
      ipr_cus17     numeric(1)        null, 
      
      ires_code     numeric(3)        NULL,
      tres_time     timestamp         NULL,
      cres_info     text              NULL,

      message_uuid  uuid              NULL,
      -- код обработки при ошибке
      error_code    varchar(100)      NULL,

-- constraints
-- PK
   CONSTRAINT pk_mi_0010 PRIMARY KEY (itm_id) using index tablespace indexes,

-- UK
   CONSTRAINT uk_0010_external_uuid UNIQUE (external_uuid) using index tablespace indexes,

-- FK
   CONSTRAINT fk_mi_0010__req_id FOREIGN KEY (req_id   ) REFERENCES xxi.mi_req_id (req_id   ) ON DELETE CASCADE,
   CONSTRAINT fk_mi_0010__person FOREIGN KEY (person_id) REFERENCES xxi.mi_person (person_id),
   CONSTRAINT fk_mi_0010__cus    FOREIGN KEY (icusnum  ) REFERENCES xxi."CUS" (icusnum),

-- CK
   constraint CH_IPRD_CUS17 check( IPR_CUS17 IN (0, 1 )),
   constraint CH_IPRD_DBTH  check( IPR_DBTH  IN (1,2,3)),
   constraint CH_IPRD_DDTH  check( IPR_DDTH  IN (1,2,3))
)
TABLESPACE users
;

-- Indexes
CREATE INDEX IF NOT EXISTS fx_mi_0010__req_id ON xxi.mi_0010 USING btree ( req_id ) TABLESPACE indexes
;
CREATE INDEX IF NOT EXISTS fx_mi_0010__person_id ON xxi.mi_0010 USING btree ( person_id ) TABLESPACE indexes
;
CREATE INDEX IF NOT EXISTS fx_mi_0010__icusnum ON xxi.mi_0010 USING btree ( icusnum ) TABLESPACE indexes
;
CREATE INDEX IF NOT EXISTS ix_mi_0010__message_uuid ON xxi.mi_0010 (message_uuid) TABLESPACE indexes WHERE message_uuid IS NOT NULL
;
-- Grants
ALTER TABLE xxi.mi_0010 owner to "XXI"
;

-- Comments
COMMENT ON TABLE xxi.mi_0010 is 
   'СМЭВ-3. Сведения о смерти физ лица. $id: {1.0.0} {15.07.2026} Sulimoff$'
;
COMMENT ON COLUMN xxi.mi_0010.itm_id is 
   'ID элемента запроса'
;
COMMENT ON COLUMN xxi.mi_0010.req_id is 
   'ID запроса /mi_req/'
;
COMMENT ON COLUMN xxi.mi_0010.person_id is 
   'ID физ лица /mi_person/'
;
COMMENT ON COLUMN xxi.mi_0010.icusnum is 
   'ID клиента XXI /CUS/'
;
COMMENT ON COLUMN xxi.mi_0010.ires_code is 
   'Код результата из СМЭВ'
;
COMMENT ON COLUMN xxi.mi_0010.cres_info is 
   'Информация о результате'
;
COMMENT ON COLUMN xxi.mi_0010.tres_time is 
   'Дата/время получения результата'
;
COMMENT ON COLUMN xxi.mi_0010.message_uuid is 
   'ID сообщения из MI, где был обработан элемент'
;
COMMENT ON COLUMN xxi.mi_0010.rec_num is 
   'Номер записи'
;
comment on column xxi.mi_0010.rec_date is 
   'Дата записи'
;
comment on column xxi.mi_0010.zags_code is 
   'Код ЗАГС'
;
comment on column xxi.mi_0010.zags_name is
   'Название ЗАГС'
;
comment on column xxi.mi_0010.dereg_date is
   'Дата снятия с учета'
;
comment on column xxi.mi_0010.ipr_dbth is
   'Признак полноты даты рождения - 1 - год рождения, 2 - месяц и год рождения, 3 - полная дата'
;
comment on column xxi.mi_0010.ipr_ddth is
   'Признак полноты даты смерти - 1 - год рождения, 2 - месяц и год рождения, 3 - полная дата'
;
comment on column xxi.mi_0010.ipr_cus17 is
   'Признак обновления данных по 17 связи - 0 - нет, 1 - да'
;