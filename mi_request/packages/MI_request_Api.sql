CREATE OR REPLACE PACKAGE MI_Request_Api

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
   #import MI_logger
DECLARE
   /*
      Общая логика request header для mi_req
   */
   cVersion       CONSTANT varchar(100) := '$id: {1.0.0} {13.03.2026}$';
   cLogger        CONSTANT varchar(20 ) := 'mi.req'; 
   cPkg_Name      CONSTANT varchar(20 ) := 'MI_Request_Api'; 

   ret_OK         Constant int4    := 0;
   ret_Fail       Constant int4    := -1;

   cStatus_New     CONSTANT numeric := 0;
   cStatus_Busy   CONSTANT numeric := 2;
   cStatus_Sent   CONSTANT numeric := 3;
   cStatus_Done   CONSTANT numeric := 1;
   cStatus_Error  CONSTANT numeric := -1;

   cInitiator_Slf CONSTANT numeric := -1;
   cInitiator_Ext CONSTANT numeric := 1;

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


/*
   Следующий itm_id, sequence - s_mi_itm.
*/
CREATE FUNCTION next_Itm_Id( )
   RETURNS
      numeric
   LANGUAGE 
      plPGsql
AS
$function$
   #package
BEGIN
   RETURN nextval('xxi.s_mi_item')::numeric;
END;
$function$


/* Следующий req_id, sequence - s_mi_req. */
CREATE FUNCTION next_Req_Id( )
   RETURNS 
      numeric
   LANGUAGE 
      plPGsql
AS
$function$
   #package
BEGIN
   RETURN nextval('xxi.s_mi_req')::numeric;
END;
$function$


/* Определение wsp_id по inf_id */
CREATE FUNCTION resolve_Wsp_Id (
   in p_inf_id NUMERIC
)
   RETURNS 
      NUMERIC
   LANGUAGE 
      plPGsql
AS
$function$
   #package
   #private
DECLARE
   l_wsp_Id NUMERIC;
BEGIN

    select wsp_id 
      into l_wsp_Id 
      from MI_inf 
     where 
           inf_Id = p_inf_id;

   if l_wsp_Id is null then

      RAISE 
         EXCEPTION 
      USING
         ERRCODE = 'MI',
         MESSAGE = format('MI_Request_Api.resolve_Wsp_Id: unsupported inf_id = %s', p_inf_id );

   end if;

   RETURN l_wsp_Id;

END;
$function$


/* Определение inf_id - вида сведения, по inf_id - Id запроса */
CREATE FUNCTION resolve_Inf_Id (
   in p_req_Id NUMERIC
)
   RETURNS 
      numeric
   LANGUAGE 
      plPGsql
AS
$function$
   #package
DECLARE
   l_inf_Id numeric;
BEGIN

   SELECT r.inf_id
          INTO l_inf_id
     FROM xxi.mi_req r
    WHERE r.req_id = p_req_id;

   RETURN l_inf_Id;

END;
$function$


/* 
   Создать request header
*/
CREATE FUNCTION create_Request (
   in p_inf_id         numeric,
   in p_correlation_id uuid    DEFAULT NULL,
   in p_status_cd      numeric DEFAULT 0,
   in p_itype          numeric DEFAULT NULL,
   in p_i1             numeric DEFAULT NULL,
   in p_i2             numeric DEFAULT NULL,
   in p_i3             integer DEFAULT NULL
)
   RETURNS 
      numeric
   LANGUAGE
      plPGsql
AS
$function$
   #package
DECLARE
   l_req_id         numeric;
   l_correlation_id uuid;
BEGIN
   l_req_id := MI_Request_Api.next_Req_Id();

   l_correlation_id := coalesce( p_correlation_id, gen_random_uuid() );

   insert into 
      mi_req_id( req_id )
   values
      (l_req_id);   

   INSERT INTO mi_req (
      inf_id,
      req_id,
      created_at,
      correlation_id,
      status_cd,
      itype,
      i1,
      i2,
      i3
   )
   VALUES(
      p_inf_id,
      l_req_id,
      clock_timestamp(),
      l_correlation_id,
      p_status_cd,
      p_itype,
      p_i1,
      p_i2,
      p_i3
   );
   
   RETURN l_req_id;

