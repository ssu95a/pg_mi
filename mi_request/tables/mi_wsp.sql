CREATE TABLE xxi.mi_wsp (
   wsp_id numeric(3) NOT NULL,
   name   varchar(250) NOT NULL,
   note   text,
   CONSTRAINT pk_mi_wsp PRIMARY KEY (wsp_id) 
        USING INDEX TABLESPACE indexes
)
TABLESPACE 
   users
;
COMMENT ON TABLE xxi.mi_wsp IS 'Один АРМ модуля СМЭВ'
;
COMMENT ON COLUMN xxi.mi_wsp.wsp_id IS E'ID Арм /wsp_id/'
;
COMMENT ON COLUMN xxi.mi_wsp.name IS E'Наименование'
;
COMMENT ON COLUMN xxi.mi_wsp.note IS E'Примечание'
;
ALTER TABLE xxi.mi_wsp OWNER TO "XXI"
;
