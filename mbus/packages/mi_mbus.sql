CREATE OR REPLACE PACKAGE MI_mbus
CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
DECLARE

   cVersion            CONSTANT varchar(100) := '$id: {2.0.0} {14.03.2026} Sulimoff$';
   cPkg_Name           CONSTANT varchar(20 ) := 'mi_mbus';

   cMultiBus_Gate      CONSTANT varchar(50 ) := 'r-xxl-gate';

   ret_OK              CONSTANT integer := 0;
   ret_Fail            CONSTANT integer := -1;

   cLogger             CONSTANT varchar(20) := 'mi.mbus';

   -- result codes: success / idempotent
   c_res_Send_Published       CONSTANT varchar(200) := 'SEND_PUBLISHED';
   c_res_Send_Accepted        CONSTANT varchar(200) := 'SEND_ACCEPTED';
   c_res_Sync_Completed       CONSTANT varchar(200) := 'SYNC_COMPLETED';

   c_res_Already_In_Progress  CONSTANT varchar(200) := 'ALREADY_IN_PROGRESS';
   c_res_Already_Sent         CONSTANT varchar(200) := 'ALREADY_SENT';
   c_res_Already_Completed    CONSTANT varchar(200) := 'ALREADY_COMPLETED';

   -- result codes: local MI_mbus errors
   c_err_Not_Found            CONSTANT varchar(200) := 'MI_MBUS.SEND_REQUEST#REQUEST_NOT_FOUND_IN_X';
   c_err_Bad_Status           CONSTANT varchar(200) := 'MI_MBUS.SEND_REQUEST#BAD_STATUS';
   c_err_Bus_Return           CONSTANT varchar(200) := 'MI_MBUS.SEND_REQUEST#X_TO_XXL_TRANSPORT_ERROR';
   c_err_Empty_Response       CONSTANT varchar(200) := 'MI_MBUS.SEND_REQUEST#XXL_RESPONSE_EMPTY';
   c_err_Response_Parse       CONSTANT varchar(200) := 'MI_MBUS.SEND_REQUEST#XXL_RESPONSE_PARSE_ERROR';
   c_err_Unexpected           CONSTANT varchar(200) := 'MI_MBUS.SEND_REQUEST#UNEXPECTED';

   -- result codes: local MI_mbus.send_Command errors
   c_err_Command_Invalid_Inf       CONSTANT varchar(200) := 'MI_MBUS.SEND_COMMAND#INVALID_INF_ID';
   c_err_Command_Inf_Not_Found     CONSTANT varchar(200) := 'MI_MBUS.SEND_COMMAND#INF_NOT_FOUND';
   c_err_Command_Action_Required   CONSTANT varchar(200) := 'MI_MBUS.SEND_COMMAND#ACTION_REQUIRED';
   c_err_Command_Bad_Parameters    CONSTANT varchar(200) := 'MI_MBUS.SEND_COMMAND#INVALID_PARAMETERS';
   c_err_Command_Bus_Return        CONSTANT varchar(200) := 'MI_MBUS.SEND_COMMAND#X_TO_XXL_TRANSPORT_ERROR';
   c_err_Command_Empty_Response    CONSTANT varchar(200) := 'MI_MBUS.SEND_COMMAND#XXL_RESPONSE_EMPTY';
   c_err_Command_Response_Parse    CONSTANT varchar(200) := 'MI_MBUS.SEND_COMMAND#XXL_RESPONSE_PARSE_ERROR';
   c_err_Command_Unexpected        CONSTANT varchar(200) := 'MI_MBUS.SEND_COMMAND#UNEXPECTED';   

BEGIN
   RAISE DEBUG 'Package "mi_mbus" - % - initialized', cVersion;
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


/* Отправка одного контейнера mi_req в XXL */
CREATE PROCEDURE send_request (
   IN  p_req_id  numeric,
   OUT p_result  MI_resultCtx.exec_Result
)
AS
$procedure$
   #package
