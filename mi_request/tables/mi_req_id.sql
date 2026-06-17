--
-- Object   : xxi.mi_req_id
-- Purpose  : Глобальный реестр req_id.
-- Note     : Эмулирует "глобальный уникальный индекс" для req_id
--
CREATE TABLE IF NOT EXISTS xxi.mi_req_id (
   
   req_id numeric(12) not null 
      default nextval('xxi.s_mi_req'::regclass),

   created_at timestamp with time zone not null
      default clock_timestamp(),

-- Constraints
-- PK
   CONSTRAINT pk_mi_req_id PRIMARY KEY (req_id) USING INDEX TABLESPACE indexes
)
TABLESPACE indexes
;
-- Owner
ALTER TABLE xxi.mi_req_id OWNER TO "XXI"
;
-- Comments
COMMENT ON TABLE xxi.mi_req_id is
   'Глобальный реестр идентификаторов запросов. Используется как якорь для FK по req_id.';

COMMENT ON COLUMN xxi.mi_req_id.req_id is
   'Глобально уникальный идентификатор запроса';

COMMENT ON COLUMN xxi.mi_req_id.created_at is
   'Дата и время резервирования req_id';
