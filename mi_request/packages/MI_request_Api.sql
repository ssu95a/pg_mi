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
   cVersion         CONSTANT varchar(100) := '$id: {1.0.0} {13.03.2026}$';
   cLogger          CONSTANT varchar(20 ) := 'mi.req'; 
   cPkg_Name        CONSTANT varchar(20 ) := 'MI_Request_Api'; 

   ret_OK           Constant int4    := 0;
   ret_Fail         Constant int4    := -1;

   cStatus_New      CONSTANT numeric := 0;
   cStatus_Busy     CONSTANT numeric := 2;
   cStatus_Sent     CONSTANT numeric := 3;
   cStatus_Done     CONSTANT numeric := 1;
   cStatus_Error    CONSTANT numeric := -1;

   cInitiator_Slf   CONSTANT numeric := -1;
   cInitiator_Ext   CONSTANT numeric := 1;

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


/*
   Следующий req_id, sequence - s_mi_req.
*/
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

    select inf_id 
      into l_inf_Id 
      from MI_inf 
     where 
           inf_Id = p_req_id;

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
   RETURNS 
      numeric
   LANGUAGE 
      plpgsql
AS
$function$
   #package
DECLARE
   l_status numeric;
BEGIN

   SELECT status_cd
     INTO STRICT 
          l_status
     FROM mi_req
    WHERE req_id = p_req_id;

   RETURN l_status;

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
   -- mi_logger.enter_f(character varying, character varying, character varying, numeric, numeric)
/*
CREATE PROCEDURE enter_f (
   in p_logger_name    varchar,
   in p_function_name  varchar,
   in p_message_text   varchar   default null,
   in p_parameters     text      default null, 
   in p_inf_id         numeric   default null,
   in p_req_id         numeric   default null,
   in p_person_id      numeric   default null,
   in p_icusnum        numeric   default null,
   in p_object_id      numeric   default null,
   in p_object_id2     numeric   default null
)
*/

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

      CALL MI_logger.info( cLogger, '<Запрос взят в обработку>', l_inf_id, p_req_id, l_note_text, cAction_Name, NULL::varchar, cPkg_Name );

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
         p_res_Info := 
            'Не возможно взять запрос в обработку. Т.к. он уже успешно обработан. Если необходимо, сначала сбросьте состояние запроса.';

   ELSIF l_prev_status_cd = cStatus_sent THEN
         p_res_Info :=
            'Не возможно взять запрос в обработку. Т.к. он уже отправлен во внешний сервис и ожидает завершения обработки.';

   ELSE
      p_res_Info :=
            'Не возможно взять запрос в обработку. Текущий статус: ' || coalesce(l_prev_status_cd::varchar, '<NULL>');
   END IF;

   CALL MI_logger.info( cLogger, 'take_For_Proc rejected', l_inf_id, p_req_id, p_res_Info, cAction_Name, NULL::varchar, cPkg_Name );

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
                 cLogger, 
                 cAction_Name || ' failed',
                 l_inf_id, p_req_id, 
                 TS.WhenOthersError( cAction_Name, ex ), 'exception', NULL::varchar, cPkg_Name
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

   select r.inf_id, r.status_cd 
          into l_inf_id, l_prev_status_cd 
     from xxi.mi_req r
    where r.req_id = p_req_id AND r.status_cd = cStatus_busy
      for update;

   /*   
   UPDATE xxi.mi_req r
      SET status_cd = cStatus_sent
    WHERE r.req_id  = p_req_id
      AND r.status_cd = cStatus_busy
    RETURNING OLD.inf_id,
              OLD.status_cd
         INTO l_inf_id,
              l_prev_status_cd;
   */ 

   IF FOUND THEN

      UPDATE xxi.mi_req r
         SET status_cd = cStatus_sent
       WHERE r.req_id  = p_req_id AND r.status_cd = cStatus_busy;

      if found then 

         p_res_Code := ret_OK;
         p_res_Info := null;

         CALL MI_logger.info( cLogger, 'Request moved to sent', l_inf_id, p_req_id, NULL::varchar, cAction_Name, NULL::varchar, cPkg_Name );

         RETURN;

      end if;   

   END IF;

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

   CALL MI_logger.info( cLogger, 'to_Sent rejected', l_inf_id, p_req_id, p_res_Info, cAction_Name, NULL::varchar, cPkg_Name );

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
      
            CALL MI_logger.error( 
                 cLogger, 
                 cAction_Name || 'failed',
                 l_inf_id, p_req_id, 
                 TS.WhenOthersError( cPkg_Name || '.' || cAction_Name, ex ), 'exception', NULL::varchar, cPkg_Name 
            );

      END; 

   RAISE;

END;
$procedure$


/* Перевод в успешный статус */
CREATE PROCEDURE to_Success(
   in  p_req_Id   numeric,
   out p_res_Code int4,
   out p_res_Info varchar
)
AS
$procedure$
DECLARE
   cAction_Name   constant varchar(20) := 'to_success';

   l_inf_id         numeric;
   l_prev_status_cd numeric;

   l_sqlstate       text;
   l_message        text;
   l_detail         text;
   l_hint           text;
   l_context        text;
