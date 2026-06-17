CREATE OR REPLACE PACKAGE MI_resultCtx

/*
Стандарт для ошибок

   MVxxx — validation
   MNxxx — not found
   MIxxx — integration
   MXxxx — internal/app error

Принцип:
   exec_Result содержит только 8 базовых полей.
   Всё дополнительное: sqlstate, hint, context, app_error_code, version, action —
   хранится в parameters.
*/

CREATE TYPE MI_resultCtx.exec_Result AS
(
    is_success     boolean,

    result_code    varchar(200),
    result_info    varchar(1000),
    result_details text,

    cause_code     varchar(200),
    cause_info     varchar(1000),
    cause_details  text,

    parameters     jsonb
)


/* Инициализация пакета */
CREATE FUNCTION __init__()
    RETURNS void
AS
$init$
DECLARE
    cVersion        constant varchar(100) := '$id: {4.0.0} {03.05.2026} Sulimoff$';

    c_ok_code        constant varchar(50)  := 'SUCCESS';
    c_error_code     constant varchar(50)  := 'ERROR';

    /*
      SQLSTATE для структурированных app/integration ошибок,
      которые потом можно восстановить в exec_Result.
    */
    c_raise_sqlstate constant varchar(5)   := 'MI001';

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


/* Нормализация jsonb parameters */
CREATE FUNCTION normalize_parameters(
    in p_parameters jsonb
)
RETURNS jsonb
AS
$function$
    #package
    #private
BEGIN
    IF p_parameters IS NULL THEN
        RETURN '{}'::jsonb;
    END IF;

    IF jsonb_typeof(p_parameters) = 'object' THEN
        RETURN p_parameters;
    END IF;

    RETURN jsonb_build_object('value', p_parameters);
END;
$function$


/* Успешный результат */
CREATE FUNCTION success(
    in p_code       varchar default null,
    in p_info       varchar default 'Завершено успешно',
    in p_details    text    default null,
    in p_parameters jsonb   default null
)
RETURNS MI_resultCtx.exec_Result
AS
$function$
    #package
BEGIN
    RETURN ROW(
        true,
        left(coalesce(p_code, c_ok_code), 200)::varchar(200),
        left(coalesce(p_info, 'Завершено успешно'), 1000)::varchar(1000),
        p_details,

        null::varchar(200),
        null::varchar(1000),
        null::text,

        MI_resultCtx.normalize_parameters(p_parameters)
    )::MI_resultCtx.exec_Result;
END;
$function$


/*
  Синоним для success.
  Удобно, если в коде хочется писать MI_resultCtx.ok(...)
*/
CREATE FUNCTION ok(
    in p_result_code varchar default null,
    in p_result_info varchar default 'Завершено успешно',
    in p_details     text    default null,
    in p_parameters  jsonb   default null
)
RETURNS MI_resultCtx.exec_Result
AS
$function$
    #package
BEGIN
    RETURN MI_resultCtx.success(
        p_code       => p_result_code,
        p_info       => p_result_info,
        p_details    => p_details,
        p_parameters => p_parameters
    );
END;
$function$


/* Неуспешный результат */
CREATE FUNCTION failure(
    in p_code          varchar default null,
    in p_info          varchar default 'Завершено неудачно',
    in p_details       text    default null,
    in p_parameters    jsonb   default null,

    in p_cause_code    varchar default null,
    in p_cause_info    text    default null,
    in p_cause_details text    default null
)
RETURNS MI_resultCtx.exec_Result
AS
$function$
    #package
BEGIN
    RETURN ROW(
        false,
        left(coalesce(p_code, c_error_code), 200)::varchar(200),
        left(coalesce(p_info, 'Завершено неудачно'), 1000)::varchar(1000),
        p_details,
        left(p_cause_code, 200)::varchar(200),
        left(p_cause_info, 1000)::varchar(1000),
        p_cause_details,
        MI_resultCtx.normalize_parameters(p_parameters)
    )::MI_resultCtx.exec_Result;
