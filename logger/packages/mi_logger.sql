CREATE OR REPLACE PACKAGE mi_logger
CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
DECLARE

   cVersion CONSTANT varchar(100) := '$id: {1.1.0} {28.06.2026} $';

   cMode_Off        CONSTANT numeric := 0;
   cMode_Raise_Only CONSTANT numeric := 1;
   cMode_All        CONSTANT numeric := 2;

   cLevel_Trc CONSTANT bpchar(3) := 'trc';
   cLevel_Dbg CONSTANT bpchar(3) := 'dbg';
   cLevel_Inf CONSTANT bpchar(3) := 'inf';
   cLevel_Wrn CONSTANT bpchar(3) := 'wrn';
   cLevel_Err CONSTANT bpchar(3) := 'err';

   g_mode          numeric       := 2;
   g_default_level bpchar(3)     := 'dbg';

BEGIN
   RAISE DEBUG 'Package "mi_logger" - % - initialized', cVersion;
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


/* Режимы */
CREATE PROCEDURE enable_Log()
AS
$procedure$
   #package
BEGIN
   g_mode := cMode_All;
END;
$procedure$


/* */
CREATE PROCEDURE disable_Log()
AS
$procedure$
   #package
BEGIN
   g_mode := cMode_Off;
END;
$procedure$


/* */
CREATE PROCEDURE set_Raise_Only()
AS
$procedure$
   #package
BEGIN
   g_mode := cMode_Raise_Only;
END;
$procedure$


/* */
CREATE PROCEDURE set_Default_Level(
   in p_level_cd bpchar
)
AS
$procedure$
   #package
BEGIN
   g_default_level := p_level_cd;
END;
$procedure$


/* rank уровня для сравнения */
CREATE FUNCTION level_Rank (
   in p_level_cd bpchar
)
   RETURNS numeric
AS
$function$
   #package
   #private
BEGIN
   RETURN CASE trim(coalesce(p_level_cd, g_default_level))
      WHEN 'trc' THEN 10
      WHEN 'dbg' THEN 20
      WHEN 'inf' THEN 30
      WHEN 'wrn' THEN 40
      WHEN 'err' THEN 50
      ELSE 999
   END;
END;
$function$


/* */
CREATE FUNCTION is_Enabled (
   in p_level_cd bpchar
)
   RETURNS boolean
AS
$function$
   #package
   #private
BEGIN

   IF g_mode = cMode_Off THEN
      RETURN false;
   END IF;

   RETURN mi_logger.level_Rank(coalesce(p_level_cd, g_default_level))
          >=
          mi_logger.level_Rank(g_default_level);

END;
$function$


/* Получить inf_id по req_id, если p_inf_id не передан */
CREATE PROCEDURE resolve_Id (
   in p_inf_id numeric,
   in p_req_id numeric,
  out p_inf_od numeric,
  out p_wsp_od numeric
)
AS
$procedure$
   #package
   #private
DECLARE
   l_inf_id numeric;
BEGIN

   if p_inf_id is not null then
      p_inf_od := p_inf_id;
   elsif 
      p_req_id is not null
      then
         select r.inf_id into p_inf_od from xxi.mi_req r where r.req_id = p_req_id;
   end if; 

   if p_inf_od is not null then
      select i.wsp_id into p_wsp_od from xxi.mi_inf i where i.inf_id = p_inf_od;
   end if;

EXCEPTION
   WHEN NO_DATA_FOUND THEN
        null;
END;
$procedure$


/* Сформировать строку для RAISE */
CREATE FUNCTION build_Message (
   in p_logger_name   varchar,
   in p_level_cd      bpchar,
   in p_action_cd     varchar,
   in p_message_text  varchar,
   in p_context_value varchar,
   in p_req_id        numeric,
   in p_person_id     numeric,
   in p_object_id     numeric,
   in p_object_id2    numeric
)
   RETURNS text
AS
$function$
   #package
   #private
DECLARE
   l_msg text;