END;
$function$


/* Существует ли request */
CREATE FUNCTION exists_Request (
   in p_req_id numeric
)
   RETURNS 
      boolean
   LANGUAGE 
      plPGsql
AS
$function$
   #package
DECLARE
   l_dummy int;
BEGIN

   SELECT 1
     INTO l_dummy
     FROM mi_req
    WHERE req_id = p_req_id;

   RETURN found;

END;
$function$


/*
   Получить статус request
*/
CREATE FUNCTION get_Status (
   in p_req_id numeric
)
   returns
      numeric
AS
$function$
   #package
DECLARE
   l_status numeric;
BEGIN

   select status_cd
     into strict 
          l_status
     from mi_req
    where req_id = p_req_id;

   return l_status;

END;
$function$


/*
   Взять запрос в обработку:
    0 -> 2
   -1 -> 2
*/
CREATE PROCEDURE take_For_Proc (
   in  p_req_id   numeric,
   in  p_info     varchar,
   out p_res_Code int4,
   out p_res_Info varchar
)
AS
   $procedure$
DECLARE

   cAction_Name     constant varchar(50) := (cPkg_Name || '.' || 'take_For_Proc')::varchar;

   l_inf_id         numeric;
   l_prev_status_cd numeric;

   l_curr_note      text;
   l_note_text      text;

BEGIN

   CALL MI_logger.enter_f( cLogger, cAction_Name, 'Взятие в обработку запроса'::varchar, 'req_id=' || p_req_id, null::numeric, p_req_id );

   p_res_Code := ret_Fail;
   p_res_Info := null;

   l_note_text:= trim( both from coalesce(p_info, '')) || ' [' || to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS.MS') || ']';

   SELECT r.inf_id,
          r.status_cd
     INTO l_inf_id,
          l_prev_status_cd
     FROM xxi.mi_req r
    WHERE r.req_id  = p_req_id
      AND r.status_cd IN (cStatus_new, cStatus_error)
      FOR UPDATE;

   IF FOUND THEN

      UPDATE xxi.mi_req r
         SET status_cd = cStatus_busy,
             note      = l_note_text
       WHERE r.req_id  = p_req_id
         AND r.status_cd IN ( cStatus_new, cStatus_Error );

      p_res_Code := ret_OK;
      p_res_Info := null;

      CALL MI_logger.info(
         p_logger_name   => cLogger,
         p_message_text  => 'Запрос взят в обработку',
         p_inf_id        => l_inf_id,
         p_req_id        => p_req_id,
         p_itm_id        => NULL::numeric,
         p_details_text  => l_note_text,
         p_action_cd     => cAction_Name,
         p_context_value => NULL::varchar,
         p_object_name   => cPkg_Name
      );

      RETURN;

   END IF;

   /*
      Дифференциация причины отказа:
      - нет запроса
      - уже обрабатывается
      - уже успешно завершён
      - уже отправлен
   */
   SELECT r.inf_id, r.status_cd, r.note
     INTO l_inf_id, l_prev_status_cd, l_curr_note
     FROM xxi.mi_req r
    WHERE 
          r.req_id = p_req_id;

   IF NOT FOUND THEN
      p_res_Info := 'Не найден запрос с req_id = ' || p_req_id;
   ELSIF 
      l_prev_status_cd = cStatus_busy 
   THEN
      p_res_Info := 'Не возможно взять запрос в обработку. Т.к. он уже обрабатывается.' || CASE WHEN l_curr_note IS NOT NULL THEN E'\n' || l_curr_note ELSE '' END;

   ELSIF l_prev_status_cd = cStatus_done THEN
         p_res_Info := 'Не возможно взять запрос в обработку. Т.к. он уже успешно обработан. Если необходимо, сначала сбросьте состояние запроса.';

   ELSIF l_prev_status_cd = cStatus_sent THEN
         p_res_Info := 'Не возможно взять запрос в обработку. Т.к. он уже отправлен во внешний сервис и ожидает завершения обработки.';

   ELSE
      p_res_Info := 'Не возможно взять запрос в обработку. Текущий статус: ' || coalesce(l_prev_status_cd::varchar, '<NULL>');
   END IF;

   CALL MI_logger.info (
      p_logger_name   => cLogger,
      p_message_text  => 'take_For_Proc rejected',
      p_inf_id        => l_inf_id,
      p_req_id        => p_req_id,
      p_itm_id        => NULL::numeric,
      p_details_text  => p_res_info,
      p_action_cd     => cAction_Name,
      p_context_value => NULL::varchar,
      p_object_name   => cPkg_Name
   );

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

            CALL mi_logger.error (
               p_logger_name   => cLogger,
               p_message_text  => cAction_Name || ' failed',
               p_inf_id        => l_inf_id,
               p_req_id        => p_req_id,
               p_itm_id        => NULL::numeric,
               p_details_text  => TS.WhenOthersError(cAction_Name, ex),
               p_action_cd     => 'exception',
               p_context_value => ex.RETURNED_SQLSTATE,
               p_object_name   => cPkg_Name
            );
      END; 

   p_res_code := ret_Fail;
   p_res_info := SQLERRM;

   RAISE;