END;
$function$


/*
  Синоним для failure.
  Удобно, если в коде хочется писать MI_resultCtx.fail(...)
*/
CREATE FUNCTION fail(
    in p_result_code   varchar default null,
    in p_result_info   varchar default 'Завершено неудачно',
    in p_details       text    default null,
    in p_parameters    jsonb   default null,

    in p_cause_code    varchar default null,
    in p_cause_info    text    default null,
    in p_cause_details text    default null)
RETURNS MI_resultCtx.exec_Result
AS
$function$
    #package
BEGIN
    RETURN MI_resultCtx.failure(
        p_code          => p_result_code,
        p_info          => p_result_info,
        p_details       => p_details,
        p_parameters    => p_parameters,
        p_cause_code    => p_cause_code,
        p_cause_info    => p_cause_info,
        p_cause_details => p_cause_details
    );
END;
$function$


/*
  Сформировать exec_Result из текущей ошибки.
  Вызывать только внутри EXCEPTION-блока.
*/
CREATE FUNCTION from_current_error(
    in p_code       varchar default null,
    in p_info       varchar default 'Операция завершилась ошибкой',
    in p_details    text    default null,
    in p_parameters jsonb   default null
)
RETURNS MI_resultCtx.exec_Result
AS
$function$
    #package
DECLARE
    l_sqlstate text;
    l_message  text;
    l_detail   text;
    l_hint     text;
    l_context  text;
BEGIN
    GET STACKED DIAGNOSTICS
        l_sqlstate = RETURNED_SQLSTATE,
        l_message  = MESSAGE_TEXT,
        l_detail   = PG_EXCEPTION_DETAIL,
        l_hint     = PG_EXCEPTION_HINT,
        l_context  = PG_EXCEPTION_CONTEXT;

    RETURN MI_resultCtx.failure(
        p_code          => coalesce(p_code, c_error_code),
        p_info          => coalesce(p_info, l_message),
        p_details       => p_details,
        p_parameters    => MI_resultCtx.normalize_parameters(p_parameters)
                           || jsonb_strip_nulls(
                                 jsonb_build_object(
                                    'sqlstate', l_sqlstate,
                                    'hint',     l_hint,
                                    'context',  l_context
                                 )
                              ),
        p_cause_code    => l_sqlstate,
        p_cause_info    => l_message,
        p_cause_details => l_detail
    );
END;
$function$


/* exec_Result -> jsonb */
CREATE FUNCTION result_To_Jsonb(
   in p_result MI_resultCtx.exec_Result
)
RETURNS jsonb
AS
$function$
   #package
BEGIN
   RETURN jsonb_strip_nulls(
      jsonb_build_object(
         'is_success',     p_result.is_success,

         'result_code',    p_result.result_code,
         'result_info',    p_result.result_info,
         'result_details', p_result.result_details,

         'cause_code',     p_result.cause_code,
         'cause_info',     p_result.cause_info,
         'cause_details',  p_result.cause_details,

         'parameters',     MI_resultCtx.normalize_parameters(p_result.parameters)
      )
   );
END;
$function$


/* jsonb -> exec_Result */
CREATE FUNCTION result_From_Jsonb(
   in p_json jsonb
)
RETURNS MI_resultCtx.exec_Result
AS
$function$
   #package
DECLARE
   l_result MI_resultCtx.exec_Result;
BEGIN
   SELECT *
     INTO l_result
     FROM jsonb_populate_record(
             NULL::MI_resultCtx.exec_Result,
             coalesce(p_json, '{}'::jsonb)
          );

   l_result.parameters := MI_resultCtx.normalize_parameters(l_result.parameters);

   RETURN l_result;
END;
$function$


/* exec_Result -> text */
CREATE FUNCTION result_To_Text(
   in p_result MI_resultCtx.exec_Result
)
RETURNS text
AS
$function$
   #package