DECLARE

   cAction_Name CONSTANT varchar(50) := cPkg_Name || '.send_request';

   r_request      record;

   l_result_info  varchar;
   l_result_x     text;
   l_result_code  numeric;
   l_result_corr  varchar;

   l_send_x       text;

   l_call_uuid    uuid        := gen_random_uuid();
   l_called_at    timestamptz := clock_timestamp();

   l_inf_id       numeric;
   l_wsp_id       numeric;

BEGIN

   CALL MI_logger.enter_f( 
      p_logger_name   => cLogger, p_function_name => cAction_Name, p_message_text  => 'Отправка запроса в ' || cMultiBus_Gate, 
      p_parameters    => jsonb_build_object('req_id', p_req_id, 'call_uuid', l_call_uuid )::text,
      p_req_id        => p_req_id
   );

   IF p_req_id IS NULL THEN
      CALL MI_resultCtx.raise_fail( p_result_Code => c_err_Not_Found, p_result_Info => 'p_req_id is required', 
                                    p_parameters  => jsonb_build_object( 'req_id', p_req_id,'call_uuid', l_call_uuid ) );
   END IF;

   -- Загружаем параметры запроса
   BEGIN

      SELECT e.inf_id,
             e.req_id,
             e.status_cd,
             p.wsp_id,
             p.gate_alias,
             coalesce( p.request_queue,  'xxi_pg_out') AS request_queue,
             p.request_ttl_ms,
             coalesce( p.response_queue, 'xxi_pg_in' )  AS response_queue,
             e.correlation_id,
             e.external_uuid
        INTO 
             STRICT 
                r_request
        FROM xxi.mi_req e
        JOIN xxi.mi_inf p
          ON p.inf_id = e.inf_id
       WHERE e.req_id = p_req_id;

      l_inf_id := r_request.inf_id;
      l_wsp_id := r_request.wsp_id;

   EXCEPTION
      WHEN NO_DATA_FOUND THEN
           CALL MI_resultCtx.raise_failed( p_result_code => c_err_Not_Found, p_result_info => 'Request not found in xxi.mi_req', 
                                           p_parameters  => jsonb_build_object( 'req_id', p_req_id,'call_uuid', l_call_uuid ));
   END;

   -- Повторный send не ошибка, если контейнер уже в маршруте.
   IF r_request.status_cd = 2 THEN

      p_result := MI_resultCtx.OK (
         p_result_code => c_res_Already_In_Progress,
         p_result_info => 'Request is already in progress',
         p_parameters  => jsonb_build_object( 'req_id', p_req_id, 'status_cd', r_request.status_cd, 'call_uuid', l_call_uuid )
      );

      CALL MI_logger.log_exec_result (
         p_logger_name => cLogger, p_result => p_result, p_inf_id => r_request.inf_id, p_req_id => p_req_id, p_action_cd => 'send_state', p_context_value => p_result.result_code, p_object_name => cAction_Name 
      );

      RETURN;

   ELSIF r_request.status_cd = 3 THEN

      p_result := MI_resultCtx.OK (
         p_result_code => c_res_Already_Sent,
         p_result_info => 'Request is already sent, waiting item responses',
         p_parameters  => jsonb_build_object( 'req_id', p_req_id, 'status_cd', r_request.status_cd, 'call_uuid', l_call_uuid)
      );

      CALL MI_logger.log_exec_result(
         p_logger_name => cLogger, p_result => p_result, p_inf_id => r_request.inf_id, p_req_id => p_req_id, p_action_cd => 'send_state', p_context_value => p_result.result_code, p_object_name => cAction_Name
      );

      RETURN;

   ELSIF r_request.status_cd = 1 THEN

      p_result := MI_resultCtx.OK (
         p_result_code => c_res_Already_Completed,
         p_result_info => 'Request is already completed',
         p_parameters  => jsonb_build_object( 'req_id', p_req_id, 'status_cd', r_request.status_cd, 'call_uuid', l_call_uuid )
      );

      CALL MI_logger.log_exec_result(
         p_logger_name => cLogger, p_result => p_result, p_inf_id => r_request.inf_id, p_req_id => p_req_id, p_action_cd => 'send_state', p_context_value => p_result.result_code, p_object_name => cAction_Name
      );

      RETURN;

   ELSIF r_request.status_cd NOT IN ( 0,-1 ) THEN

      CALL MI_resultCtx.raise_fail (
         p_result_code => c_err_Bad_Status,
         p_result_info => 'Invalid request status for send',
         p_parameters  => jsonb_build_object( 'req_id', p_req_id, 'status_cd', r_request.status_cd, 'call_uuid', l_call_uuid  )
      );

   END IF;

   /*
      Настройки транспорта.
   */
   IF r_request.gate_alias IS NULL THEN
      r_request.gate_alias :=
         MI_prp.get_sys_property('MBUS_GATE', cMultiBus_Gate)::varchar;
   END IF;

   IF r_request.request_ttl_ms IS NULL THEN
      r_request.request_ttl_ms :=
         MI_prp.get_sys_property('MBUS_REQUEST_TIMEOUT', '30000')::numeric;
   END IF;

   SELECT xmlserialize(
             content xmlelement(
                name "XXLRequest",
                xmlattributes(
                   '1.0'                           AS "version",
                   'send'                          AS "action",
                   'auto'                          AS "mode",

                   p_req_id::varchar               AS "req_id",
                   r_request.wsp_id::varchar       AS "wsp_id",
                   r_request.inf_id::varchar       AS "inf_id",

                   r_request.correlation_id::text  AS "correlation_id",
                   r_request.external_uuid::text   AS "external_uuid",
                   l_call_uuid::text               AS "call_uuid",

                   to_char( l_called_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS TZH:TZM' ) AS "timestamp"
                )
             )
             AS text
          )
     INTO l_send_x;

   CALL MI_logger.variable_Value(
      p_logger_name   => cLogger,
      p_variable_name => 'XXLRequest',
      p_value_text    => l_send_x,
      p_inf_id        => r_request.inf_id,
      p_req_id        => p_req_id
   );

   /*
      Вызов XXL через MBUS.

      Важно:
      если query_Bus_Text вернул ошибку, НЕ вызываем to_Error.
      Это transport uncertainty: X не знает, получил XXL команду или нет.
   */
   CALL cbs_Bus_X.query_Bus_Text(

      cSqueue_name => r_request.request_queue::varchar,
      cDqueue_name => r_request.response_queue::varchar,

      cXml         => l_send_x::text,

      busType      => r_request.gate_alias::varchar,
      nWait        => r_request.request_ttl_ms::numeric,

      SOUT         => l_result_x,

      ERRORMSG     => l_result_info,
      
      cCor         => l_result_corr,
      res          => l_result_code
   );

   CALL MI_logger.variable_Value(
      p_logger_name=> cLogger, p_variable_name => 'query_Bus_Text.SOUT', p_value_text => l_result_x, p_inf_id => r_request.inf_id, p_req_id => p_req_id 
   );

   -- mbus вернул не успех
   IF coalesce(l_result_code, -1) <> 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => c_err_Bus_Return,
         p_result_info => 'Ошибка вызова cbs_Bus_X.query_Bus_Text',
         p_cause_code  => 'MBUS_ERROR',
         p_cause_info  => l_result_info,
         p_parameters  => jsonb_build_object (
                            'req_id',    p_req_id,
                            'inf_id',    r_request.inf_id,
                            'status_cd', r_request.status_cd,
                            'call_uuid', l_call_uuid,
                            'bus_result_code', l_result_code,
                            'bus_corr_id',     l_result_corr,
                            'request_queue',   r_request.request_queue,
                            'response_queue',  r_request.response_queue,
                            'gate_alias',      r_request.gate_alias,
                            'request_ttl_ms',  r_request.request_ttl_ms,
                            'request_payload', jsonb_build_object( 'format', 'xml', 'body', l_send_x )
                         )
      );

   END IF;

   /*
      Транспортный вызов прошёл, смотрим что вернул XXLResponse.
   */
   IF nullif(btrim(l_result_x), '') IS NULL THEN
      
      CALL MI_resultCtx.raise_fail(
         p_result_code => c_err_Empty_Response,
         p_result_info => 'XXLResponse is empty',
         p_parameters  => jsonb_build_object( 'req_id', p_req_id, 'inf_id', r_request.inf_id, 'call_uuid', l_call_uuid, 'bus_corr_id', l_result_corr )
      );

   END IF;

   /*
      Разбор XML ответа XXL.
      Ошибка разбора — ожидаемая интеграционная ошибка,
      поэтому превращается в structured failure через raise_fail.
   */
   BEGIN
      p_result := MI_resultCtx.result_from_xml(l_result_x);
   EXCEPTION
      WHEN OTHERS THEN
         CALL MI_resultCtx.raise_fail(
            p_result_code => c_err_Response_Parse,
            p_result_info => 'Ошибка разбора XXLResponse',
            p_cause_code  => SQLSTATE,
            p_cause_info  => SQLERRM,
            p_parameters  => jsonb_build_object( 'req_id', p_req_id, 'inf_id', r_request.inf_id, 'call_uuid', l_call_uuid, 'bus_corr_id', l_result_corr, 'response_xml', l_result_x )
         );
   END;

   /*
      На этом send_request не двигает статус.
      Если XXL вернул SEND_PUBLISHED, значит XXL уже сам вызвал to_Sent.
      Если XXL вернул ошибку после take_For_Proc, значит XXL сам вызвал to_Error,
      если это container-level failure.
   */
   CALL MI_logger.log_exec_result(
      p_logger_name   => cLogger,
      p_result        => p_result,
      p_inf_id        => r_request.inf_id,
      p_req_id        => p_req_id,
      p_action_cd     => 'xxl_result',
      p_context_value => p_result.result_code,
      p_object_name   => cAction_Name
   );

   CALL MI_logger.exit_f (
      p_logger_name  => cLogger,
      p_message_text => 'send_request finished',
      p_inf_id       => r_request.inf_id,
      p_req_id       => p_req_id,
      p_details_text => 
              jsonb_build_object( 'result_code', p_result.result_code, 'is_success', p_result.is_success, 'call_uuid', l_call_uuid )::text
   );

   RETURN;

