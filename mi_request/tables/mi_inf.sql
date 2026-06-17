--
-- Таблица    : xxi.mi_inf
-- Назначение : Виды сведений СМЭВ
-- Описание   : Реестр видов сведений, настройки
--
CREATE TABLE IF NOT EXISTS xxi.mi_inf 
(
-- +---------------------------------------------------------------------------
-- | column        | type        | null      | default 
-- +---------------------------------------------------------------------------
      inf_id          numeric(6)   NOT NULL,
      wsp_id          numeric(3)   NOT NULL,

      initiator_cd    numeric(1)   NOT NULL    Default -1,
      
      name_inf        varchar(250) NOT NULL,
      name_official   varchar(500) NOT NULL,
      namespace_inf   varchar(200)     NULL,

      gate_alias      varchar(50)      NULL, 

      request_queue   varchar(255)     NULL, 
      response_queue  varchar(255)     NULL, 
      request_ttl_ms  numeric(12)      NULL,
      response_ttl_ms numeric(12)      NULL,

      url_doc         varchar(500)     NULL,
      
      note            text             NULL,
      
      audit_on        boolean      NOT NULL  DEFAULT false,
-- Constraints      
-- PK
      CONSTRAINT pk_mi_inf PRIMARY KEY (inf_id) USING INDEX TABLESPACE indexes,
-- FK      
      CONSTRAINT fk_mi_inf__mi_wsp FOREIGN KEY (wsp_id) REFERENCES xxi.mi_wsp(wsp_id) ON DELETE RESTRICT,
-- Check
-- Имена очередей
      CONSTRAINT ck_queue_names CHECK (
         request_queue is null or ( request_queue  ~ '^[a-zA-Z0-9\._\-:]+$' AND request_queue  !~* '^amq\.' )
         AND
         response_queue is null or ( response_queue ~ '^[a-zA-Z0-9\._\-:]+$'AND response_queue !~* '^amq\.' )
      ),
      CONSTRAINT ck_timeouts_positive CHECK (
         ( request_ttl_ms IS NULL OR request_ttl_ms > 0 )
         AND
         ( response_ttl_ms IS NULL OR response_ttl_ms > 0 )
      ),      
-- Инициатор
   CONSTRAINT ck_mi_req__initiator_cd
        CHECK ( initiator_cd in ( 1, -1) )
)
TABLESPACE users
;
-- Indexes
CREATE INDEX IF NOT EXISTS fx_mi_inf__wsp_id ON xxi.mi_inf USING BTREE (wsp_id)
;
-- Owner
ALTER TABLE xxi.mi_inf OWNER TO "XXI";
-- Table comment
COMMENT ON TABLE xxi.mi_inf is 
   'СМЭВ-3. Виды сведений $id: {3.1.0} {19.03.2026} Sulimoff$'
;
-- Columns comments
COMMENT ON COLUMN xxi.mi_inf.inf_id is 
   'ID вида сведений'
;
COMMENT ON COLUMN xxi.mi_inf.wsp_id is 
   'АРМ вида сведений /mi_wsp/'
;
COMMENT ON COLUMN xxi.mi_inf.initiator_cd is 
   'Иницатор запросов -1 АБС, +1 СМЭВ'
;
COMMENT ON COLUMN xxi.mi_inf.name_inf is 
   'Наименование вида сведений'
;
COMMENT ON COLUMN xxi.mi_inf.name_official is 
   'Наименование вида сведений офиициальное, с сайта СМЭВ'
;
COMMENT ON COLUMN xxi.mi_inf.namespace_inf is 
   'Namespace вида сведений, с сайта СМЭВ'
;
COMMENT ON COLUMN xxi.mi_inf.url_doc is 
   'Ссылка на документацию (ЛКУВ)'
;
COMMENT ON COLUMN xxi.mi_inf.note is 
   'Примечание'
;
