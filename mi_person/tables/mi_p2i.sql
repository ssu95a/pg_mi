CREATE TABLE xxi.mi_p2i 
(
   person_id numeric(12) NOT NULL,
   inf_id numeric(6) NOT NULL,
   linked_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
   CONSTRAINT pk_mi_p2i PRIMARY KEY (person_id, inf_id) using index TABLESPACE indexes
)
TABLESPACE users
;
COMMENT ON TABLE xxi.mi_p2i IS 'Связь person и видами сведений'
;
COMMENT ON COLUMN xxi.mi_p2i.linked_at IS 'Когда была сформирована связь'
;
ALTER TABLE xxi.mi_p2i OWNER TO "XXI"
;
ALTER TABLE xxi.mi_p2i ADD CONSTRAINT fk_mi_p2i__mi_inf FOREIGN KEY (inf_id)
   REFERENCES xxi.mi_inf (inf_id) MATCH FULL
      ON DELETE CASCADE
;
ALTER TABLE xxi.mi_p2i 
   ADD CONSTRAINT fk_mi_p2i__mi_person FOREIGN KEY (person_id)
      REFERENCES xxi.mi_person (person_id) MATCH FULL
ON DELETE CASCADE
;
CREATE INDEX fx_mi_p2i__inf ON xxi.mi_p2i USING btree( inf_id ) TABLESPACE indexes
;