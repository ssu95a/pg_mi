CREATE TABLE IF NOT EXISTS xxi.mi_req_event (
   event_id          bigserial PRIMARY KEY,
   event_at          timestamptz NOT NULL DEFAULT clock_timestamp(),

   req_id            numeric(12) NOT NULL
      REFERENCES xxi.mi_req_id(req_id) ON DELETE CASCADE,

   external_uuid     uuid,
   correlation_id    uuid,
   inf_id            numeric(6),

   source_cd         varchar(32) NOT NULL,  -- X / XXL / MI / S
   event_cd          varchar(64) NOT NULL,  -- STATUS_CHANGED / ERROR / RETRY / RESPONSE_RECEIVED
   stage_cd          varchar(64),

   old_status_cd     numeric(1),
   new_status_cd     numeric(1),

   message_id        uuid,
   causation_id      uuid,

   error_code        varchar(200),
   error_kind        varchar(32),
   retryable         boolean,

   message_text      text,
   details           jsonb
);

CREATE INDEX ix_mi_req_event__req_id_event_at
   ON xxi.mi_req_event(req_id, event_at DESC);

CREATE INDEX ix_mi_req_event__external_uuid
   ON xxi.mi_req_event(external_uuid);

CREATE INDEX ix_mi_req_event__correlation_id
   ON xxi.mi_req_event(correlation_id);

CREATE INDEX ix_mi_req_event__event_at
   ON xxi.mi_req_event(event_at DESC);