BEGIN
   l_msg := '[' || trim( coalesce(p_level_cd, g_default_level)) || '] ' || coalesce(p_logger_name, '-') || ' | ' || coalesce(p_action_cd, '-') || ' | ' || coalesce(p_message_text, '');

   IF p_context_value IS NOT NULL THEN
      l_msg := l_msg || ' | ctx=' || p_context_value;
   END IF;

   IF p_req_id IS NOT NULL THEN
      l_msg := l_msg || ' | req_id=' || p_req_id;
   END IF;

   IF p_person_id IS NOT NULL THEN
      l_msg := l_msg || ' | person_id=' || p_person_id;
   END IF;

   RETURN l_msg;

END;
$function$


/* Вывод в RAISE */
CREATE PROCEDURE emit_Raise(
   in p_logger_name   varchar,
   in p_level_cd      bpchar,
   in p_action_cd     varchar,
   in p_message_text  varchar,
   in p_context_value varchar,
   in p_req_id        numeric,
   in p_itm_id        numeric,
   in p_person_id     numeric,
   in p_object_id     numeric,
   in p_object_id2    numeric,
   in p_details_text  text
)AS
$procedure$
   #package
   #private
DECLARE
   l_msg text;
BEGIN
   l_msg := mi_logger.build_Message (
      p_logger_name,
      p_level_cd,
      p_action_cd,
      p_message_text,
      p_context_value,
      p_req_id,
      p_person_id,
      p_object_id,
      p_object_id2
   );

   IF p_details_text IS NOT NULL THEN
      l_msg := l_msg || ' | ' || p_details_text;
   END IF;

   CASE trim(coalesce(p_level_cd, g_default_level))
      WHEN 'trc' THEN
         RAISE DEBUG '%', l_msg;
      WHEN 'dbg' THEN
         RAISE DEBUG '%', l_msg;
      WHEN 'inf' THEN
         RAISE DEBUG '%', l_msg;
      WHEN 'wrn' THEN
         RAISE DEBUG '%', l_msg;
      WHEN 'err' THEN
         RAISE LOG '%', l_msg;
      ELSE
         RAISE DEBUG '%', l_msg;
   END CASE;
END;
$procedure$


/* Автономная вставка в таблицу */
CREATE PROCEDURE insert_Row_AT (
   in p_inf_id           numeric,
   in p_wsp_id           numeric,
   in p_level_cd         bpchar,
   in p_logger_name      varchar,
   in p_context_value    varchar,
   in p_object_name      varchar,
   in p_action_cd        varchar,
   in p_message_text     varchar,
   in p_details_text     text,
   in p_req_id           numeric,
   in p_itm_id           numeric,
   in p_person_id        numeric,
   in p_icusnum          numeric,
   in p_object_id        numeric,
   in p_object_id2       numeric
)
AS
$procedure$
   #package
   #private
   #import 
      auditing   
DECLARE
   l_au_session_id numeric;
BEGIN 
   AUTONOMOUS
raise debug 'insert_Row_AT';   
   l_au_session_id := auditing.V_ID_Session;

   INSERT INTO xxi.mi_log(
      inf_id, wsp_id, au_session_id, level_cd, logger_name, context_value, object_name, action_cd, message_text, details_text, req_id, person_id, icusnum, object_id, object_id2, itm_Id
   )
   VALUES(
      p_inf_id, p_wsp_id, l_au_session_id, coalesce( p_level_cd, g_default_level), 
      left(p_logger_name, 50), left(p_context_value, 100), left(p_object_name, 100), left(p_action_cd, 50), left(p_message_text, 2000), p_details_text,
      p_req_id, p_person_id, p_icusnum, p_object_id, p_object_id2, p_itm_Id
   );

END;
$procedure$


/* */
CREATE PROCEDURE try_Insert_Row(
   in p_inf_id           numeric,
   in p_wsp_id           numeric,
   in p_level_cd         bpchar,
   in p_logger_name      varchar,
   in p_context_value    varchar,
   in p_object_name      varchar,
   in p_action_cd        varchar,
   in p_message_text     varchar,
   in p_details_text     text,
   in p_req_id           numeric,
   in p_itm_id           numeric,
   in p_person_id        numeric,
   in p_icusnum          numeric,
   in p_object_id        numeric,
   in p_object_id2       numeric
)
AS
$procedure$
   #package
   #private