END;
$procedure$


/* Отправить запрос в СМЭВ */
CREATE PROCEDURE to_Sent (
   in  p_req_id   numeric,
   out p_res_Code int4,
   out p_res_Info varchar
)
AS
   $procedure$
DECLARE

   cAction_Name   constant varchar(20) := 'to_sent';

   l_inf_id         numeric;
   l_prev_status_cd numeric;

BEGIN

   p_res_Code := ret_Fail;
   p_res_Info := null;

   UPDATE xxi.mi_req r
      SET status_cd = cStatus_sent
    WHERE r.req_id  = p_req_id
      AND r.status_cd = cStatus_busy
RETURNING OLD.inf_id,
          OLD.status_cd
          INTO l_inf_id,
               l_prev_status_cd;

   if found then 

      p_res_Code := ret_OK;
      p_res_Info := null;

      CALL MI_logger.info(
         p_logger_name   => cLogger,
         p_message_text  => 'Request moved to sent',
         p_inf_id        => l_inf_id,
         p_req_id        => p_req_id,
         p_itm_id        => NULL::numeric,
         p_details_text  => NULL::text,
         p_action_cd     => cAction_Name,
         p_context_value => NULL::varchar,
         p_object_name   => cPkg_Name
      );

      RETURN;

   end if;   


   SELECT r.inf_id,
          r.status_cd
     INTO l_inf_id,
          l_prev_status_cd
     FROM xxi.mi_req r
    WHERE r.req_id = p_req_id;

   IF NOT FOUND THEN
      p_res_Info := 'Не найден запрос с req_id = ' || p_req_id;

   ELSIF l_prev_status_cd = cStatus_Sent THEN
      p_res_Info := 'Не возможно перевести запрос в статус "отправлен". Т.к. он уже находится в статусе "отправлен".';

   ELSIF l_prev_status_cd = cStatus_Done THEN
      p_res_Info := 'Не возможно перевести запрос в статус "отправлен". Т.к. он уже успешно обработан.';

   ELSIF l_prev_status_cd = cStatus_Error THEN
      p_res_Info := 'Не возможно перевести запрос в статус "отправлен". Т.к. он находится в ошибочном статусе. Сначала возьмите его в обработку повторно.';

   ELSIF l_prev_status_cd = cStatus_New THEN
      p_res_Info := 'Не возможно перевести запрос в статус "отправлен". Т.к. он ещё не взят в обработку.';

   ELSE
      p_res_Info := 'Не возможно перевести запрос в статус "отправлен". Текущий статус: ' || coalesce(l_prev_status_cd::varchar, '<NULL>');
   END IF;

   CALL MI_logger.info (
      p_logger_name   => cLogger,
      p_message_text  => 'to_Sent rejected',
      p_inf_id        => l_inf_id,
      p_req_id        => p_req_id,
      p_itm_id        => NULL::numeric,
      p_details_text  => p_res_info,
      p_action_cd     => cAction_Name,
      p_context_value => NULL::varchar,
      p_object_name   => cPkg_Name
   );

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
      
            CALL MI_logger.error (
               p_logger_name   => cLogger,
               p_message_text  => cAction_Name || ' failed',
               p_inf_id        => l_inf_id,
               p_req_id        => p_req_id,
               p_itm_id        => NULL::numeric,
               p_details_text  => TS.WhenOthersError( cPkg_Name || '.' || cAction_Name, ex  ),
               p_action_cd     => 'exception',
               p_context_value => ex.RETURNED_SQLSTATE,
               p_object_name   => cPkg_Name
            );

      END; 

   RAISE;

