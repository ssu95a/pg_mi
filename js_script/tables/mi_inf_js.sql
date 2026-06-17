--
-- Таблица    : xxi.mi_inf_js
-- Назначение : JS скрипты для реализации логики вида сведения
-- Описание   : Хранятся скрипты на JavaScript, где возможно реализовать логику работы с ВС
--
CREATE TABLE IF NOT EXISTS xxi.mi_inf_js (
-- +---------------------------------------------------------------------------
-- |   column   |  type       |   null   | default 
-- +---------------------------------------------------------------------------
     inf_id       numeric(6)    not null, 
     js_type      numeric(3)    not null, 
     name         varchar(100)  not null, 
     note         text              null,
     ts_body      timestamp     not NULL   DEFAULT current_timestamp,
     js_body      text          not null,
-- Constraints
-- PK
    CONSTRAINT pk_mi_inf_js
        PRIMARY KEY (inf_id, js_type)
            USING INDEX TABLESPACE indexes,
-- FK
-- FK на mi_inf.
   CONSTRAINT fk_mi_inf_js__mi_inf
      FOREIGN KEY(inf_id) REFERENCES xxi.mi_inf (inf_id)
         ON DELETE CASCADE
)
   tablespace users
;   
-- Grants
ALTER TABLE xxi.mi_inf_js OWNER TO "XXI"
;
-- Comments
COMMENT ON TABLE xxi.mi_inf_js IS 
    'СМЭВ-3. JS скрипты для реализации логики вида сведения'
;
COMMENT ON COLUMN xxi.mi_inf_js.inf_id IS 
    'Вид сведения /mi_inf/'
;
COMMENT ON COLUMN xxi.mi_inf_js.js_type IS 
    'Тип скрипта - подготовка, обработка и тд. на форме раскрывается через enum'
;
COMMENT ON COLUMN xxi.mi_inf_js.name IS 
    'Наименование'
;
COMMENT ON COLUMN xxi.mi_inf_js.note IS 
    'Примечание'
;
COMMENT ON COLUMN xxi.mi_inf_js.js_body IS 
    'Тело скрипта'
;
COMMENT ON COLUMN xxi.mi_inf_js.ts_body IS 
    'Дата/время последнего изменения тела скрипта. Устанавливается в триггере'
;