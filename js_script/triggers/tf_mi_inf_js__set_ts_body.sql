CREATE OR REPLACE FUNCTION xxi.tf_mi_inf_js__set_ts_body()
RETURNS trigger
LANGUAGE plpgsql
AS
$function$
BEGIN
   IF TG_OP = 'INSERT' THEN
      NEW.ts_body := current_timestamp;
      RETURN NEW;
   END IF;

   IF NEW.js_body IS DISTINCT FROM OLD.js_body THEN
      NEW.ts_body := current_timestamp;
   END IF;

   RETURN NEW;
END;
$function$;

CREATE TRIGGER tbu_mi_inf_js__set_ts_body
BEFORE INSERT OR UPDATE
ON xxi.mi_inf_js
FOR EACH ROW
EXECUTE FUNCTION xxi.tf_mi_inf_js__set_ts_body();