END;
$procedure$


/* Перевод в успешный статус */
CREATE PROCEDURE to_Success(
   in  p_req_id   numeric,
   out p_res_code int4,
   out p_res_info varchar
)
AS
$procedure$
DECLARE
   
   cAction_Name constant varchar(50) := cPkg_Name || '.to_success';

   l_inf_id         numeric;
   l_prev_status_cd numeric;
BEGIN
   p_res_code := ret_Fail;
   p_res_info := NULL;

   UPDATE xxi.mi_req r
      SET status_cd = cStatus_done
    WHERE r.req_id = p_req_id
      AND r.status_cd = cStatus_sent
   RETURNING OLD.inf_id,
             OLD.status_cd
        INTO l_inf_id,
             l_prev_status_cd;

   IF FOUND THEN
      p_res_code := ret_OK;
      p_res_info := NULL;

      CALL MI_logger.info(
         p_logger_name   => cLogger,
         p_message_text  => 'Request moved to success',
         p_inf_id        => l_inf_id,
         p_req_id        => p_req_id,
         p_itm_id        => NULL::numeric,
         p_details_text  => NULL::text,
         p_action_cd     => cAction_Name,
         p_context_value => NULL::varchar,
         p_object_name   => cPkg_Name
      );

      RETURN;
   END IF;

   SELECT r.inf_id,
          r.status_cd
     INTO l_inf_id,
          l_prev_status_cd
     FROM xxi.mi_req r
    WHERE r.req_id = p_req_id;

   IF NOT FOUND THEN
      p_res_info :=
         'Не найден запрос с req_id = ' || p_req_id;

   ELSIF l_prev_status_cd = cStatus_done THEN
      p_res_info :=
         'Невозможно перевести запрос в статус "успешно обработан", '
         || 'так как он уже успешно обработан.';

   ELSIF l_prev_status_cd = cStatus_busy THEN
      p_res_info :=
         'Невозможно перевести запрос в статус "успешно обработан", '
         || 'так как запрос ещё находится в обработке '
         || 'и не зафиксирован как отправленный.';

   ELSIF l_prev_status_cd = cStatus_new THEN
      p_res_info :=
         'Невозможно перевести запрос в статус "успешно обработан", '
         || 'так как он ещё не был взят в обработку и отправлен.';

   ELSIF l_prev_status_cd = cStatus_error THEN
      p_res_info :=
         'Невозможно перевести запрос в статус "успешно обработан", '
         || 'так как он находится в ошибочном статусе.';

   ELSE
      p_res_info :=
         'Невозможно перевести запрос в статус "успешно обработан". '
         || 'Текущий статус: '
         || coalesce(l_prev_status_cd::varchar, '<NULL>');
   END IF;

   CALL MI_logger.info(
      p_logger_name   => cLogger,
      p_message_text  => 'to_Success rejected',
      p_inf_id        => l_inf_id,
      p_req_id        => p_req_id,
      p_itm_id        => NULL::numeric,
      p_details_text  => p_res_info,
      p_action_cd     => cAction_Name,
      p_context_value => NULL::varchar,
      p_object_name   => cPkg_Name
   );

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

         CALL MI_logger.error (
            p_logger_name   => cLogger,
            p_message_text  => cAction_Name || ' failed',
            p_inf_id        => l_inf_id,
            p_req_id        => p_req_id,
            p_itm_id        => NULL::numeric,
            p_details_text  => TS.WhenOthersError( cAction_Name, ex ),
            p_action_cd     => 'exception',
            p_context_value => ex.RETURNED_SQLSTATE,
            p_object_name   => cPkg_Name
         );

      END;

      RAISE;