BEGIN
   RETURN MI_resultCtx.result_To_Jsonb(p_result)::text;
END;
$function$


/* text -> exec_Result */
CREATE FUNCTION result_From_Text(
   in p_text text
)
RETURNS MI_resultCtx.exec_Result
AS
$function$
   #package
BEGIN
   RETURN MI_resultCtx.result_From_Jsonb(
      coalesce(nullif(btrim(p_text), ''), '{}')::jsonb
   );
END;
$function$


/*
  Достаёт локализованный текст из системы ML2.
  Пока stub.
*/
CREATE PROCEDURE resolve_Error_Text(
    in  p_app_error_code varchar,
    out p_message_text   text,
    out p_hint_text      text,
    out p_sqlstate       varchar
)
AS
$procedure$
    #package
    #private
BEGIN
    p_message_text := p_app_error_code;
    p_hint_text    := null;
    p_sqlstate     := c_raise_sqlstate;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        p_message_text := p_app_error_code;
        p_hint_text    := null;
        p_sqlstate     := c_raise_sqlstate;
END;
$procedure$


/*
  Бросить структурированную ошибку в формате exec_Result.

  Важно:
    MESSAGE = result_code
    DETAIL  = JSON exec_Result
    HINT    = result_info

*/
CREATE PROCEDURE raise_failure(
    in p_code          varchar default null,
    in p_info          varchar default 'Завершено неудачно',
    in p_details       text    default null,
    in p_parameters    jsonb   default null,

    in p_cause_code    varchar default null,
    in p_cause_info    text    default null,
    in p_cause_details text    default null,

    in p_sqlstate      varchar(5) default null
)
AS
$procedure$
    #package
DECLARE
    l_result MI_resultCtx.exec_Result;
BEGIN
    l_result := MI_resultCtx.failure(
        p_code          => p_code,
        p_info          => p_info,
        p_details       => p_details,
        p_parameters    => p_parameters,
        p_cause_code    => p_cause_code,
        p_cause_info    => p_cause_info,
        p_cause_details => p_cause_details
    );

    RAISE EXCEPTION USING
        ERRCODE = coalesce(p_sqlstate, c_raise_sqlstate),
        MESSAGE = coalesce(l_result.result_code, c_error_code),
        DETAIL  = MI_resultCtx.result_To_Jsonb(l_result)::text,
        HINT    = l_result.result_info;
END;
$procedure$


/*
  Alias для raise_failure.
  Под стиль кода: MI_resultCtx.raise_fail(...)
*/
CREATE PROCEDURE raise_fail(
    in p_result_code   varchar default null,
    in p_result_info   varchar default 'Завершено неудачно',
    in p_details       text    default null,
    in p_parameters    jsonb   default null,

    in p_cause_code    varchar default null,
    in p_cause_info    text    default null,
    in p_cause_details text    default null,

    in p_sqlstate      varchar(5) default null
)
AS
$procedure$
    #package
BEGIN
    CALL MI_resultCtx.raise_failure(
        p_code          => p_result_code,
        p_info          => p_result_info,
        p_details       => p_details,
        p_parameters    => p_parameters,
        p_cause_code    => p_cause_code,
        p_cause_info    => p_cause_info,
        p_cause_details => p_cause_details,
        p_sqlstate      => p_sqlstate
    );
END;
$procedure$


/*
  Главный бросатель app-error.
  Оставлен для совместимости с app-code подходом.
  Внутри теперь тоже бросает DETAIL в формате exec_Result.
*/
CREATE PROCEDURE raise_app_error(
    in p_app_error_code varchar,
    in p_params         jsonb      default null,
    in p_debug_detail   text       default null,
    in p_sqlstate       varchar(5) default null
)
AS
$procedure$
    #package
DECLARE
    l_message_text text;
    l_hint_text    text;
    l_sqlstate     varchar(5);