EXCEPTION

   WHEN OTHERS THEN
   DECLARE
      ex TS.T_StackedDiagnostics;
      l_error_Text varchar;
   begin
      GET STACKED DIAGNOSTICS
          ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,  
          ex.MESSAGE_TEXT         = MESSAGE_TEXT,
          ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
          ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
          ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;   
      
          l_error_Text := TS.WhenOthersError( cAction_Name, ex);

         /*
            Любая ошибка, ожидаемая или неожиданная,
            превращается в MI_resultCtx.exec_Result.
         */
         p_result := MI_resultCtx.from_exception (
            p_sqlstate => ex.returned_sqlstate,
            p_message  => ex.message_text,
            p_detail   => ex.pg_exception_detail,
            p_hint     => ex.pg_exception_hint
         );

      /*
         Если это не наше структурированное MI001-исключение,
         добавим технический контекст.
      */
      IF ex.returned_sqlstate IS DISTINCT FROM 'MI001' THEN

         p_result.is_success  := false;
         p_result.result_code := coalesce( p_result.result_code, c_err_Unexpected );
         p_result.result_info := coalesce( p_result.result_info, 'Unexpected error in ' || cAction_Name );

         p_result.parameters :=
            coalesce( p_result.parameters, '{}'::jsonb ) || jsonb_build_object( 'error_info', l_error_Text );
            
      END IF;

      /*
         Логируем итоговый exec_result.
         Наружу exception не пробрасываем.
      */
      CALL MI_logger.log_exec_result(
         p_logger_name   => cLogger,
         p_result        => p_result,
         p_inf_id        => l_inf_id,
         p_req_id        => p_req_id,
         p_action_cd     => 'exception',
         p_context_value => p_result.result_code,
         p_object_name   => cAction_Name
      );

      RETURN;

   end;   