END;
$procedure$


/* Перевод в ошибочный статус */
CREATE PROCEDURE to_Error(
   in  p_req_id   numeric,
   out p_res_code int4,
   out p_res_info varchar
)
AS
$procedure$
DECLARE

   cAction_Name constant varchar(50) := cPkg_Name || '.to_error';

   l_inf_id         numeric;
   l_prev_status_cd numeric;

BEGIN

   p_res_code := ret_Fail;
   p_res_info := NULL;

   UPDATE xxi.mi_req r
      SET status_cd = cStatus_error
    WHERE r.req_id = p_req_id
      AND r.status_cd IN (
         cStatus_busy,
         cStatus_sent
      )
   RETURNING OLD.inf_id,
             OLD.status_cd
        INTO l_inf_id,
             l_prev_status_cd;

   IF FOUND THEN
      p_res_code := ret_OK;
      p_res_info := NULL;

      CALL MI_logger.info(
         p_logger_name   => cLogger,
         p_message_text  => 'Request moved to error',
         p_inf_id        => l_inf_id,
         p_req_id        => p_req_id,
         p_itm_id        => NULL::numeric,
         p_details_text  => NULL::text,
         p_action_cd     => cAction_Name,
         p_context_value => NULL::varchar,
         p_object_name   => cPkg_Name
      );

      RETURN;
   END IF;

   SELECT r.inf_id,
          r.status_cd
     INTO l_inf_id,
          l_prev_status_cd
     FROM xxi.mi_req r
    WHERE r.req_id = p_req_id;

   IF NOT FOUND THEN
      p_res_info := 'Не найден запрос с req_id = ' || p_req_id;

   ELSIF l_prev_status_cd = cStatus_error THEN
      p_res_info := 'Невозможно перевести запрос в статус "ошибка", так как он уже находится в ошибочном статусе.';

   ELSIF l_prev_status_cd = cStatus_done THEN
      p_res_info :=
         'Невозможно перевести запрос в статус "ошибка", '
         || 'так как он уже успешно обработан.';

   ELSIF l_prev_status_cd = cStatus_new THEN
      p_res_info :=
         'Невозможно перевести запрос в статус "ошибка", '
         || 'так как он ещё не был взят в обработку.';

   ELSE
      p_res_info :=
         'Невозможно перевести запрос в статус "ошибка". '
         || 'Текущий статус: '
         || coalesce(l_prev_status_cd::varchar, '<NULL>');
   END IF;

   CALL MI_logger.info(
      p_logger_name   => cLogger,
      p_message_text  => 'to_Error rejected',
      p_inf_id        => l_inf_id,
      p_req_id        => p_req_id,
      p_itm_id        => NULL::numeric,
      p_details_text  => p_res_info,
      p_action_cd     => cAction_Name,
      p_context_value => NULL::varchar,
      p_object_name   => cPkg_Name
   );

EXCEPTION
   WHEN OTHERS THEN
      DECLARE
         ex TS.T_StackedDiagnostics;
      BEGIN
         GET STACKED DIAGNOSTICS
            ex.RETURNED_SQLSTATE =
               RETURNED_SQLSTATE,
            ex.MESSAGE_TEXT =
               MESSAGE_TEXT,
            ex.PG_EXCEPTION_DETAIL =
               PG_EXCEPTION_DETAIL,
            ex.PG_EXCEPTION_HINT =
               PG_EXCEPTION_HINT,
            ex.PG_EXCEPTION_CONTEXT =
               PG_EXCEPTION_CONTEXT;

         CALL MI_logger.error(
            p_logger_name   => cLogger,
            p_message_text  => cAction_Name || ' failed',
            p_inf_id        => l_inf_id,
            p_req_id        => p_req_id,
            p_itm_id        => NULL::numeric,
            p_details_text  =>
               TS.WhenOthersError(
                  cAction_Name,
                  ex
               ),
            p_action_cd     => 'exception',
            p_context_value => ex.RETURNED_SQLSTATE,
            p_object_name   => cPkg_Name
         );
      END;

      RAISE;
