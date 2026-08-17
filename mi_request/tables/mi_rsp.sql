--
-- Таблица    : xxi.mi_rsp
-- Назначение : Реестр ответов на запросы в модулях 
-- Описание   : Хранит все заголовки ответов + свзь с запросов.
-- Версия     : 0.1, 16.08.2026
-- 
CREATE TABLE IF NOT EXISTS xxi.mi_rsp
(
-- +---------------------------------------------------------------------------
-- |     column     |    type    |    null   | default 
-- +---------------------------------------------------------------------------
      rsp_id        numeric(12)  not null      default nextval('xxi.s_mi_rsp'::regclass),
      req_id        numeric(12)  not null,
      itm_id        numeric(12)  not null,

      rsp_uuid      uuid         not null      default uuidv7(),

      category_cd   varchar(50)  not null,
      result_code   varchar(100) not null,
      result_info   text,

      payload       jsonb,

      status_cd     numeric(3)   not null default 0,

      created_at    timestamptz  not null default current_timestamp,
      sent_at       timestamptz,

-- Constraints:
-- PK
   CONSTRAINT pk_mi_rsp 
      PRIMARY KEY (rsp_id) 
         USING INDEX TABLESPACE indexes,

-- FK
   CONSTRAINT fk_mi_rsp__mi_req_id
      FOREIGN KEY (req_id) 
         REFERENCES xxi.mi_req_id(req_id) 
            ON DELETE CASCADE,

-- Check
-- Статус ответа
   CONSTRAINT ck_mi_rsp__status_cd
      CHECK ( status_cd in ( 0, 1, 2,-1) )
)
TABLESPACE users
;
create index if not exists ix_mi_rsp__req_itm
   on xxi.mi_rsp(req_id, itm_id)
      tablespace indexes
;
create unique index if not exists ux_mi_rsp__rsp_uuid
   on xxi.mi_rsp(rsp_uuid)
      tablespace indexes
;
create index if not exists ix_mi_rsp__ready
   on xxi.mi_rsp(created_at, rsp_id)
      tablespace indexes
         where status_cd = 1
;
-- Owner
ALTER TABLE xxi.mi_rsp OWNER TO "XXI"
;
-- Comments
COMMENT ON TABLE xxi.mi_rsp IS
   'Ответы на запросы'
;
