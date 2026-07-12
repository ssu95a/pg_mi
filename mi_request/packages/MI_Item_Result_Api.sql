create or replace package MI_Item_Result_Api

CREATE TYPE Item_Result AS (
   ires_code numeric,
   cres_info text
)


/* Инициализация пакета */
CREATE FUNCTION __init__()
    RETURNS void
AS
$init$
DECLARE

   cVersion     CONSTANT varchar(100) := '$id: {1.0.0} {11.07.2026}$';

   cPkg_Name    CONSTANT varchar(20 ) := 'MI_Item_Result_Api'; 
   cLogger      CONSTANT varchar(20 ) := 'mi.req.itm'; 

   ret_OK       CONSTANT int4 := 0;
   ret_FAIL     CONSTANT int4 := -1;

BEGIN
    RAISE DEBUG 'Package "MI_resultCtx" - % - initialized', cVersion;
END;
$init$


/* Версия */
CREATE FUNCTION get_Version()
    RETURNS varchar
AS
$function$
   #package
BEGIN
   RETURN cVersion;
END;
$function$


/* */
CREATE PROCEDURE parse_Json_Payload (
   in p_payload_text text,
  out p_payload_json jsonb, 
  out p_ret_Code     int4, 
  out p_ret_Info     varchar 
)
AS 
$procedure$
   #package
   #private
BEGIN
   p_payload_json := p_payload_text::jsonb;
   p_ret_Code     := ret_Ok;
EXCEPTION
   WHEN OTHERS THEN
      DECLARE
         ex TS.T_StackedDiagnostics;
      BEGIN
        GET STACKED DIAGNOSTICS                       
            ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,  
            ex.MESSAGE_TEXT         = MESSAGE_TEXT,
            ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
            ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
            ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;   
      
         p_ret_info := 'p_payload_text is not valid JSON: ' || TS.WhenOthersError( cFunc, ex );
         p_ret_Code := ret_Fail;
      END; 
END;
$procedure$


/* */
CREATE PROCEDURE apply_Item_Result (

   in p_item_Table        regclass,
   in p_payload_Mapper    regprocedure,

   in p_request_uuid      uuid,
   in p_message_uuid      uuid,
   in p_item_uuid         uuid,

   in p_response_kind     int4,

   in p_response_code     varchar,
   in p_response_info     varchar,
   in p_response_details  text,
   in p_response_time     timestamptz,

   in p_payload_text      text,

  out p_ret_code          int4,
  out p_ret_info          varchar
)
AS 
$procedure$
   #package
DECLARE

   cAlready_applied constant int4 := 1;
   cOther_applied   constant int4 := 2;

   l_itm_id               numeric(12);
   l_current_message_uuid uuid;

   l_payload              jsonb;
   l_item_Result          MI_Item_Result_Api.item_Result;

   l_row_Count            int4;

BEGIN

   p_ret_code := ret_Fail;
   p_ret_info := NULL;

   if p_response_kind not in (ret_OK,ret_Fail) then
      p_ret_info := 'unsupported p_response_kind: ' || p_response_kind;
      RETURN;
   end if;   


   EXECUTE format(
      $sql$
      SELECT i.itm_id,
             i.message_uuid
        FROM xxi.mi_req r
        JOIN %s i
          ON i.req_id = r.req_id
       WHERE r.external_uuid = $1
         AND i.external_uuid = $2
       FOR UPDATE OF i
      $sql$,
      p_item_table
   )
   INTO l_itm_id,
        l_current_message_uuid
   USING p_request_uuid,
         p_item_uuid;

   IF l_itm_id IS NULL THEN
      p_ret_info := 'item not found: table=' || p_item_table || ', request_uuid=' || p_request_uuid || ', item_uuid=' || p_item_uuid;
      RETURN;

   END IF;

   IF l_current_message_uuid IS NOT NULL 
   THEN

      IF l_current_message_uuid = p_message_uuid THEN
         p_ret_code := cAlready_applied;
         p_ret_info := 'Item already applied';
         
         RETURN;

      END IF;

      p_ret_info := 'item already applied by another message: current_message_uuid=' || l_current_message_uuid || ', new_message_uuid=' || p_message_uuid;
      p_ret_code := cOther_applied;
      RETURN;

   END IF;

   IF p_response_kind = ret_OK
   THEN

      IF p_payload_text IS NULL OR btrim(p_payload_text) = '' THEN
         p_ret_info := 'p_payload_text is null or empty for successful item';
         RETURN;
      END IF;

      -- разбор PayLoad
      call parse_Json_Payload( p_payload_text, l_payload, p_ret_code, p_ret_info );
      
      if p_ret_code <> ret_OK then
         RETURN;
      end if;


      -- мапинг pyload 
      BEGIN

         EXECUTE format( 'SELECT * FROM %s($1,$2)', p_payload_Mapper )
            INTO l_item_Result
           USING l_payload, l_itm_Id;
         EXCEPTION
            WHEN others THEN
               GET STACKED DIAGNOSTICS
                   p_ret_info = MESSAGE_TEXT;

               p_ret_info := 'successful payload business mapping failed: ' || p_ret_info;

         RETURN;

      END;

   ELSE -- p_response_kind = ret_FAIL

      IF p_response_code IS NULL OR btrim(p_response_code) = '' THEN
         p_ret_info := 'p_response_code is null or empty for failed item';

         RETURN;

      END IF;

      l_item_Result.ires_Code := ret_Fail;
      l_item_Result.cres_Info := COALESCE( NULLIF(p_response_info, ''), NULLIF(p_response_details, ''), p_response_code );

   END IF;

   EXECUTE format(
      $sql$
      UPDATE %s
         SET ires_code    = $1,
             cres_info    = $2,
             tres_time    = $3,
             message_uuid = $4,
             error_code   = $5
       WHERE itm_id = $6
         AND message_uuid IS NULL
      $sql$,
      p_item_Table
   )
   USING l_item_Result.ires_Code,
         l_item_Result.cres_Info,
         p_response_time,
         p_message_uuid,
         CASE
            WHEN p_response_kind = ret_Fail
            THEN p_response_code
                 ELSE NULL
         END,
         l_itm_id;

   GET DIAGNOSTICS l_row_count = ROW_COUNT;

   IF l_row_count <> 1 THEN
      p_ret_info := 'item outcome was not applied, table=' || p_item_table || ', row_count=' || l_row_count;
      RETURN;
   END IF;

   p_ret_code := ret_OK;
   p_ret_info := 'applied';

END;
$procedure$

; -- end_of_Package