END;
$procedure$


/** */
CREATE PROCEDURE reset (
   in  p_req_id   numeric,
   in  p_info     varchar,
   out p_res_Code int4,
   out p_res_Info varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name      constant varchar(20) := 'reset';

   l_inf_id         numeric;
   l_prev_status_cd numeric;
   l_curr_note      text;
   l_note_text      text;

   l_sqlstate       text;
   l_message        text;
   l_detail         text;
   l_hint           text;
   l_context        text;
BEGIN

   p_res_Code := ret_Fail;
   p_res_Info := null;

   l_note_text := trim(both from coalesce(p_info, '')) || ' [RESET ' || to_char(clock_timestamp(), 'YYYY-MM-DD HH24:MI:SS.MS') || ']';

   /*
      Аварийный сброс в начальное состояние:
      любое состояние -> 0
      если уже 0, отдельно сообщаем
   */
   UPDATE xxi.mi_req r
      SET status_cd = cStatus_new,
          note      = l_note_text
    WHERE r.req_id  = p_req_id
      AND coalesce(r.status_cd, -999999) <> cStatus_new
    RETURNING OLD.inf_id,
              OLD.status_cd
         INTO l_inf_id,
              l_prev_status_cd;

   IF FOUND THEN
      p_res_Code := ret_OK;

      CALL MI_logger.info( cLogger, 'Request reset to initial state', l_inf_id, p_req_id, l_note_text, cAction_Name, NULL::varchar, cPkg_Name  );

      RETURN;
   END IF;

   SELECT r.inf_id,
          r.status_cd,
          r.note
     INTO l_inf_id,
          l_prev_status_cd,
          l_curr_note
     FROM xxi.mi_req r
    WHERE r.req_id = p_req_id;

   IF NOT FOUND THEN
      p_res_Info := 'Не найден запрос с req_id = ' || p_req_id;

   ELSIF l_prev_status_cd = cStatus_new THEN
      p_res_Code := ret_OK;
      p_res_Info := 'Сброс не требуется. Запрос уже находится в начальном статусе 0.';

   ELSE
      p_res_Info := 'Не удалось выполнить reset. Текущий статус: ' || coalesce(l_prev_status_cd::varchar, '<NULL>');
   END IF;

   CALL MI_logger.info( cLogger, 'reset rejected', l_inf_id, p_req_id,  p_res_Info, cAction_Name, NULL::varchar, cPkg_Name  );

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
      
            CALL MI_logger.error ( 
                 cLogger, 
                 cAction_Name || ' failed',
                 l_inf_id, p_req_id, 
                 TS.WhenOthersError( cPkg_Name || '.' || cAction_Name, ex ), 'exception', NULL::varchar, cPkg_Name 
            );

      END; 

   RAISE;

END;
$procedure$

/*
   Получить correlation_id
*/
CREATE FUNCTION get_Correlation_Id (
   in p_req_id numeric
)
   RETURNS 
      uuid
   LANGUAGE 
      plPGsql
AS
$function$
   #package
DECLARE
   l_correlation_id uuid;
BEGIN
   SELECT correlation_id
     INTO STRICT l_correlation_id
     FROM mi_req
    WHERE req_id = p_req_id;

   RETURN l_correlation_id;
END;
$function$


/* Взять request на блокировку */
CREATE FUNCTION lock_Request (
   in p_req_id numeric
)
   RETURNS 
      record --mi_req
AS
$function$
   #package
DECLARE
   --r mi_req%rowtype;
   r record;
BEGIN
   /*
   SELECT *
     INTO STRICT r
     FROM mi_req
    WHERE req_id = p_req_id
    FOR UPDATE;
    */
   RETURN r;
END;
$function$


/* Удалить request */
CREATE PROCEDURE delete_Request(
   in p_req_id numeric
)
AS
$procedure$
   #package
BEGIN
   DELETE
     FROM xxi.mi_req_id
    WHERE 
          req_id = p_req_id;
END;
$procedure$


/* Удалить помеченные */
CREATE PROCEDURE delete_By_Marker(
   in  p_marker_id  numeric,
   out p_res_Info   varchar
)
AS
$procedure$
DECLARE
   cAction_Name   constant varchar(20) := 'delete_by_marker';

   l_deleted_count integer;
BEGIN
   p_res_Info := null;

   DELETE FROM xxi.mi_req r
   USING xxi.mrk_id m
   WHERE m.idmarker = p_marker_id
     AND m.idrow    = r.req_id;

   GET DIAGNOSTICS l_deleted_count = ROW_COUNT;

   IF l_deleted_count = 0 THEN
      p_res_Info := 'По marker_id = ' || p_marker_id || ' запросы для удаления не найдены.';
   ELSE
      p_res_Info := 'Удалено запросов: ' || l_deleted_count::varchar || '.';
   END IF;

   CALL MI_logger.info( cLogger, 'delete_By_Marker completed', NULL::numeric, NULL::numeric, p_res_Info, cAction_Name, 'marker_id=' || p_marker_id::varchar, cPkg_Name );

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
      
            CALL MI_logger.error ( 
                 cLogger, 
                 cAction_Name || ' failed',
                 null::numeric, 
                 null::numeric, 
                 TS.WhenOthersError( cPkg_Name || '.' || cAction_Name, ex ), 'exception', NULL::varchar, cPkg_Name 
            );

      END; 

   RAISE;

END;
$procedure$


/* Установка запроса в ошибочный стутс из-за ответа СМЭВ */
CREATE PROCEDURE apply_Request_Failure (
   
   in p_external_uuid uuid,
   in p_message_uuid  uuid,

   in p_reason_code   varchar,

   in p_error_code    varchar,
   in p_error_info    varchar,
   in p_error_details text,

   in p_occurred_at   timestamptz,

   out p_res_code     int4,
   out p_res_info     varchar
)
AS
$procedure$
   #package
declare

   cAction_Name  constant varchar := cPkg_Name || '.apply_Request_Failure';

   l_req_Id    numeric;
   l_inf_Id    numeric;

   l_status_cd numeric;

   l_reason_code varchar;

   l_current_message_uuid uuid;
   
   l_expected_stage_cd numeric;
   l_current_stage_cd  numeric;

begin

   p_res_code := -1;
   p_res_Info := 'Unhandled error in ' || cAction_Name;

/*   call MI_logger.enter_f( cLogger, cAction_Name, 'Отрицательный ответ от MI/SMEV на запрос'::varchar, 
                          'p_external_uuid=' || p_external_uuid || ', p_reason= ' || p_reason_code || ', p_error_code = ' || p_error_code  ); */

   CALL MI_logger.enter_f(
      p_logger_name   => cLogger,
      p_function_name => cAction_Name,
      p_message_text  => 'Отрицательный ответ от MI/SMEV на запрос'::varchar,
      p_parameters    => 'p_external_uuid=' || p_external_uuid || ', p_reason= ' || p_reason_code || ', p_error_code = ' || p_error_code,
      p_inf_id        => NULL::numeric,
      p_req_id        => NULL::numeric,
      p_itm_id        => NULL::numeric
   );


   /*
    * Нормализуем значение transport enum:
    * REQUEST_REJECTED / REQUEST_FAILED.
    */

   l_reason_code := upper( trim(p_reason_code) );

   -- Проверка обязательных параметров.
   IF p_external_uuid IS NULL THEN
      p_res_info := 'p_external_uuid is null';
      RETURN;
   END IF;

   IF p_message_uuid IS NULL THEN
      p_res_info := 'p_message_uuid is null';
      RETURN;
   END IF;

   IF l_reason_code IS NULL THEN
      p_res_info := 'p_reason_code is null';
      RETURN;
   END IF;

   l_expected_stage_cd :=
      CASE l_reason_code
         WHEN 'REQUEST_REJECTED' THEN 1::numeric
         WHEN 'REQUEST_FAILED'   THEN 2::numeric
         ELSE NULL
      END;

   /* Ищем запрос независимо от текущего статуса
      и блокируем его до завершения процедуры. */
   BEGIN

      SELECT r.req_id,
             r.inf_id,
             r.status_cd,
             r.stage_cd,
             r.message_uuid
        INTO STRICT
             l_req_id,
             l_inf_id,
             l_status_cd,
             l_current_stage_cd,
             l_current_message_uuid
        FROM xxi.mi_req r
       WHERE r.external_uuid = p_external_uuid
         FOR UPDATE;

   EXCEPTION
      WHEN no_data_found THEN

         p_res_code := ret_Fail;
         p_res_info := 'Не найден запрос с external_uuid = ' || p_external_uuid;

         RETURN;
   END;

   -- call MI_logger.variable_Value( cLogger, 'req_id', l_req_Id, p_inf_id => l_inf_id, p_req_id => l_req_Id );

   -- Запрос уже установлен в ошибочный статус. 
   IF l_status_cd = -1 THEN

      -- Тот же message_uuid должен содержать точно такие же данные.
      IF l_current_message_uuid = p_message_uuid THEN

         IF l_current_stage_cd IS NOT DISTINCT FROM l_expected_stage_cd
         THEN
            p_res_code := ret_Ok;
            p_res_info := 'Отрицательный ответ уже применён ранее';

            RETURN;
         END IF;

         p_res_code := ret_Fail;
         p_res_info := 'Конфликт повторного сообщения: message_uuid=' || p_message_uuid || ' уже применён с другими данными';

         RETURN;

      END IF;

      -- Другой ответ пришёл для уже завершённого запроса.
      p_res_code := ret_Fail;
      p_res_info := 'Запрос уже установлен в ошибочный статус другим сообщением: current_message_uuid='
                    || coalesce( l_current_message_uuid::varchar, 'null' ) || ', incoming_message_uuid='|| p_message_uuid;

      RETURN;

   END IF;

   -- Отрицательный ответ применим только к запросу, который был успешно отправлен.
   IF l_status_cd <> 3 THEN

      p_res_code := ret_Fail;
      p_res_info := 'Запрос не находится в необходимом статусе 3: ' || 'status_cd=' || coalesce( l_status_cd::varchar, 'null' );

      RETURN;

   END IF;

   UPDATE xxi.mi_req
      SET status_cd    = -1,
          stage_cd     = l_expected_stage_cd,
          result_code  = p_error_code,
          result_info  = p_error_info,
          note         = p_error_details,
          result_time  = p_occurred_at,
          message_uuid = p_message_uuid
    WHERE 
          req_id = l_req_id;

   IF NOT FOUND THEN
      p_res_code := ret_Fail;
      p_res_info := 'Не удалось обновить запрос: req_id=' || l_req_id || '. Данные не нашлись';

      RETURN;

   END IF;

   p_res_code := ret_Ok;
   p_res_info := 'Отрицательный ответ успешно применён: req_id=' || l_req_id;

EXCEPTION
   WHEN others THEN
      DECLARE
         ex TS.T_StackedDiagnostics;
      BEGIN
        GET STACKED DIAGNOSTICS
            ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,
            ex.MESSAGE_TEXT         = MESSAGE_TEXT,
            ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
            ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
            ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;

            CALL MI_logger.error(
               p_logger_name   => cLogger,
               p_message_text  => cAction_Name || ' failed',
               p_inf_id        => l_inf_id,
               p_req_id        => l_req_id,
               p_itm_id        => NULL::numeric,
               p_details_text  => TS.WhenOthersError( cAction_Name, ex ),
               p_action_cd     => 'exception',
               p_context_value => ex.RETURNED_SQLSTATE,
               p_object_name   => cPkg_Name
            );
      END; 

      p_res_code := ret_Fail;
      p_res_info := SQLERRM;

END;
$procedure$

/* end_Of_Package */
;
