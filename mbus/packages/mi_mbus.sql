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

   -- Загружаем параметры запросы контейнера.
   BEGIN
      SELECT e.inf_id,
             e.req_id,
             e.status_cd,
             p.wsp_id,
             p.gate_alias,
             coalesce(p.request_queue,  'xxi_pg_out') AS request_queue,
             p.request_ttl_ms,
             coalesce(p.response_queue, 'xxi_pg_in')  AS response_queue,
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

      p_result := MI_resultCtx.ok(
         p_result_code => c_res_Already_Completed,
         p_result_info => 'Request is already completed',
         p_parameters  => jsonb_build_object( 'req_id', p_req_id, 'status_cd', r_request.status_cd, 'call_uuid', l_call_uuid )
      );

      CALL MI_logger.log_exec_result(
         p_logger_name => cLogger, p_result => p_result, p_inf_id => r_request.inf_id, p_req_id => p_req_id, p_action_cd => 'send_state', p_context_value => p_result.result_code, p_object_name => cAction_Name
      );

      RETURN;

   ELSIF r_request.status_cd NOT IN (0, -1) THEN

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
      p_logger_name   => cLogger, p_variable_name => 'XXLResponse.SOUT', p_value_text => l_result_x, p_inf_id => r_request.inf_id, p_req_id => p_req_id 
   );

   -- mbus вернул не успех
   IF coalesce(l_result_code, -1) <> 0 THEN

      CALL MI_resultCtx.raise_fail(
         p_result_code => c_err_Bus_Return,
         p_result_info => 'Ошибка вызова cbs_Bus_X.query_Bus_Text',
         p_cause_code  => 'MBUS_ERROR',
         p_cause_info  => l_result_info,
         p_parameters  => jsonb_build_object(
                            'req_id', p_req_id,
                            'inf_id', r_request.inf_id,
                            'wsp_id', r_request.wsp_id,
                            'status_cd', r_request.status_cd,

                            'call_uuid', l_call_uuid,
                            'bus_result_code', l_result_code,
                            'bus_corr_id', l_result_corr,

                            'request_queue', r_request.request_queue,
                            'response_queue', r_request.response_queue,
                            'gate_alias', r_request.gate_alias,
                            'request_ttl_ms', r_request.request_ttl_ms,

                            'request_payload', jsonb_build_object(
                               'format', 'xml',
                               'body', l_send_x
                            )
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

   CALL MI_logger.exit_f(
      p_logger_name  => cLogger,
      p_message_text => 'send_request finished',
      p_inf_id       => r_request.inf_id,
      p_req_id       => p_req_id,
      p_details_text => jsonb_build_object(
                           'result_code', p_result.result_code,
                           'is_success', p_result.is_success,
                           'call_uuid', l_call_uuid
                        )::text
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
      
          l_error_Text := TS.WhenOthersError('mi_mbus.send_request', ex);

         /*
            Любая ошибка, ожидаемая или неожиданная,
            превращается в MI_resultCtx.exec_Result.
         */
         p_result := MI_resultCtx.from_exception(
            p_sqlstate => ex_sqlstate,
            p_message  => ex_message,
            p_detail   => ex_detail,
            p_hint     => ex_hint
         );

      /*
         Если это не наше структурированное MI001-исключение,
         добавим технический контекст.
      */
      IF ex_sqlstate IS DISTINCT FROM 'MI001' THEN
         p_result.is_success  := false;
         p_result.result_code := coalesce(p_result.result_code, c_err_Unexpected);
         p_result.result_info := coalesce(p_result.result_info, 'Unexpected error in ' || cAction_Name);

         p_result.parameters :=
            coalesce(p_result.parameters, '{}'::jsonb)
            || jsonb_build_object(
                  'req_id', p_req_id,
                  'inf_id', l_inf_id,
                  'wsp_id', l_wsp_id,
                  'call_uuid', l_call_uuid,
                  'sqlstate', ex_sqlstate,
                  'message', ex_message,
                  'detail', ex_detail,
                  'hint', ex_hint,
                  'context', ex_context
               );
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

-- end_Of_Package
;