BEGIN
raise debug 'try_Insert_Row';
   CALL mi_logger.insert_Row_AT (
      p_inf_id,
      p_wsp_id,
      p_level_cd,
      p_logger_name,
      p_context_value,
      p_object_name,
      p_action_cd,
      p_message_text,
      p_details_text,
      p_req_id,
      p_itm_id,
      p_person_id,
      p_icusnum,
      p_object_id,
      p_object_id2
   );

EXCEPTION
   WHEN OTHERS THEN
        RAISE DEBUG 'mi_logger.try_Insert_Row failed: SQLSTATE=%, SQLERRM=%', SQLSTATE, SQLERRM;
END;
$procedure$


/* public main procedure */
CREATE PROCEDURE log(
   in p_logger_name    varchar,

   in p_message_text   varchar,

   in p_inf_Id         numeric   default null,
   in p_req_Id         numeric   default null,
   in p_itm_Id         numeric   default null,
   
   in p_level_cd       bpchar    default 'dbg',
   
   in p_details_text   text      default null,
   
   in p_action_cd      varchar   default null,
   in p_context_value  varchar   default null,
   
   in p_object_name    varchar   default null,
   
   in p_person_id      numeric   default null,
   in p_icusnum        numeric   default null,
   
   in p_object_id      numeric   default null,
   in p_object_id2     numeric   default null
)
AS
$procedure$
   #package
DECLARE
   l_inf_id numeric;
   l_wsp_id numeric;
BEGIN

   IF NOT mi_logger.is_Enabled(p_level_cd) THEN
      RETURN;
   END IF;

   call mi_logger.resolve_Id( p_inf_id, p_req_id, l_inf_id, l_wsp_id );

   CALL mi_logger.emit_Raise (
      p_logger_name, p_level_cd, p_action_cd, p_message_text, p_context_value, p_req_id, p_itm_Id, p_person_id, p_object_id, p_object_id2, p_details_text 
   );

   -- Если маршрут не определился - в таблицу не пишем, но RAISE уже был
   IF l_inf_id IS NULL OR l_wsp_id IS NULL THEN
      RETURN;
   END IF;

   if g_mode = cMode_All then
      CALL mi_logger.try_Insert_Row (
         l_inf_id, l_wsp_id, p_level_cd, p_logger_name, p_context_value, p_object_name, p_action_cd, p_message_text, p_details_text, p_req_id, p_itm_Id, p_person_id, p_icusnum, p_object_id, p_object_id2
      );
   end if;   

END;
$procedure$