BEGIN
    CALL MI_resultCtx.resolve_Error_Text(
        p_app_error_code,
        l_message_text,
        l_hint_text,
        l_sqlstate
    );

    CALL MI_resultCtx.raise_failure(
        p_code     => p_app_error_code,
        p_info     => coalesce(l_hint_text, l_message_text, p_app_error_code),
        p_details  => p_debug_detail,
        p_parameters => MI_resultCtx.normalize_parameters(p_params)
                        || jsonb_build_object(
                              'app_error_code', p_app_error_code
                           ),
        p_sqlstate => coalesce(p_sqlstate, l_sqlstate, c_raise_sqlstate)
    );
END;
$procedure$


/*
  Бросить ошибку из exec_Result.
*/
CREATE PROCEDURE raise_Error(
    in p_result         MI_resultCtx.exec_Result,
    in p_raise_sqlstate varchar(5) default null,
    in p_hint           text       default null
)
AS
$procedure$
    #package
BEGIN
    IF NOT coalesce(p_result.is_success, false) THEN
        RAISE EXCEPTION USING
            ERRCODE = coalesce(p_raise_sqlstate, c_raise_sqlstate),
            MESSAGE = coalesce(nullif(p_result.result_code, ''), c_error_code),
            DETAIL  = MI_resultCtx.result_To_Jsonb(p_result)::text,
            HINT    = coalesce(p_hint, p_result.result_info);
    END IF;
END;
$procedure$


/*
  Восстановить exec_Result из пойманного exception.

  Логика:
    1. Если SQLSTATE = MI001 и DETAIL содержит JSON exec_Result,
       возвращаем его.
    2. Иначе собираем failure из диагностик исключения.
*/
CREATE FUNCTION from_exception(
    in p_sqlstate text,
    in p_message  text,
    in p_detail   text,
    in p_hint     text default null,
    in p_context  text default null
)
RETURNS MI_resultCtx.exec_Result
AS
$function$
    #package
DECLARE
    l_result MI_resultCtx.exec_Result;
    l_json   jsonb;
BEGIN
    IF p_sqlstate = c_raise_sqlstate
       AND nullif(btrim(p_detail), '') IS NOT NULL
    THEN
        BEGIN
            l_json   := p_detail::jsonb;
            l_result := MI_resultCtx.result_From_Jsonb(l_json);

            IF l_result.result_code IS NOT NULL THEN
                RETURN l_result;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END IF;

    RETURN MI_resultCtx.failure(
        p_code          => c_error_code,
        p_info          => coalesce(p_message, 'Unexpected error'),
        p_details       => null,
        p_parameters    => jsonb_strip_nulls(
                              jsonb_build_object(
                                  'sqlstate', p_sqlstate,
                                  'hint',     p_hint,
                                  'context',  p_context
                              )
                           ),
        p_cause_code    => p_sqlstate,
        p_cause_info    => p_message,
        p_cause_details => p_detail
    );
END;
$function$


/* text -> boolean */
CREATE FUNCTION to_bool(
   in p_value    text,
   in p_field    text,
   in p_required boolean default true
)
RETURNS boolean
AS
$function$
   #package
   #private
DECLARE
    l_value text;
BEGIN
    l_value := lower(nullif(btrim(p_value), ''));

    IF l_value IS NULL THEN
        IF p_required THEN
            RAISE EXCEPTION 'Required boolean field "%" is empty', p_field;
        END IF;

        RETURN NULL;
    END IF;

    IF l_value IN ('true', 't', '1', 'yes', 'y') THEN
        RETURN true;
    END IF;

    IF l_value IN ('false', 'f', '0', 'no', 'n') THEN
        RETURN false;
    END IF;

    RAISE EXCEPTION 'Invalid boolean value "%" for field "%"', p_value, p_field;
END;
$function$


