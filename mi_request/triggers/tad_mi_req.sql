CREATE OR REPLACE FUNCTION mi_request_api.tf_mi_req__delete_req_id()
RETURNS 
  trigger
LANGUAGE 
  plPGsql
AS
$function$
BEGIN
   DELETE
     FROM xxi.mi_req_id
    WHERE req_id = OLD.req_id;
   RETURN NULL;
END;
$function$
;
CREATE OR REPLACE TRIGGER 
   tad_mi_req
AFTER 
   DELETE
ON
   xxi.mi_req
FOR
   EACH ROW
EXECUTE 
   FUNCTION MI_Request_Api.tf_mi_req__delete_req_id()
;