/* level wrappers */
CREATE PROCEDURE trace(
   in p_logger_Name    varchar,
   in p_message_Text   varchar,
   in p_inf_id         numeric   default null,
   in p_req_id         numeric   default null,
   in p_itm_Id         numeric   default null,
   in p_details_text   text      default null,
   in p_action_cd      varchar   default null,
   in p_context_value  varchar   default null,
   in p_object_name    varchar   default null,
   in p_person_id      numeric   default null,
   in p_icusnum        numeric   default null,
   in p_object_id      numeric   default null,
   in p_object_id2     numeric   default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.log(
      p_logger_name   => p_logger_name,
      p_message_text  => p_message_text,
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_itm_Id        => p_itm_Id,
      p_level_cd      => cLevel_Trc,
      p_details_text  => p_details_text,
      p_action_cd     => p_action_cd,
      p_context_value => p_context_value,
      p_object_name   => p_object_name,
      p_person_id     => p_person_id,
      p_icusnum       => p_icusnum,
      p_object_id     => p_object_id,
      p_object_id2    => p_object_id2
   );
END;
$procedure$


CREATE PROCEDURE debug (
   in p_logger_name    varchar,
   in p_message_text   varchar,
   in p_inf_id         numeric   default null,
   in p_req_id         numeric   default null,
   in p_itm_Id         numeric   default null,
   in p_details_text   text      default null,
   in p_action_cd      varchar   default null,
   in p_context_value  varchar   default null,
   in p_object_name    varchar   default null,
   in p_person_id      numeric   default null,
   in p_icusnum        numeric   default null,
   in p_object_id      numeric   default null,
   in p_object_id2     numeric   default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.log(
      p_logger_name   => p_logger_name,
      p_message_text  => p_message_text,
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_itm_Id        => p_itm_Id,
      p_level_cd      => cLevel_Dbg,
      p_details_text  => p_details_text,
      p_action_cd     => p_action_cd,
      p_context_value => p_context_value,
      p_object_name   => p_object_name,
      p_person_id     => p_person_id,
      p_icusnum       => p_icusnum,
      p_object_id     => p_object_id,
      p_object_id2    => p_object_id2
   );
END;
$procedure$


CREATE PROCEDURE info(
   in p_logger_name    varchar,
   in p_message_text   varchar,
   in p_inf_id         numeric   default null,
   in p_req_id         numeric   default null,
   in p_itm_Id         numeric   default null,
   in p_details_text   text      default null,
   in p_action_cd      varchar   default null,
   in p_context_value  varchar   default null,
   in p_object_name    varchar   default null,
   in p_person_id      numeric   default null,
   in p_icusnum        numeric   default null,
   in p_object_id      numeric   default null,
   in p_object_id2     numeric   default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.log(
      p_logger_name   => p_logger_name,
      p_message_text  => p_message_text,
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_level_cd      => cLevel_Inf,
      p_details_text  => p_details_text,
      p_action_cd     => p_action_cd,
      p_context_value => p_context_value,
      p_object_name   => p_object_name,
      p_person_id     => p_person_id,
      p_icusnum       => p_icusnum,
      p_object_id     => p_object_id,
      p_object_id2    => p_object_id2
   );
END;
$procedure$

CREATE PROCEDURE warn(
   in p_logger_name    varchar,
   in p_message_text   varchar,
   in p_inf_id         numeric   default null,
   in p_req_id         numeric   default null,
   in p_itm_Id         numeric   default null,
   in p_details_text   text      default null,
   in p_action_cd      varchar   default null,
   in p_context_value  varchar   default null,
   in p_object_name    varchar   default null,
   in p_person_id      numeric   default null,
   in p_icusnum        numeric   default null,
   in p_object_id      numeric   default null,
   in p_object_id2     numeric   default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.log(
      p_logger_name   => p_logger_name,
      p_message_text  => p_message_text,
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_level_cd      => cLevel_Wrn,
      p_details_text  => p_details_text,
      p_action_cd     => p_action_cd,
      p_context_value => p_context_value,
      p_object_name   => p_object_name,
      p_person_id     => p_person_id,
      p_icusnum       => p_icusnum,
      p_object_id     => p_object_id,
      p_object_id2    => p_object_id2
   );
END;
$procedure$

CREATE PROCEDURE error(
   in p_logger_name    varchar,
   in p_message_text   varchar,
   in p_inf_id         numeric   default null,
   in p_req_id         numeric   default null,
   in p_itm_Id         numeric   default null,
   in p_details_text   text      default null,
   in p_action_cd      varchar   default null,
   in p_context_value  varchar   default null,
   in p_object_name    varchar   default null,
   in p_person_id      numeric   default null,
   in p_icusnum        numeric   default null,
   in p_object_id      numeric   default null,
   in p_object_id2     numeric   default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.log(
      p_logger_name   => p_logger_name,
      p_message_text  => p_message_text,
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_level_cd      => cLevel_Err,
      p_details_text  => p_details_text,
      p_action_cd     => p_action_cd,
      p_context_value => p_context_value,
      p_object_name   => p_object_name,
      p_person_id     => p_person_id,
      p_icusnum       => p_icusnum,
      p_object_id     => p_object_id,
      p_object_id2    => p_object_id2
   );
END;
$procedure$


/* сахар */

/* вход в ф-цию */
CREATE PROCEDURE enter_f (
   in p_logger_name   varchar,
   in p_function_name varchar,
   in p_message_text  varchar   default null,
   in p_parameters    text      default null, 
   in p_inf_id        numeric   default null,
   in p_req_id        numeric   default null,
   in p_itm_Id        numeric   default null,
   in p_person_id     numeric   default null,
   in p_icusnum       numeric   default null,
   in p_object_id     numeric   default null,
   in p_object_id2    numeric   default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.debug(
      p_logger_name   => p_logger_name,
      p_object_name   => p_function_name,
      p_message_text  => p_message_text,
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_itm_Id        => p_itm_Id,
      p_details_text  => p_parameters,
      p_action_cd     => 'enter_f'::varchar,
      p_person_id     => p_person_id,
      p_icusnum       => p_icusnum,
      p_object_id     => p_object_id,
      p_object_id2    => p_object_id2
   );
END;
$procedure$

/* выход из ф-ции */
CREATE PROCEDURE exit_f(
   in p_logger_name    varchar,
   in p_message_text   varchar default null,
   in p_inf_id         numeric default null,
   in p_req_id         numeric default null,
   in p_itm_Id         numeric default null,
   in p_details_text   text    default null,
   in p_person_id      numeric default null,
   in p_icusnum        numeric default null,
   in p_object_id      numeric default null,
   in p_object_id2     numeric default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.debug(
      p_logger_name   => p_logger_name,
      p_message_text  => p_message_text,
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_itm_Id        => p_itm_Id,
      p_details_text  => p_details_text,
      p_action_cd     => 'exit_f'::varchar,
      p_person_id     => p_person_id,
      p_icusnum       => p_icusnum,
      p_object_id     => p_object_id,
      p_object_id2    => p_object_id2
   );
END;
$procedure$

/* метка в коде */
CREATE PROCEDURE label(
   in p_logger_name    varchar,
   in p_message_text   varchar,
   in p_inf_id         numeric default null,
   in p_req_id         numeric default null,
   in p_itm_Id         numeric default null,
   in p_details_text   text    default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.debug(
      p_logger_name   => p_logger_name,
      p_message_text  => p_message_text,
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_details_text  => p_details_text,
      p_action_cd     => 'label'::varchar
   );
END;
$procedure$


CREATE PROCEDURE variable_Value(
   in p_logger_name    varchar,
   in p_variable_name  varchar,
   in p_value_text     text,
   in p_inf_id         numeric default null,
   in p_req_id         numeric default null,
   in p_itm_Id         numeric default null,
   in p_details_text   text    default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.debug(
      p_logger_name   => p_logger_name,
      p_message_text  => p_variable_name || ' = ' || coalesce( p_value_text::varchar, '<NULL>'),
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_details_text  => p_details_text,
      p_action_cd     => 'val'::varchar
   );
END;
$procedure$

CREATE PROCEDURE version(
   in p_logger_name   varchar,
   in p_object_name   varchar,
   in p_version_text  varchar,
   in p_inf_id        numeric default null
)
AS
$procedure$
   #package
BEGIN
   CALL mi_logger.info(
      p_logger_name   => p_logger_name,
      p_message_text  => p_object_name || ': ' || p_version_text,
      p_inf_id        => p_inf_id,
      p_action_cd     => 'version',
      p_object_name   => p_object_name
   );
END;
$procedure$

CREATE PROCEDURE call_stack(
   in p_logger_name    varchar,
   in p_message_text   varchar default null,
   in p_inf_id         numeric default null,
   in p_req_id         numeric default null,
   in p_itm_Id         numeric default null
)
AS
$procedure$
   #package
DECLARE
   l_context text;
BEGIN
   GET DIAGNOSTICS l_context = PG_CONTEXT;

   CALL mi_logger.debug(
      p_logger_name   => p_logger_name,
      p_message_text  => coalesce(p_message_text, 'call_stack'),
      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_details_text  => l_context,
      p_action_cd     => 'call_stack'
   );
END;
$procedure$

/* */
CREATE PROCEDURE log_exec_Result (
   in p_logger_name    varchar,
   in p_result         mi_resultctx.exec_result,

   in p_inf_id         numeric   default null,
   in p_req_id         numeric   default null,
   in p_itm_Id         numeric   default null,

   in p_action_cd      varchar   default null,
   in p_context_value  varchar   default null,
   in p_object_name    varchar   default null,

   in p_person_id      numeric   default null,
   in p_icusnum        numeric   default null,
   in p_object_id      numeric   default null,
   in p_object_id2     numeric   default null,

   -- Можно переопределить уровень логирования.
   -- По умолчанию успех = inf, ошибка = err.
   in p_success_level  bpchar    default null,
   in p_error_level    bpchar    default null
)
AS
$procedure$
   #package
DECLARE
   l_level_cd      bpchar(3);
   l_action_cd     varchar(20);
   l_context_value varchar(100);
   l_message_text  varchar(2000);
   l_details_json  jsonb;
   l_details_text  text;
BEGIN

   RAISE debug 'enter log_exec_Result';

   IF p_result IS NULL THEN

      CALL mi_logger.error (
         p_logger_name   => p_logger_name,
         p_message_text  => 'exec_result is NULL',
         p_inf_id        => p_inf_Id,
         p_req_id        => p_req_Id,
         p_itm_Id        => p_itm_Id,
         p_action_cd     => coalesce(p_action_cd, 'exec_result'),
         p_context_value => p_context_value,
         p_object_name   => p_object_name,
         p_person_id     => p_person_id,
         p_icusnum       => p_icusnum,
         p_object_id     => p_object_id,
         p_object_id2    => p_object_id2
      );

      RETURN;
   END IF;

   l_level_cd :=
      CASE
         WHEN p_result.is_success IS TRUE  THEN coalesce( p_success_level, cLevel_Inf)
         WHEN p_result.is_success IS FALSE THEN coalesce( p_error_level,   cLevel_Err)
         ELSE cLevel_Wrn
      END;

   l_action_cd :=
      left(
         coalesce(
            p_action_cd,
            'exec_result'
         ),
         50
      );

   /*
      context_value короткий varchar(100).
      По умолчанию кладём result_code.
      Если вызывающий код хочет correlation_id/call_uuid —
      он может передать p_context_value явно.
   */
   l_context_value :=
      left(
         coalesce(
            p_context_value,
            p_result.result_code,
            p_result.cause_code,
            'exec_result'
         ),
         100
      );

   l_message_text :=
      left(
         concat_ws(
            ': ',
            CASE
               WHEN p_result.is_success IS TRUE  THEN 'OK'
               WHEN p_result.is_success IS FALSE THEN 'ERROR'
               ELSE 'UNKNOWN'
            END || coalesce(' [' || p_result.result_code || ']', ''),
            nullif(p_result.result_info, '')
         ),
         2000
      );

   l_details_json :=
      jsonb_strip_nulls(
         jsonb_build_object(
            'is_success',    p_result.is_success,

            'result_code',   p_result.result_code,
            'result_info',   p_result.result_info,
            'result_details',p_result.result_details,

            'cause_code',    p_result.cause_code,
            'cause_info',    p_result.cause_info,
            'cause_details', p_result.cause_details,

            'parameters',    coalesce(p_result.parameters, '{}'::jsonb)
         )
      );

   l_details_text := l_details_json::text;

   CALL mi_logger.log(
      p_logger_name   => p_logger_name,
      p_message_text  => l_message_text,

      p_inf_id        => p_inf_id,
      p_req_id        => p_req_id,
      p_itm_Id        => p_itm_Id,

      p_level_cd      => l_level_cd,

      p_details_text  => l_details_text,
      p_action_cd     => l_action_cd,
      p_context_value => l_context_value,
      p_object_name   => p_object_name,

      p_person_id     => p_person_id,
      p_icusnum       => p_icusnum,
      p_object_id     => p_object_id,
      p_object_id2    => p_object_id2
   );

END;
$procedure$

/* Чистильщики */

/* очищает весь лог */
CREATE PROCEDURE clear_Log()
AS
$procedure$
   #package
BEGIN AUTONOMOUS
   TRUNCATE TABLE xxi.mi_log;
EXCEPTION
   WHEN OTHERS THEN
      RAISE DEBUG 'mi_logger.clear_Log failed: %', SQLERRM;
END;
$procedure$

/* */
CREATE PROCEDURE clear_Log(
   in p_inf_id numeric
)
AS
$procedure$
   #package
BEGIN AUTONOMOUS
   DELETE FROM xxi.mi_log
    WHERE inf_id = p_inf_id;
EXCEPTION
   WHEN OTHERS THEN
      RAISE DEBUG 'mi_logger.clear_Log(inf_id) failed: %', SQLERRM;
END;
$procedure$

/* end_Of_Package */
;