END;
$procedure$


/*
 * Отправка команды в XXL.
 *
 * Маршрутизация:
 *
 *    p_inf_id IS NULL: команда адресована XXL целиком;
 *    p_inf_id > 0    : команда адресована конкретному виду сведений;
 *    p_inf_id <= 0   : ошибка контракта.
 *
 * Команда определяется парой: inf_id + action
 *
 * Для глобальной, для всего XXL, команды:    NULL + action
 *
 * Значения параметров команды не записываются в лог.
 * Пишем только ключи, количество и размер XML.
 */
CREATE PROCEDURE send_Command (
   OUT p_result     MI_resultCtx.exec_Result,

   IN  p_action     varchar,
   
   IN  p_inf_id     numeric DEFAULT NULL,
   IN  p_req_id     numeric DEFAULT NULL,

   IN  p_parameters jsonb   DEFAULT '{}'::jsonb
)
AS
$procedure$
   #package
DECLARE

   cAction_Name CONSTANT varchar(50) := cPkg_Name || '.send_Command';

   /* Нормализованные параметры команды. */
   l_action     varchar;
   l_parameters jsonb;
   l_scope      varchar(10);

   /*
    * Для безопасного логирования параметров.
    * Значения параметров не логируются.
    */
   l_parameter_keys  text[] := ARRAY[]::text[];
   l_parameter_count integer := 0;

   /*
    * Настройки транспорта.
    *
    * Используются отдельные переменные, а не record,
    * поскольку для глобальной команды строка mi_inf
    * не загружается.
    */
   l_gate_alias      varchar;
   l_request_queue   varchar;
   l_response_queue  varchar;
   l_request_ttl_ms  numeric;

   /*
    * XML request/response.
    */
   l_send_x   text;
   l_result_x text;

   /*
    * Результат Multi-Bus.
    */
   l_result_info varchar;
   l_result_code numeric;
   l_result_corr varchar;

   l_call_uuid   uuid := gen_random_uuid();

   l_called_at   timestamptz := clock_timestamp();

