--
-- Таблица    : xxi.mi_req
-- Назначение : Реестр запросов в модули СМЭВ
-- Описание   : Хранит все заголовки запросов. Исходник для VIEW по видам сведений. Партицированная по inf_id. Нет PK!
-- Версия     : 0.9, 13.07.2026
-- 
CREATE TABLE IF NOT EXISTS xxi.mi_req (
-- +---------------------------------------------------------------------------
-- |     column     |    type    |    null   | default 
-- +---------------------------------------------------------------------------
      req_id         numeric(12)   NOT NULL,
      external_uuid  uuid          NOT NULL   DEFAULT uuidv7(),
      inf_id         numeric(6)    NOT NULL,
      created_at     timestamp     NOT NULL   DEFAULT current_timestamp,
      correlation_id uuid          NOT NULL,
      status_cd      numeric(3)    NOT NULL   DEFAULT 0,
      stage_cd       numeric(3)        NULL,
      idsmr          varchar(3)    NOT NULL   DEFAULT sys_context('B21'::character varying, 'IDSmr'::character varying),
      note           text              NULL, 
      ctaxreq_id     varchar(50)       NULL,
      itype          numeric(3)        NULL,
      i1             numeric(3)        NULL, 
      i2             numeric(3)        NULL,
      i3             numeric(3)        NULL,
      result_code    varchar(100)      NULL,
      result_info    varchar(300)      NULL,
      result_time    timestamp         NULL,
      message_uuid   uuid              NULL,
      original_request_uuid
                     uuid              NULL

-- Constraints:
-- FK
   CONSTRAINT fk_mi_req__req_id
      FOREIGN KEY (req_id)
         REFERENCES xxi.mi_req_id(req_id)
            ON DELETE CASCADE,

   CONSTRAINT fk_mi_req__mi_inf
      FOREIGN KEY (inf_id)
        REFERENCES mi_inf(inf_id),

   CONSTRAINT fk_mi_req__smr
      FOREIGN KEY (idsmr)
         REFERENCES "SMR"(idsmr),
-- Check
-- Статус запроса
   CONSTRAINT ck_mi_req__status_cd
      CHECK ( status_cd in ( 0, 1, 2, 3, -1) )
)
PARTITION 
   BY LIST (inf_id);

-- Indexes
-- FK на req_Id
create index IF NOT EXISTS fx_mi_req__req_id
   on xxi.mi_req (req_id)
      tablespace indexes
;
create index IF NOT EXISTS ix_mi_req__correlation_id
   on xxi.mi_req (correlation_id)
      tablespace indexes
;
create index IF NOT EXISTS ix_mi_req__inf_id_created_at
   on xxi.mi_req (inf_id, created_at)
      tablespace indexes
;
CREATE INDEX IF NOT EXISTS ix_mi_req__inf_ctaxreq 
   ON xxi.mi_req( inf_id, ctaxreq_id ) 
      TABLESPACE indexes
;
create index IF NOT EXISTS ix_mi_req__external_uuid
   on xxi.mi_req (external_uuid)
      tablespace indexes
;
create index if not exists ix_mi_req__original_request_uuid
   on xxi.mi_req(original_request_uuid)
      tablespace indexes
         where original_request_uuid is not null
;

-- Partitions
-- Валидация физ лиц
create table IF NOT EXISTS xxi.mi_req_0007
   partition of xxi.mi_req
      FOR VALUES IN ( 71, 72, 73, 74, 75 )
          TABLESPACE USERS
;
-- ГИС ГМП - отправка
create table IF NOT EXISTS xxi.mi_req_0006
   partition of xxi.mi_req
      FOR VALUES IN ( 61 )
          TABLESPACE USERS
;
-- Доходы физ лиц
create table IF NOT EXISTS xxi.mi_req_0008
   partition of xxi.mi_req
      FOR VALUES IN ( 8 )
          TABLESPACE USERS
;
-- ИНН физ лиц
create table IF NOT EXISTS xxi.mi_req_0001
   partition of xxi.mi_req
      FOR VALUES IN ( 12, 13 )
          TABLESPACE USERS
;
-- ЗАГС
create table IF NOT EXISTS xxi.mi_req_0010
   partition of xxi.mi_req
      FOR VALUES IN ( 10 )
          TABLESPACE USERS
;
-- default
create table IF NOT EXISTS xxi.mi_req_default
   partition of xxi.mi_req
      default
         TABLESPACE users
;
-- Owner
ALTER TABLE xxi.mi_req OWNER TO "XXI"
;
-- Comments
COMMENT ON TABLE xxi.mi_req IS
   'Общий заголовок запросов. Партиционируется по inf_id.'
;
COMMENT ON COLUMN xxi.mi_req.inf_id is
   'Идентификатор вида сведений. Ключ партицирования /mi_inf/'
;
COMMENT ON COLUMN xxi.mi_req.req_id is
   'Идентификатор запроса из xxi.mi_req_id'
;
COMMENT ON COLUMN xxi.mi_req.created_at is
   'Дата и время создания заголовка запроса'
;
COMMENT ON COLUMN xxi.mi_req.correlation_id is
   'Корреляционный идентификатор запроса'
;
COMMENT ON COLUMN xxi.mi_req.status_cd is
   'Статус запроса: 0=new, 1=done, 2=in_work, 3=sent, -1=error'
;
COMMENT ON COLUMN xxi.mi_req.idsmr is
   'Идентификатор IDSMR'
;
COMMENT ON COLUMN xxi.mi_req.ctaxreq_id is
   'Идентификатор запроса из ФНС, там где нужен'
;
COMMENT ON COLUMN xxi.mi_req.external_uuid is
   'Внешний глобальный идентификатор запроса'
;
COMMENT ON COLUMN xxi.mi_req.stage_cd is
   'Фаза/стадия запроса'
;
COMMENT ON COLUMN xxi.mi_req.result_code is
   'Код результата операции'
;
COMMENT ON COLUMN xxi.mi_req.result_info is
   'Инорфмация о результате'
;
COMMENT ON COLUMN xxi.mi_req.result_time is
   'Дата время получения информации'
;
COMMENT ON COLUMN xxi.mi_req.message_uuid is
   'ИД сообщения MI на который сформирован запрос или получен ответ'
;
COMMENT ON COLUMN xxi.mi_req.original_request_uuid IS
   'ID исходного запроса в MI для входящих business-запросов MI -> XXL -> XXI';
