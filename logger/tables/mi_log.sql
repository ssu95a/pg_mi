--
-- Таблица    : xxi.mi_log
-- Назначение : Техническая debug-трасса MI для разработчиков
-- Описание   : Не аудит. Может чиститься, отключаться, теряться при crash.
--
CREATE UNLOGGED TABLE IF NOT EXISTS xxi.mi_log
(
-- +---------------------------------------------------------------------------
-- | column        | type         | null    | default 
-- +---------------------------------------------------------------------------
        log_id        numeric(38)   NOT NULL   DEFAULT nextval('xxi.s_mi_log'::regclass),

        inf_id        numeric(6)    NOT NULL,
        wsp_id        numeric(3)    NOT NULL,

        logged_at     timestamptz   NOT NULL   DEFAULT clock_timestamp(),

        -- Ссылка на сессию системного аудита
        au_session_id numeric(38)   NOT NULL,

        level_cd      bpchar(3)     NOT NULL,

        logger_name   varchar(50),

        action_cd     varchar(50),
        object_name   varchar(100),

        -- Смысловой контекст события:
        -- sqlstate, exception name, correlation_id, бизнес-ключ, номер счёта и т.п.
        context_value varchar(100),

        message_text  varchar(2000),
        details_text  text,

        req_id        numeric(12),
        itm_id        numeric(12),
        rsp_id        numeric(12),

        person_id     numeric(12),
        icusnum       numeric(12),

        object_id     numeric(12),
        object_id2    numeric(12),

        -- Ссылка на родительскую запись лога
        parent_id     numeric(38)
)
PARTITION BY LIST (wsp_id)
;

-- Partitions
CREATE UNLOGGED TABLE IF NOT EXISTS xxi.mi_log_1
    PARTITION OF xxi.mi_log
        FOR VALUES IN (1)
            TABLESPACE USERS
;
CREATE UNLOGGED TABLE IF NOT EXISTS xxi.mi_log_7
    PARTITION OF xxi.mi_log
        FOR VALUES IN (7)
            TABLESPACE USERS
;
CREATE UNLOGGED TABLE IF NOT EXISTS xxi.mi_log_3
    PARTITION OF xxi.mi_log
        FOR VALUES IN (3)
            TABLESPACE USERS
;
CREATE UNLOGGED TABLE IF NOT EXISTS xxi.mi_log_23
   PARTITION OF xxi.mi_log
      FOR VALUES IN (23)
         TABLESPACE USERS
;
-- Партиция по умолчанию
CREATE UNLOGGED TABLE IF NOT EXISTS xxi.mi_log_0
    PARTITION OF xxi.mi_log
        DEFAULT
            TABLESPACE USERS
;

-- Indexes
-- Индексы на parent создадут соответствующие индексы на partitions
CREATE INDEX IF NOT EXISTS ix_mi_log__log_id ON xxi.mi_log (log_id) TABLESPACE INDEXES
;
CREATE INDEX IF NOT EXISTS ix_mi_log__logged_at ON xxi.mi_log (logged_at) TABLESPACE INDEXES
;
CREATE INDEX IF NOT EXISTS ix_mi_log__req_itm_id ON xxi.mi_log(req_id,itm_id) TABLESPACE INDEXES
;
CREATE INDEX IF NOT EXISTS ix_mi_log__person_id ON xxi.mi_log (person_id) TABLESPACE INDEXES
;
CREATE INDEX IF NOT EXISTS ix_mi_log__audit_session_id ON xxi.mi_log (au_session_id) TABLESPACE INDEXES
;
CREATE INDEX IF NOT EXISTS ix_mi_log__logger_name_logged_at ON xxi.mi_log (logger_name, logged_at) TABLESPACE INDEXES
;
CREATE INDEX IF NOT EXISTS ix_mi_log__parent_id ON xxi.mi_log (parent_id) TABLESPACE INDEXES
;

-- Comments
COMMENT ON TABLE xxi.mi_log IS
   'Техническая debug-трасса MI для разработчиков. Не является аудитом. Может очищаться и отключаться.'
;

COMMENT ON COLUMN xxi.mi_log.log_id IS
   'Идентификатор записи debug-лога'
;
COMMENT ON COLUMN xxi.mi_log.inf_id IS
   'Идентификатор вида сведений'
;
COMMENT ON COLUMN xxi.mi_log.wsp_id IS
   'Идентификатор АРМ/контейнера'
;
COMMENT ON COLUMN xxi.mi_log.logged_at IS
   'Дата и время события'
;
COMMENT ON COLUMN xxi.mi_log.au_session_id IS
   'Идентификатор сессии системного аудита'
;
COMMENT ON COLUMN xxi.mi_log.level_cd IS
    'Уровень логирования: trc, dbg, inf, wrn, err'
;
COMMENT ON COLUMN xxi.mi_log.logger_name IS
    'Имя логгера / пакета / компонента'
;
COMMENT ON COLUMN xxi.mi_log.context_value IS
    'Смысловой контекст события: sqlstate, exception name, correlation_id, бизнес-ключ и т.п.'
;
COMMENT ON COLUMN xxi.mi_log.object_name IS
    'Объект, связанный с событием'
;
COMMENT ON COLUMN xxi.mi_log.action_cd IS
    'Действие, связанное с событием'
;
COMMENT ON COLUMN xxi.mi_log.message_text IS
    'Краткий текст события'
;
COMMENT ON COLUMN xxi.mi_log.details_text IS
    'Детали события'
;
COMMENT ON COLUMN xxi.mi_log.req_id IS
    'Идентификатор запроса'
;
COMMENT ON COLUMN xxi.mi_log.itm_id IS
   'Идентификатор элемента запроса'
;
COMMENT ON COLUMN xxi.mi_log.rsp_id IS
   'Id ответа на запрос'
;
COMMENT ON COLUMN xxi.mi_log.person_id IS
    'Идентификатор физлица'
;
COMMENT ON COLUMN xxi.mi_log.icusnum IS
    'Идентификатор клиента CRM'
;
COMMENT ON COLUMN xxi.mi_log.object_id IS
    'Технический идентификатор объекта'
;
COMMENT ON COLUMN xxi.mi_log.object_id2 IS
    'Технический идентификатор объекта 2'
;
COMMENT ON COLUMN xxi.mi_log.parent_id IS
    'Ссылка на родительскую запись debug-лога'
;