BEGIN

   /*
    * Нормализация входных значений.
    */
   l_action     := lower( btrim(p_action) );
   l_parameters := coalesce( p_parameters, '{}'::jsonb );
   l_scope :=
      CASE
         WHEN p_req_id IS NOT NULL THEN 'REQUEST'
         WHEN p_inf_id IS NOT NULL THEN 'INF'
         ELSE 'XXL'
      END;
      
   /*
    * Безопасно получаем только список ключей.
    *
    * jsonb_object_keys вызывается только для JSON object,
    * чтобы некорректный тип параметров был обработан ниже
    * как структурированная ошибка контракта.
    */
   IF jsonb_typeof(l_parameters) = 'object' THEN

      SELECT
         coalesce(
            array_agg(p.key ORDER BY p.key),
            ARRAY[]::text[]
         ),
         count(*)::integer
      INTO
         l_parameter_keys,
         l_parameter_count
      FROM jsonb_object_keys(l_parameters) AS p(key);

   END IF;

   CALL MI_logger.enter_f( p_logger_name => cLogger, p_function_name => cAction_Name, p_message_text => 'Sending command to ' || cMultiBus_Gate,
         p_parameters =>
         jsonb_build_object(
            'scope',           l_scope,
            'inf_id',          p_inf_id,
            'req_id',          p_req_id,
            'action',          l_action,
            'call_uuid',       l_call_uuid,
            'parameter_keys',  l_parameter_keys,
            'parameter_count', l_parameter_count
         )::text,
         p_req_id =>p_req_id
   );

   /*
    * NULL означает глобальную команду XXL.
    * Нулевые и отрицательные значения запрещены:
    */
   IF p_inf_id IS NOT NULL AND p_inf_id <= 0
   THEN

      CALL MI_resultCtx.raise_fail( p_result_code => c_err_Command_Invalid_Inf, p_result_info => 'p_inf_id must be positive or null',
         p_parameters =>
            jsonb_build_object( 'scope', l_scope, 'inf_id', p_inf_id, 'req_id', p_req_id, 'action', l_action, 'call_uuid', l_call_uuid )
      );

   END IF;

   /*
    * Action является обязательной частью ключа маршрутизации.
    */
   IF nullif( l_action, '' ) IS NULL THEN

      CALL MI_resultCtx.raise_fail( p_result_code => c_err_Command_Action_Required, p_result_info => 'p_action is required',
         p_parameters =>
            jsonb_build_object( 'scope', l_scope, 'inf_id', p_inf_id, 'req_id', p_req_id, 'action', l_action, 'call_uuid', l_call_uuid )
      );

   END IF;

   /*
    * Параметры команды должны представлять map.
    */
   IF jsonb_typeof(l_parameters) <> 'object' THEN

      CALL MI_resultCtx.raise_fail( p_result_code => c_err_Command_Bad_Parameters, p_result_info => 'p_parameters must be a JSON object',
         p_parameters =>
            jsonb_build_object(
               'scope',           l_scope,
               'inf_id',          p_inf_id,
               'req_id',          p_req_id,
               'action',          l_action,
               'call_uuid',       l_call_uuid,
               'parameters_type', jsonb_typeof(l_parameters)
            )
      );

   END IF;

   /*
    * Настройки транспорта для команды конкретного inf_id, берутся из xxi.mi_inf.
    */
   IF p_inf_id IS NOT NULL THEN

      BEGIN

         SELECT
            p.gate_alias,
            coalesce( p.request_queue, 'xxi_pg_out' ),
            coalesce( p.response_queue,'xxi_pg_in'  ),
            p.request_ttl_ms
         INTO 
              STRICT
              l_gate_alias,
              l_request_queue,
              l_response_queue,
              l_request_ttl_ms
         FROM 
              xxi.mi_inf p
         WHERE
              p.inf_id = p_inf_id;

      EXCEPTION
         WHEN NO_DATA_FOUND THEN

            CALL MI_resultCtx.raise_fail( p_result_code => c_err_Command_Inf_Not_Found, p_result_info => 'Information type not found in xxi.mi_inf',
               p_parameters =>
                  jsonb_build_object( 'scope', l_scope, 'inf_id', p_inf_id, 'action', l_action, 'call_uuid', l_call_uuid )
            );

      END;

   /*
    * Глобальная команда адресована XXL целиком.
    *
    * Она не связана с записью xxi.mi_inf, поэтому
    * используются общие очереди и системные настройки.
    */
   ELSE

      l_request_queue  :='xxi_pg_out';
      l_response_queue :='xxi_pg_in';
      l_gate_alias     := NULL;
      l_request_ttl_ms := NULL;

   END IF;

   /* Общие настройки транспорта. */
   IF l_gate_alias IS NULL THEN
      l_gate_alias := MI_prp.get_sys_property( 'MBUS_GATE', cMultiBus_Gate )::varchar;
   END IF;

   IF l_request_ttl_ms IS NULL THEN
      l_request_ttl_ms := MI_prp.get_sys_property( 'MBUS_REQUEST_TIMEOUT', '30000' )::numeric;
   END IF;

   /*
    * Формируем XXLRequest.
    */
   SELECT
      xmlserialize(
         content xmlelement (
            name "XXLRequest",

            xmlattributes (
               '1.0'
                  AS "version",

               l_action
                  AS "action",

               p_req_id::varchar
                  AS "req_id",

               p_inf_id::varchar
                  AS "inf_id",

               l_call_uuid::text
                  AS "call_uuid",

               to_char(
                  l_called_at,
                  'YYYY-MM-DD"T"HH24:MI:SS.MS TZH:TZM'
               )
                  AS "timestamp"
            ),
            xmlelement(
               name "parameters",
               l_parameters::text
            )
         )
         AS text
      )
   INTO
      l_send_x;

   /*
    * Полный XML не логируется, поскольку parameters
    * могут содержать закрытые значения.
    */
   CALL MI_logger.variable_Value(
      p_logger_name   => cLogger,
      p_variable_name => 'XXLCommand.meta',
      p_value_text =>
         jsonb_build_object(
            'scope',           l_scope,
            'inf_id',          p_inf_id,
            'req_id',          p_req_id,
            'action',          l_action,
            'call_uuid',       l_call_uuid,
            'request_size',    octet_length(l_send_x),
            'parameter_keys',  l_parameter_keys,
            'parameter_count', l_parameter_count
         )::text,
         p_inf_id => p_inf_id,
         p_req_id => p_req_id
   );

   /*
    * Синхронный request/reply транспортного уровня.
    *
    * Это не означает, что прикладная команда выполняется
    * синхронно. Например, auto_prepare только ставит
    * фоновое задание и возвращает job_id.
    */
   CALL cbs_Bus_X.query_Bus_Text(
      cSqueue_name =>l_request_queue::varchar,
      cDqueue_name =>l_response_queue::varchar,
      cXml =>        l_send_x::text,
      busType =>     l_gate_alias::varchar,
      nWait =>       l_request_ttl_ms::numeric,
      SOUT        => l_result_x,
      ERRORMSG    => l_result_info,
      cCor        => l_result_corr,
      res         => l_result_code
   );

   /*
    * Полный XXLResponse не пишется в диагностический лог.
    */
   CALL MI_logger.variable_Value(
      p_logger_name =>
         cLogger,
      p_variable_name =>
         'query_Bus_Text.SOUT.meta',
      p_value_text =>
         jsonb_build_object(
            'scope',         l_scope,
            'inf_id',        p_inf_id,
            'req_id',        p_req_id,
            'action',        l_action,
            'call_uuid',     l_call_uuid,
            'bus_corr_id',   l_result_corr,
            'bus_result',    l_result_code,
            'response_size', octet_length(coalesce(l_result_x, '') )
         )::text,

      p_inf_id => p_inf_id,
      p_req_id => p_req_id
   );

   /*
    * Обработка ошибки Multi-Bus
    * фиксируется сам факт ошибки,
    * никаких действий не производится -
    * тк не ясно выполнилась в XXL команда или нет
    */
   IF coalesce( l_result_code, ret_Fail ) <> ret_OK
   THEN
      CALL MI_resultCtx.raise_fail(
         p_result_code => c_err_Command_Bus_Return,
         p_result_info => 'Error calling cbs_Bus_X.query_Bus_Text',
         p_cause_code  =>'MBUS_ERROR',
         p_cause_info  => l_result_info,
         p_parameters  =>
            jsonb_build_object(
               'scope',           l_scope,
               'inf_id',          p_inf_id,
               'req_id',          p_req_id,
               'action',          l_action,
               'call_uuid',       l_call_uuid,
               'bus_result_code', l_result_code,
               'bus_corr_id',     l_result_corr,
               'request_queue',   l_request_queue,
               'response_queue',  l_response_queue,
               'gate_alias',      l_gate_alias,
               'request_ttl_ms',  l_request_ttl_ms,
               'parameter_keys',  l_parameter_keys,
               'parameter_count', l_parameter_count
            )
      );

   END IF;

   /*
    * Транспортный вызов завершился успешно,
    * но тело XXLResponse отсутствует.
    */
   IF nullif( btrim(l_result_x),'') IS NULL
   THEN

      CALL MI_resultCtx.raise_fail( p_result_code => c_err_Command_Empty_Response, p_result_info => 'XXLResponse is empty',
         p_parameters =>
            jsonb_build_object(
               'scope',         l_scope,
               'inf_id',        p_inf_id,
               'req_id',        p_req_id,
               'action',        l_action,
               'call_uuid',     l_call_uuid,
               'bus_corr_id',   l_result_corr,
               'response_size', 0
            )
      );

   END IF;

   /*
    * Разбор XXLResponse,
    */
   BEGIN
      p_result := MI_resultCtx.result_from_xml( l_result_x );
   EXCEPTION
      WHEN OTHERS THEN

         CALL MI_resultCtx.raise_fail( p_result_code => c_err_Command_Response_Parse,
            p_result_info =>'Error parsing XXLResponse',
            p_cause_code  => SQLSTATE,
            p_cause_info  => SQLERRM,
            p_parameters  =>
               jsonb_build_object(
                  'scope',         l_scope,
                  'inf_id',        p_inf_id,
                  'req_id',        p_req_id,
                  'action',        l_action,
                  'call_uuid',     l_call_uuid,
                  'bus_corr_id',   l_result_corr,
                  'response_size', octet_length( coalesce(l_result_x, '') )
               )
         );

   END;

   /*
    * Результат XXL сохраняется без изменения:
    */
   p_result.parameters := coalesce( p_result.parameters, '{}'::jsonb ) || jsonb_build_object (
         'scope',       l_scope,
         'inf_id',      p_inf_id,
         'req_id',      p_req_id,
         'action',      l_action,
         'call_uuid',   l_call_uuid,
         'bus_corr_id', l_result_corr
      );

   /*
    * Итоговый результат XXL.
    */
   CALL MI_logger.log_exec_result(
      p_logger_name => cLogger,
      p_result      => p_result,
      p_inf_id      => p_inf_id,
      p_req_id      => p_req_id,
      p_action_cd   => 'xxl_command_result',
      p_context_value
                    => p_result.result_code,
      p_object_name => cAction_Name
   );

   CALL MI_logger.exit_f (
      p_logger_name  => cLogger,
      p_message_text => 'send_Command finished',
      p_inf_id       => p_inf_id,
      p_req_id       => p_req_id,
      p_details_text =>
         jsonb_build_object(
            'result_code', p_result.result_code,
            'is_success',  p_result.is_success,
            'scope',       l_scope,
            'inf_id',      p_inf_id,
            'action',      l_action,
            'call_uuid',   l_call_uuid,
            'bus_corr_id', l_result_corr
         )::text
   );

   RETURN;