BEGIN
   p_res_Code := ret_Fail;
   p_res_Info := null;

   UPDATE xxi.mi_req r
      SET status_cd = cStatus_done
    WHERE r.req_id = p_req_id
      AND r.status_cd = cStatus_sent
    RETURNING OLD.inf_id,
              OLD.status_cd
         INTO l_inf_id,
              l_prev_status_cd;

   IF FOUND THEN

      p_res_Code := ret_OK;
      p_res_Info := null;

      CALL MI_logger.info( cLogger, 'Request moved to success', l_inf_id, p_req_id, NULL::varchar, cAction_Name, NULL::varchar, cPkg_Name );
      
      RETURN;

   END IF;

   SELECT r.inf_id,
          r.status_cd
     INTO l_inf_id,
          l_prev_status_cd
     FROM xxi.mi_req r
    WHERE r.req_id = p_req_id;

   IF NOT FOUND THEN
      p_res_Info := 'Не найден запрос с req_id = ' || p_req_id;

   ELSIF l_prev_status_cd = cStatus_done THEN
         p_res_Info 
            := 'Не возможно перевести запрос в статус "успешно обработан". Т.к. он уже успешно обработан.';

   ELSIF l_prev_status_cd = cStatus_busy THEN
         p_res_Info 
            := 'Не возможно перевести запрос в статус "успешно обработан". Т.к. запрос ещё находится в обработке и не зафиксирован как отправленный.';

   ELSIF l_prev_status_cd = cStatus_new THEN
         p_res_Info 
            := 'Не возможно перевести запрос в статус "успешно обработан". Т.к. он ещё не был взят в обработку и отправлен.';

   ELSIF l_prev_status_cd = cStatus_error THEN
         p_res_Info 
            := 'Не возможно перевести запрос в статус "успешно обработан". Т.к. он находится в ошибочном статусе.';

   ELSE
      p_res_Info := 'Не возможно перевести запрос в статус "успешно обработан". Текущий статус: '
                       || coalesce(l_prev_status_cd::varchar, '<NULL>');
   END IF;

   CALL MI_logger.info( cLogger, 'to_Success rejected', l_inf_id, p_req_id, p_res_Info, cAction_Name, NULL::varchar, cPkg_Name );

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
      
            CALL MI_logger.error( 
                 cLogger, 
                 'to_Success failed',
                 l_inf_id, p_req_id, 
                 TS.WhenOthersError( cPkg_Name || '.to_Success', ex ), 'exception', NULL::varchar, cPkg_Name 
            );

      END; 

   RAISE;

END;
$procedure$


/* */
CREATE PROCEDURE to_Error(
   in  p_req_Id   numeric,
   out p_res_Code int4,
   out p_res_Info varchar
)
AS
$procedure$
DECLARE
   cAction_Name     constant varchar(20) := 'to_error';

   l_inf_id         numeric;
   l_prev_status_cd numeric;

BEGIN
   p_res_Code := ret_Fail;
   p_res_Info := null;

   UPDATE xxi.mi_req r
      SET status_cd = cStatus_error
    WHERE r.req_id  = p_req_id
      AND r.status_cd IN ( cStatus_busy, cStatus_sent )
    RETURNING old.inf_id,
              old.status_cd
         INTO l_inf_id,
              l_prev_status_cd;

   IF FOUND THEN

      p_res_Code := ret_OK;
      p_res_Info := null;

      CALL MI_logger.info( cLogger, 'Request moved to error', l_inf_id, p_req_id, NULL::varchar, cAction_Name, NULL::varchar, cPkg_Name );

      RETURN;

   END IF;

   SELECT r.inf_id,
          r.status_cd
     INTO l_inf_id,
          l_prev_status_cd
     FROM xxi.mi_req r
    WHERE r.req_id = p_req_id;

   IF NOT FOUND THEN
      p_res_Info := 'Не найден запрос с req_id = ' || p_req_id;

   ELSIF l_prev_status_cd = cStatus_error THEN
      p_res_Info := 'Не возможно перевести запрос в статус "ошибка". Т.к. он уже находится в ошибочном статусе.';

   ELSIF l_prev_status_cd = cStatus_done THEN
      p_res_Info := 'Не возможно перевести запрос в статус "ошибка". Т.к. он уже успешно обработан.';

   ELSIF l_prev_status_cd = cStatus_new THEN
      p_res_Info := 'Не возможно перевести запрос в статус "ошибка". Т.к. он ещё не был взят в обработку.';

   ELSE
      p_res_Info := 'Не возможно перевести запрос в статус "ошибка". Текущий статус: '
                       || coalesce(l_prev_status_cd::varchar, '<NULL>');
   END IF;

   CALL MI_logger.info( cLogger, 'to_Error rejected', l_inf_id, p_req_id, p_res_Info, cAction_Name, NULL::varchar, cPkg_Name );

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
      
            CALL MI_logger.error( 
                 cLogger, 
                 'to_Error failed',
                 l_inf_id, p_req_id, 
                 TS.WhenOthersError( cPkg_Name || '.to_Error', ex ), 'exception', NULL::varchar, cPkg_Name 
            );

      END; 

   RAISE;

END;
$procedure$


/** */
CREATE PROCEDURE reset(
   in  p_req_id   numeric,
   in  p_info     varchar,
   out p_res_Code int4,
   out p_res_Info varchar
)
AS
$procedure$
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
   LANGUAGE
      plpgsql
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
   LANGUAGE plpgsql
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

   l_sqlstate text;
   l_message  text;
   l_detail   text;
   l_hint     text;
   l_context  text;
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
/* end_Of_Package */
;
