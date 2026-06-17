--
-- Таблица    : xxi.mi_person
-- Назначение : Клиенты
-- Описание   : Реестр клиентов Физ лиц, используемых в модуле СМЭВ
--
CREATE TABLE IF NOT EXISTS xxi.mi_person
(
    person_id          numeric(12,0) NOT NULL DEFAULT nextval('xxi.s_mi_person'::regclass),
    icusnum            numeric,

    created_at         timestamp NOT NULL DEFAULT current_timestamp,

    first_name         varchar(50),
    last_name          varchar(50),
    middle_name        varchar(50),

    first_name_lat     varchar(50),
    last_name_lat      varchar(50),
    middle_name_lat    varchar(50),

    gender_id          numeric(1),

    ctzn_type_id       numeric(1),
    ctzn_country_code  varchar(10),

    inn                varchar(13),
    snils              varchar(20),

    doc_type_id        numeric(3),
    doc_type_code      varchar(20),
    doc_ser            varchar(10),
    doc_num            varchar(20),
    doc_issue_date     date,
    doc_issuer_code    varchar(20),
    doc_expire_date    date,
    doc_issuer_name    varchar(500),
    doc_invalid_from   date,

    birth_date         date,
    birth_date_raw     varchar(20),
    birth_place        varchar(500),

    death_date         date,

    phone              varchar(20),
    email              varchar(100),

    region_code        varchar(2),

    coid               varchar(100),

-- Constraints
-- PK
    CONSTRAINT pk_mi_person
        PRIMARY KEY (person_id)
            USING INDEX TABLESPACE indexes,
-- FK
-- FK на CUS.
-- ON DELETE SET NULL оставляет локальную персону жить автономно, если запись в CUS удалена.
    CONSTRAINT fk_mi_person__cus 
        FOREIGN KEY(icusnum) REFERENCES xxi."CUS" (icusnum)
        ON DELETE 
           SET NULL,
-- Check
    -- дата смерти больше даты рождения        
    CONSTRAINT ck_mi_person__death_date
         CHECK( death_date IS NULL OR birth_date IS NULL OR death_date >= birth_date  ),

    -- дата ДУЛ до, больше даты выдачи ДУЛ     
    CONSTRAINT ck_mi_person__doc_expire_date
         CHECK( doc_expire_date IS NULL OR doc_issue_date IS NULL OR doc_expire_date >= doc_issue_date ),

    -- дата ДУЛ отмены, больше даты выдачи ДУЛ     
    CONSTRAINT ck_mi_person__doc_invalid_from
         CHECK( doc_invalid_from IS NULL OR doc_issue_date IS NULL OR doc_invalid_from >= doc_issue_date  )
)
TABLESPACE users
;

-- Grants
ALTER TABLE xxi.mi_person OWNER TO "XXI"
;

-- bind SEQUENCE
ALTER SEQUENCE xxi.s_mi_person OWNED BY xxi.mi_person.person_id

-- Indexes
-- Поиск по ФИО + документу, как в оракле
CREATE INDEX IF NOT EXISTS ix_mi_person__doc_fio ON xxi.mi_person USING btree
(
   doc_type_id,
   replace(doc_num, ' ', ''),
   replace(doc_ser, ' ', ''),
   upper(last_name),
   upper(first_name)
)
TABLESPACE indexes;
-- Для fk_mi_person__cus
CREATE INDEX IF NOT EXISTS fx_mi_person__icusnum ON xxi.mi_person USING btree
(
    icusnum
)
TABLESPACE indexes;

-- Comments
COMMENT ON TABLE xxi.mi_person IS 
    'СМЭВ-3. Данные физ лиц'
;
COMMENT ON COLUMN xxi.mi_person.person_id IS 
    'ID записи /mi_person/'
;
COMMENT ON COLUMN xxi.mi_person.icusnum IS 
    'Обычно заполнен; допускается NULL для локальных персон без привязки к CUS'
;
COMMENT ON COLUMN xxi.mi_person.created_at IS 
    'Дата и время создания записи'
;
COMMENT ON COLUMN xxi.mi_person.first_name IS 
    'Имя'
;
COMMENT ON COLUMN xxi.mi_person.last_name IS 
    'Фамилия'
;
COMMENT ON COLUMN xxi.mi_person.middle_name IS 
    'Отчество'
;
COMMENT ON COLUMN xxi.mi_person.first_name_lat IS 
    'Имя латиницей'
;
COMMENT ON COLUMN xxi.mi_person.last_name_lat IS 
    'Фамилия латиницей'
;
COMMENT ON COLUMN xxi.mi_person.middle_name_lat IS 
    'Отчество латиницей'
;
COMMENT ON COLUMN xxi.mi_person.gender_id IS 
    'Пол человека'
;
COMMENT ON COLUMN xxi.mi_person.ctzn_type_id IS 
    'Тип гражданства'
;
COMMENT ON COLUMN xxi.mi_person.ctzn_country_code IS 
    'Страна/код страны гражданства'
;
COMMENT ON COLUMN xxi.mi_person.inn IS 
    'ИНН'
;
COMMENT ON COLUMN xxi.mi_person.snils IS 
    'СНИЛС'
;
COMMENT ON COLUMN xxi.mi_person.doc_type_id IS 
    'Тип документа, ДУЛ'
;
COMMENT ON COLUMN xxi.mi_person.doc_type_code IS 
    'Строковый код типа ДУЛ'
;
COMMENT ON COLUMN xxi.mi_person.doc_ser IS 
    'Серия ДУЛ'
;
COMMENT ON COLUMN xxi.mi_person.doc_num IS 
    'Номер ДУЛ'
;
COMMENT ON COLUMN xxi.mi_person.doc_issue_date IS 
    'Дата выдачи ДУЛ'
;
COMMENT ON COLUMN xxi.mi_person.doc_issuer_code IS 
    'Код подразделения, выдавшего ДУЛ'
;
COMMENT ON COLUMN xxi.mi_person.doc_expire_date IS 
    'Дата окончания срока действия ДУЛ'
;
COMMENT ON COLUMN xxi.mi_person.doc_issuer_name IS 
    'Наименование органа, выдавшего ДУЛ'
;
COMMENT ON COLUMN xxi.mi_person.doc_invalid_from IS 
    'Дата, с которой ДУЛ недействителен'
;
COMMENT ON COLUMN xxi.mi_person.birth_date IS 
    'Дата рождения'
;
COMMENT ON COLUMN xxi.mi_person.birth_date_raw IS 
    'Строковая дата рождения для особых случаев'
;
COMMENT ON COLUMN xxi.mi_person.birth_place IS 
    'Место рождения'
;
COMMENT ON COLUMN xxi.mi_person.death_date IS 
    'Дата смерти'
;
COMMENT ON COLUMN xxi.mi_person.phone IS 
    'Телефон'
;
COMMENT ON COLUMN xxi.mi_person.email IS 
    'E-mail'
;
COMMENT ON COLUMN xxi.mi_person.region_code IS 
    'Код региона'
;