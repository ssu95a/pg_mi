CREATE OR REPLACE PACKAGE MI_Response_Api

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
   #import MI_logger
DECLARE
   /*
      Общая логика response для mi_rsp/mi_req
   */
   cVersion       CONSTANT varchar(100) := '$id: {0.0.1} {16.08.2026}$';
   cLogger        CONSTANT varchar(20 ) := 'mi.rsp'; 
   cPkg_Name      CONSTANT varchar(20 ) := 'MI_Response_Api'; 

   ret_OK         Constant int4    := 0;
   ret_Fail       Constant int4    := -1;

   cStatus_New    CONSTANT numeric := 0;
   cStatus_Ready  CONSTANT numeric := 1;
   cStatus_Sent   CONSTANT numeric := 2;
   cStatus_Error  CONSTANT numeric := -1;

BEGIN
   raise debug 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


/* Версия */
CREATE FUNCTION get_Version()
   RETURNS 
      VARCHAR
   LANGUAGE 
      plPGsql
AS
$function$
   #package
BEGIN
   RETURN cVersion;
END;
$function$


/* Id для ответа */
CREATE FUNCTION next_Rsp_Id()
   RETURNS numeric
AS
$function$
   #package
BEGIN
   RETURN nextval('xxi.s_mi_rsp')::numeric;
END;
$function$


/* Создает ответ на запрос */
CREATE FUNCTION create_Response (
   
   IN p_req_id        numeric,
   IN p_itm_id        numeric,

   IN p_category_cd   varchar,
   IN p_result_code   varchar,
   IN p_result_info   varchar DEFAULT NULL,

   IN p_payload       jsonb   DEFAULT NULL
)
RETURNS 
   numeric
AS
$function$
   #package
DECLARE
   l_rsp_id numeric;
BEGIN

   l_rsp_id := MI_Response_Api.next_Rsp_Id();

   INSERT INTO xxi.mi_rsp (
      rsp_id,
      req_id,
      itm_id,
      category_cd,
      result_code,
      result_info,
      payload,
      status_cd
   )
   VALUES (
      l_rsp_id,
      p_req_id,
      p_itm_id,
      p_category_cd,
      p_result_code,
      p_result_info,
      p_payload,
      cStatus_New
   );

      CALL MI_logger.info(
         p_logger_name   => cLogger,
         p_message_text  => 'Сформирован ответ на позицию запроса',
         p_inf_id        => NULL::numeric,
         p_req_id        => p_req_id,
         p_itm_id        => p_itm_id,
         p_action_cd     => 'create_Response',
         p_context_value => l_rsp_id::varchar,
         p_object_name   => cPkg_Name
      );

   RETURN l_rsp_id;

END;
$function$


/* Изменить статус ответа на готов к отправке */
CREATE PROCEDURE to_Ready (
   in  p_rsp_id   numeric,
   out p_res_Code int4,
   out p_res_Info varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name constant varchar(20) := 'to_Ready';

   l_prev_status_cd numeric;
   l_req_id         numeric;
   l_itm_id         numeric;

BEGIN

   p_res_Code := ret_Fail;
   p_res_Info := NULL;

   UPDATE xxi.mi_rsp
      SET status_cd = cStatus_Ready
    WHERE rsp_id    = p_rsp_id
      AND status_cd = cStatus_New
   RETURNING req_id,
             itm_id
        INTO l_req_id,
             l_itm_id;

   IF FOUND THEN

      p_res_Code := ret_OK;

      CALL MI_logger.info(
         p_logger_name   => cLogger,
         p_message_text  => 'Ответ готов к отправке',
         p_inf_id        => NULL::numeric,
         p_req_id        => l_req_id,
         p_itm_id        => l_itm_id,
         p_details_text  => NULL::text,
         p_action_cd     => cAction_Name,
         p_context_value => null::varchar,
         p_object_name   => cPkg_Name
      );

      RETURN;

   END IF;

   SELECT r.status_cd,
          r.req_id,
          r.itm_id
     INTO l_prev_status_cd,
          l_req_id,
          l_itm_id
     FROM xxi.mi_rsp r
    WHERE r.rsp_id = p_rsp_id;

   IF NOT FOUND THEN
      p_res_Info := 'Не найден ответ с rsp_id = ' || p_rsp_id;

   ELSIF l_prev_status_cd = cStatus_Ready THEN
         p_res_Info := 'Невозможно перевести ответ в статус "Готов". Ответ уже находится в статусе "Готов".';

   ELSIF l_prev_status_cd = cStatus_Sent THEN
         p_res_Info := 'Невозможно перевести ответ в статус "Готов". Ответ уже успешно отправлен.';

   ELSIF l_prev_status_cd = cStatus_Error THEN
         p_res_Info := 'Невозможно перевести ответ в статус "Готов". Ответ находится в ошибочном статусе.';
   ELSE
         p_res_Info := 'Невозможно перевести ответ в статус "Готов". Текущий статус: ' || coalesce(l_prev_status_cd::varchar, '<NULL>');

   END IF;

   CALL MI_logger.info(
      p_logger_name   => cLogger,
      p_message_text  => 'to_Ready rejected',
      p_inf_id        => NULL::numeric,
      p_req_id        => l_req_id,
      p_itm_id        => l_itm_id,
      p_details_text  => p_res_Info,
      p_action_cd     => cAction_Name,
      p_context_value => p_rsp_id::varchar,
      p_object_name   => cPkg_Name
   );

END;
$procedure$


END;
