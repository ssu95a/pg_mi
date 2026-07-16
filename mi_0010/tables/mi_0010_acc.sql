--
-- Таблица    : xxi.mi_0010_acc
-- Назначение : ЕГР ЗАГС
-- Описание   : Список счетов
--
CREATE TABLE IF NOT EXISTS xxi.mi_0010_acc (
-- +---------------------------------------------------------------------------
-- |   column      |  type      |   null  | default 
-- +---------------------------------------------------------------------------
      acc_Id        numeric(12)   not null  DEFAULT nextval('xxi.s_mi_item'::regclass),
      itm_Id        numeric(12)   not null,
      fil           varchar (4)   not null,
      acc           varchar(20)   not null,
      acc_date      date              null,
      acc_cur       char(3)           null,
      acc_type      varchar(4)        null,

-- constraints
-- PK
      constraint pk_mi_0010_acc primary key (acc_Id) using index tablespace indexes,
-- FK
      constraint fk_mi_0010_acc__itm_id foreign key (itm_id) references xxi.mi_0010(itm_id) on delete cascade
)
tablespace users
;
-- Indexes
create index if not exists fx_mi_0010_acc__itm_Id on xxi.mi_0010_acc using btree ( itm_Id ) tablespace indexes
;
-- Grants
alter table xxi.mi_0010_acc owner to "xxi"
;
-- Comments
COMMENT ON TABLE xxi.mi_0010_acc is 'СМЭВ-3. Сведения о смерти физ лица. Список счетов. $id: {1.0.0} {15.07.2026} Sulimoff$'
;
comment on column xxi.mi_0010_acc.itm_id is 'ID элемента запроса /xxi.mi_0010/'
;
comment on column xxi.mi_0010_acc.fil is 'Филиал'
;
comment on column xxi.mi_0010_acc.acc is 'Счет'
;
comment on column xxi.mi_0010_acc.acc_date is 'Дата открытия счета'
;
comment on column xxi.mi_0010_acc.acc_cur  is 'Валюта счета'
;
comment on column xxi.mi_0010_acc.acc_type is 'Код вида счета'
;