EXCEPTION
   WHEN OTHERS THEN
   DECLARE
      ex TS.T_StackedDiagnostics;
      l_error_Text varchar;
   BEGIN

      GET STACKED DIAGNOSTICS
         ex.RETURNED_SQLSTATE   = RETURNED_SQLSTATE,
         ex.MESSAGE_TEXT        = MESSAGE_TEXT,
         ex.PG_EXCEPTION_DETAIL = PG_EXCEPTION_DETAIL,
         ex.PG_EXCEPTION_HINT   = PG_EXCEPTION_HINT,
         ex.PG_EXCEPTION_CONTEXT= PG_EXCEPTION_CONTEXT;

         l_error_Text := TS.WhenOthersError( cAction_Name, ex );

      /*
       * Как и send_request, процедура не пробрасывает
       * исключение наружу.
       *
       * Любая ошибка преобразуется в exec_Result.
       */
      p_result :=
         MI_resultCtx.from_exception( 
            p_sqlstate => ex.returned_sqlstate,
            p_message  => ex.message_text,
            p_detail   => ex.pg_exception_detail,
            p_hint     => ex.pg_exception_hint
         );

      /*
       * MI001 означает структурированную ошибку,
       * сформированную MI_resultCtx.raise_fail.
       *
       * Для остальных исключений задаётся локальный
       * result_code процедуры.
       */
      IF ex.returned_sqlstate IS DISTINCT FROM 'MI001' THEN
         p_result.is_success := false;
         p_result.result_code:= coalesce( p_result.result_code, c_err_Command_Unexpected );
         p_result.result_info:= coalesce( p_result.result_info, 'Unexpected error in ' || cAction_Name );
         p_result.parameters := coalesce( p_result.parameters, '{}'::jsonb ) || jsonb_build_object('error_info', l_error_Text );
      END IF;

      /*
       * Добавляем корреляционный контекст независимо
       * от типа исключения.
       *
       * Значения p_parameters не включаются.
       */
      p_result.parameters := coalesce( p_result.parameters, '{}'::jsonb )
         ||
         jsonb_build_object(
            'scope',           l_scope,
            'inf_id',          p_inf_id,
            'req_id',          p_req_id,
            'action',          l_action,
            'call_uuid',       l_call_uuid,
            'bus_corr_id',     l_result_corr,
            'parameter_keys',  l_parameter_keys,
            'parameter_count', l_parameter_count
         );

      CALL MI_logger.log_exec_result(
         p_logger_name => cLogger,
         p_result      => p_result,
         p_inf_id      => p_inf_id,
         p_req_id      => p_req_id,
         p_action_cd   => 'exception',
         p_context_value 
                       => p_result.result_code,
         p_object_name => cAction_Name
      );

      RETURN;

   END;
END;
$procedure$;

-- end_Of_Package
;