/*
  Разбор XXLResponse XML -> exec_Result.

  Ожидаемый XML:

  <XXLResponse
      version="1.0"
      action="send"
      is_success="true"
      result_code="SEND_PUBLISHED"
      result_info="Контейнер опубликован">
      <details>...</details>
      <cause_details>...</cause_details>
      <parameters><![CDATA[{...}]]></parameters>
  </XXLResponse>

  version/action не входят в exec_Result напрямую.
  Они добавляются в parameters.
*/
CREATE FUNCTION result_From_Xml(
   in p_xml text
)
RETURNS MI_resultCtx.exec_Result
AS
$function$
   #package
DECLARE
   l_doc              xml;
   l_row              record;
   l_result           MI_resultCtx.exec_Result;
   l_parameters_text  text;
   l_parameters       jsonb;
   l_version          text;
   l_action           text;
BEGIN
   IF nullif(btrim(p_xml), '') IS NULL THEN
      RAISE EXCEPTION 'XXLResponse XML is empty';
   END IF;

   BEGIN
      l_doc := xmlparse(document p_xml);
   EXCEPTION
      WHEN OTHERS THEN
         RAISE EXCEPTION 'Invalid XXLResponse XML: %', SQLERRM;
   END;

   SELECT *
     INTO l_row
     FROM XMLTABLE(
         '/XXLResponse'
         PASSING l_doc
         COLUMNS
             version_txt      text          PATH 'string(@version)',
             action_txt       text          PATH 'string(@action)',

             is_success_txt   text          PATH 'string(@is_success)',

             result_code      varchar(200)  PATH 'string(@result_code)',
             result_info      varchar(1000) PATH 'string(@result_info)',
             result_details   text          PATH 'string(details)',

             cause_code       varchar(200)  PATH 'string(@cause_code)',
             cause_info       varchar(1000) PATH 'string(@cause_info)',
             cause_details    text          PATH 'string(cause_details)',

             parameters_text  text          PATH 'string(parameters)'
     ) AS x;

   IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid XML: root element XXLResponse not found';
   END IF;

   l_version := nullif(btrim(l_row.version_txt), '');
   l_action  := nullif(btrim(l_row.action_txt), '');

   /*
      Если version есть — проверяем.
      Если version отсутствует — не падаем, чтобы не ломать старые ответы,
      но кладём это в parameters.
   */
   IF l_version IS NOT NULL AND l_version IS DISTINCT FROM '1.0' THEN
      RAISE EXCEPTION 'Unsupported XXLResponse version "%"', l_version;
   END IF;

   l_result.is_success :=
      MI_resultCtx.to_bool(
         l_row.is_success_txt,
         'is_success',
         true
      );

   l_result.result_code := nullif(btrim(l_row.result_code), '')::varchar(200);

   IF l_result.result_code IS NULL THEN
      RAISE EXCEPTION 'Required field result_code is empty';
   END IF;

   l_result.result_info    := nullif(btrim(l_row.result_info), '')::varchar(1000);
   l_result.result_details := nullif(btrim(l_row.result_details), '');

   l_result.cause_code     := nullif(btrim(l_row.cause_code), '')::varchar(200);
   l_result.cause_info     := nullif(btrim(l_row.cause_info), '')::varchar(1000);
   l_result.cause_details  := nullif(btrim(l_row.cause_details), '');

   l_parameters_text := nullif(btrim(l_row.parameters_text), '');

   IF l_parameters_text IS NULL THEN
      l_parameters := '{}'::jsonb;
   ELSE
   
      BEGIN
         l_parameters := l_parameters_text::jsonb;
      EXCEPTION
         WHEN OTHERS THEN
            RAISE EXCEPTION 'Invalid JSON in XXLResponse.parameters: %', SQLERRM 
                      USING  DETAIL = l_parameters_text;
      END;

   END IF;

   l_result.parameters :=
      MI_resultCtx.normalize_parameters(l_parameters)
      || jsonb_strip_nulls(
            jsonb_build_object(
               'xml_version', l_version,
               'xml_action',  l_action
            )
         );

   RETURN l_result;
END;
$function$

-- end_Of_Package
;