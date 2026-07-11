create or replace package MI_0007_Api

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
DECLARE
   /*
      Entry point логики вида сведений 0007
      Работает поверх:
         - mi_req
         - xxi.mi_0007
         - xxi.v_mi_0007_req
         - mi_request_Api
         - mi_person_Api
   */
   cVersion  CONSTANT varchar(100) := '$id: {1.1.0} {17.06.2026}$';

   cPkg_Name CONSTANT varchar(20 ) := 'mi_0007_Api'; 
   cLogger   CONSTANT varchar(20 ) := 'mi.0007'; 

   ret_OK    Constant int4 := 0;
   ret_FAIL  Constant int4 := -1;

   cInitiator_Slf CONSTANT NUMERIC := -1;

   g_PsrtRf_Id numeric := null;

BEGIN
   raise debug 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


/* Версия */
CREATE FUNCTION get_Version()
   RETURNS 
      varchar
AS
$function$
   #package
BEGIN
   RETURN cVersion;
END;
$function$


/* Код типа ДУЛ паспорт РФ */
CREATE FUNCTION get_PassportRF_Id()
   RETURNS
      NUMERIC
AS
$function$
   #package
   #private
BEGIN

   if g_PsrtRf_Id is not null then
      return g_PsrtRf_Id;
   end if;

   SELECT pud.ipudid
     INTO g_PsrtRf_Id
     FROM pud
    WHERE IPUDINT_CODE = 1;

   IF NOT FOUND THEN

      CALL mi_logger.error( cLogger, 'Не задан ID типа документа для паспорта РФ. Не установлено поле IPUDINT_CODE в 1 в таблице PUD.', 
                            NULL::numeric, NULL::numeric, NULL::varchar, 'get_PassportRF_Id', NULL::varchar, cPkg_Name, NULL::numeric, NULL::numeric, NULL::numeric, NULL::numeric );

      RAISE EXCEPTION USING
            ERRCODE = 'MI',
            MESSAGE = 'Не задан ID типа документа для "Паспорт гражданина РФ". Не установлено поле IPUDINT_CODE в 1 в таблице PUD.';
   END IF;

   CALL MI_logger.info( cLogger, 'ID типа документа для паспорта РФ: ' || g_PsrtRf_Id, 
                        NULL::numeric, NULL::numeric, NULL::varchar, 'get_PassportRF_Id', NULL::varchar, cPkg_Name, NULL::numeric, NULL::numeric, NULL::numeric, NULL::numeric );
   

   RETURN g_PsrtRf_Id;

END;
$function$


/* 
   Построить json-person из параметров
*/
CREATE FUNCTION build_Json_Person (
   in p_icusnum     NUMERIC,
   in p_last_name   varchar,
   in p_first_name  varchar,
   in p_middle_name varchar,
   in p_birth_date  date,
   in p_doc_series  varchar,
   in p_doc_number  varchar,
   in p_doc_issue_date date,
   in p_region_code varchar
)
   RETURNS 
      jsonb
   LANGUAGE 
      plPGsql
AS
$function$
   #package
   #private
DECLARE
   l_json jsonb;
BEGIN
   l_json :=
      jsonb_build_object (
         'icusnum',        p_icusnum,
         'last_name',      p_last_name,
         'first_name',     p_first_name,
         'middle_name',    p_middle_name,
         'birth_date',     p_birth_date,
         'doc_type_id',    MI_0007_api.get_PassportRF_Id(),
         'doc_ser',        p_doc_series,
         'doc_num',        p_doc_number,
         'doc_issue_date', p_doc_issue_date,
         'region_code',    p_region_code
      );

   RETURN jsonb_strip_nulls(l_json);

END;
$function$


/*
   Создать item 0007
*/
CREATE FUNCTION create_Item (
   in p_req_id    NUMERIC,
   in p_person_id NUMERIC
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
   l_itm_id NUMERIC;
BEGIN

   l_itm_id := mi_request_Api.next_Itm_Id( );

   INSERT INTO xxi.mi_0007 (
      itm_id,
      req_id,
      person_id,
      created_at
   )
   VALUES(
      l_itm_id,
      p_req_id,
      p_person_id,
      clock_timestamp()
   );

   RETURN l_itm_id;

END;
$function$


/*
   Создать request для 0007
*/
CREATE FUNCTION create_Request ( 
   in p_inf_Id NUMERIC DEFAULT 74::NUMERIC 
)
   RETURNS 
      NUMERIC
   LANGUAGE
      plPGsql
AS
$function$
   #package
   #private
BEGIN
   RETURN mi_request_Api.create_Request( p_inf_Id, NULL::uuid );
END;
$function$


/*
   Главная функция создания request 0007
*/
CREATE FUNCTION create_Person_Item (
   in p_json_person jsonb
)
   RETURNS 
      NUMERIC
   LANGUAGE 
      plPGsql
AS
$function$
   #package
DECLARE
   l_person_id NUMERIC;
   l_req_id    NUMERIC;
   l_itm_id    NUMERIC;
BEGIN

   l_person_id := mi_person_Api.get_Or_Create(
      p_inf_id      => 74::numeric,
      p_json_person => p_json_person
   );

   l_req_id := mi_0007_Api.create_Request( );

   l_itm_id := mi_0007_Api.create_Item(
      p_req_id    => l_req_id,
      p_person_id => l_person_id
   );

   RETURN l_itm_Id;

END;
$function$


/*
   Перегрузка:
   icusnum приходит отдельно от json payload
*/
CREATE FUNCTION create_Person_Item (
   in p_icusnum     NUMERIC,
   in p_json_person jsonb,
   in p_inf_Id      NUMERIC DEFAULT 74::NUMERIC
)
   RETURNS 
      NUMERIC
   LANGUAGE 
      plPGsql
AS
$function$
   #package
DECLARE
   l_person_id NUMERIC;
   l_req_id    NUMERIC;
   l_itm_id    NUMERIC;
BEGIN

   l_person_id := MI_person_Api.get_Or_Create (
      p_inf_Id,
      p_icusnum::NUMERIC,
      p_json_person::jsonb
   );

   l_req_id := mi_0007_Api.create_Request( );

   l_itm_id := mi_0007_Api.create_Item(
      p_req_id    => l_req_id,
      p_person_id => l_person_id
   );

   RETURN l_itm_id;

END;
$function$


/* Проверка атрибутов клиента, для создания записи запроса по паспортам */
CREATE FUNCTION check_Attrs (
   in p_last_name    varchar,
   in p_first_name   varchar,
   in p_middle_name  varchar,
   in p_doc_ser      varchar,
   in p_doc_num      varchar
)
   RETURNS 
      VARCHAR
AS
$function$
   #private
   #package
DECLARE
   l_msg varchar;
BEGIN
   IF p_last_name IS NULL THEN
      l_msg := ', Фамилия';
   END IF;

   IF p_first_name IS NULL THEN
      l_msg := coalesce(l_msg, '') || ', Имя';
   END IF;

   IF p_doc_ser IS NULL THEN
      l_msg := coalesce(l_msg, '') || ', Серия паспорта';
   END IF;

   IF p_doc_num IS NULL THEN
      l_msg := coalesce(l_msg, '') || ', Номер паспорта';
   END IF;

   IF l_msg IS NOT NULL THEN
      RETURN 'Создание записи не возможно, не заданы обязательные атрибуты: ' || substr(l_msg, 3);
   END IF;

   IF regexp_replace(coalesce(p_doc_ser, ''), '\s+', '', 'g') !~ '^\d{4}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение серии паспорта - "' || coalesce(p_doc_ser, '') || '". Требуется 4 цифры.';
   END IF;

   IF regexp_replace(coalesce(p_doc_num, ''), '\s+', '', 'g') !~ '^\d{6}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение номера паспорта - "'|| coalesce(p_doc_num, '') || '". Требуется 6 цифр.';
   END IF;

   IF p_last_name !~ '^[А-Яа-яЁё\-\s,.]{1,100}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение Фамилии - "'
             || p_last_name
             || '". Русский текст, длиной до 100 символов, тире, цифры не допускаются.';
   END IF;

   IF p_first_name !~ '^[А-Яа-яЁё\-\s,.]{1,100}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение Имени - "'
             || p_first_name
             || '". Русский текст, длиной до 100 символов, тире, цифры не допускаются.';
   END IF;

   IF p_middle_name IS NOT NULL
      AND p_middle_name !~ '^[А-Яа-яЁё\-\s,.]{1,100}$' THEN
      RETURN 'Создание записи не возможно: не корректное значение Отчества - "'
             || p_middle_name
             || '". Русский текст, длиной до 100 символов, тире, цифры не допускаются.';
   END IF;

   RETURN NULL;

END;
$function$


/* */
CREATE PROCEDURE has_Entry_Set (
   in  p_inf_id        numeric,
   in  p_icusnum       numeric,
   in  p_last_name     varchar,
   in  p_first_name    varchar,
   in  p_middle_name   varchar,
   in  p_doc_num       varchar,
   in  p_doc_ser       varchar,
   in  p_doc_issue_date date,
   in  p_birth_date    date,
   in  p_n_day         numeric,
   out p_found         boolean,
   out p_iState        numeric,
   out p_req_id        numeric,
   out p_itm_id        numeric
)
AS
$procedure$
   #private
   #package
DECLARE
   cPsrtRf constant numeric := MI_0007_api.get_PassportRF_Id();
BEGIN

   p_found  := false;
   p_iState := null;
   p_req_id := null;
   p_itm_id := null;

   SELECT coalesce( v.ires_code, r.status_cd ),
          v.req_id,
          v.itm_id
     INTO p_iState, p_req_id, p_itm_id
     FROM xxi.v_mi_0007 v inner join xxi.mi_req r on r.req_Id = v.req_Id
    WHERE upper(v.last_name ) = upper( p_last_name )
      AND upper(v.first_name) = upper( p_first_name)
      AND (p_middle_name IS NULL OR upper(v.middle_name) = upper(p_middle_name))
      AND ((v.birth_date IS NULL OR p_birth_date IS NULL) OR v.birth_date = p_birth_date)
      AND v.doc_Type_Id = cPsrtRf
      AND replace(v.doc_num, ' ', '') = replace(p_doc_num, ' ', '' )
      AND replace(v.doc_ser, ' ', '') = replace(p_doc_ser, ' ', '' )
      AND ( p_doc_issue_date IS NULL OR v.doc_issue_date = p_doc_issue_date )
      AND r.inf_id = p_inf_id
      AND current_date < ( coalesce(v.tres_time, v.created_at)::date + p_n_day::int4 )
    ORDER BY
          CASE WHEN r.status_cd = 1 THEN 1 ELSE 2 END,
          v.tres_time DESC NULLS LAST,
          v.created_at DESC,
          v.itm_id DESC
    LIMIT 1;

   IF FOUND THEN
      p_found := true;
   END IF;

END;
$procedure$


/* Запрос в таблицу на наличии, записи с ручной установкой валидности */
CREATE PROCEDURE has_Manual_Set (
   in  p_icusnum        numeric,
   in  p_last_name      varchar,
   in  p_first_name     varchar,
   in  p_middle_name    varchar,
   in  p_doc_num        varchar,
   in  p_doc_ser        varchar,
   in  p_doc_issue_date date,
   in  p_n_day          numeric,
   out p_found          boolean,
   out p_iState         numeric,
   out p_req_id         numeric,
   out p_itm_id         numeric
)
AS
$procedure$
   #private
   #package
BEGIN

   CALL mi_0007_Api.has_Entry_Set ( 
        75::numeric, p_icusnum, p_last_name, p_first_name, p_middle_name, p_doc_num, p_doc_ser, p_doc_issue_date, NULL::date,
       p_n_day, p_found, p_iState, p_req_id, p_itm_id
   );

   IF coalesce( p_iState, -1) <> 300 THEN
      p_found  := false;
      p_iState := null;
      p_req_id := null;
      p_itm_id := null;
   END IF;

END;
$procedure$


/* Создает новый запрос, и если надо отправляет в MI */
CREATE PROCEDURE create_And_Exec (
   in  p_inf_id          numeric,

   in  p_icusnum         numeric,
   in  p_last_name       varchar,
   in  p_first_name      varchar,
   in  p_middle_name     varchar,
   in  p_birth_date      date,
   in  p_doc_ser         varchar,
   in  p_doc_num         varchar,
   in  p_doc_issue_date  date,
   in  p_region_code     varchar,

   in  p_time_out        numeric,
   in  p_do_send         boolean,
   
   out p_res_code        int4,
   out p_req_id          numeric,
   out p_itm_id          numeric,
   out p_iState          numeric,
   out p_result_info     varchar
)
AS
$procedure$
   #package
DECLARE

   cAction_Name  constant varchar(50) :=  cPkg_Name || '.create_And_Exec';

   l_inf_id      numeric := coalesce( p_inf_id, 74::numeric );
   l_n_day       numeric;
   l_json_person jsonb;
   l_person_id   numeric;
   l_check_msg   varchar;

   l_req_id      numeric;
   l_itm_id      numeric;

   l_res_code_75 int4;
   l_res_info_75 varchar;

   l_found       boolean;

BEGIN

   p_res_code    := ret_Fail;
   p_req_id      := null;
   p_itm_id      := null;
   p_iState      := null;
   p_result_info := null;

   CALL MI_logger.enter_f( p_logger_name => cLogger, p_function_name => 'create_And_Exec started', p_inf_id => p_inf_id, p_icusnum => p_icusnum );

   begin

      l_check_msg := mi_0007_Api.check_Attrs (
         p_last_name,
         p_first_name,
         p_middle_name,
         p_doc_ser,
         p_doc_num
      );

      IF l_check_msg IS NOT NULL THEN
         p_res_code    := ret_Fail;
         p_result_info := l_check_msg;

         RETURN;

      END IF;

      l_n_day := mi_prp.get_Wsp_Property( 7::numeric, 'VALID_PERIOD_DOC_DAYS', '0')::numeric;

      CALL mi_0007_Api.has_Manual_Set(
         p_icusnum,
         p_last_name,
         p_first_name,
         p_middle_name,
         p_doc_num,
         p_doc_ser,
         p_doc_issue_date,
         l_n_day,
         l_found,
         p_iState,
         p_req_id,
         p_itm_id
      );

      IF l_found THEN

         p_res_code    := ret_OK;
         p_result_info := null;
         
         RETURN;

      END IF;

      IF l_inf_id <> 75 THEN

         CALL mi_0007_Api.has_Entry_Set ( 74::numeric,
            p_icusnum,
            p_last_name,
            p_first_name,
            p_middle_name,
            p_doc_num,
            p_doc_ser,
            p_doc_issue_date,
            p_birth_date,
            l_n_day,
            l_found,
            p_iState,
            p_req_id,
            p_itm_id
         );

         IF l_found THEN
            p_res_code    := ret_OK;
            p_result_info := null;
            RETURN;
         END IF;

      END IF;

      IF l_inf_id = 75 THEN

         CALL mi_0007_Api.create_75_Person_Item (
            p_icusnum,
            p_last_name,
            p_first_name,
            p_middle_name,
            p_doc_ser,
            p_doc_num,
            p_doc_issue_date,
            p_birth_date,
            p_region_code,
            l_res_code_75,
            l_res_info_75
         );

         p_res_code    := l_res_code_75;
         p_result_info := l_res_info_75;

         RETURN;

      END IF;

      l_json_person := mi_0007_Api.build_Json_Person (
         p_icusnum,
         p_last_name,
         p_first_name,
         p_middle_name,
         p_birth_date,
         p_doc_ser,
         p_doc_num,
         p_doc_issue_date,
         p_region_code
      );

      l_person_id := mi_person_Api.get_Or_Create(
         l_inf_id,
         l_json_person
      );

      l_req_id := mi_0007_Api.create_Request(
         l_inf_id
      );

      l_itm_id := mi_0007_Api.create_Item(
         l_req_id,
         l_person_id
      );

      p_req_id := l_req_id;
      p_itm_id := l_itm_id;

   end;

   COMMIT;

   begin

      IF p_do_send THEN

         call MI_MBus.send_Request( p_req_id );

         IF coalesce( p_time_out, 0 ) > 0 THEN
            PERFORM pg_sleep(p_time_out);
         END IF;
         
      END IF;

      SELECT coalesce( v.ires_code, r.status_cd )
        INTO p_iState
        FROM xxi.v_mi_0007 v inner join xxi.mi_req r on v.req_Id = r.req_Id
       WHERE v.itm_id = p_itm_id;

      p_res_code    := 0;
      p_result_info := null;

      CALL mi_logger.info( cLogger, 'create_And_Exec completed', l_inf_id, p_req_id, NULL::varchar, NULL::text, NULL::varchar, cAction_Name, l_person_id, p_icusnum, p_itm_id, NULL::numeric );

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
                    TS.WhenOthersError( cAction_Name, ex ), 'exception', NULL::varchar, NULL::varchar
               );

         END; 

         p_res_code    := ret_Fail;
         p_result_info := SQLERRM;

         RAISE;
   end;
      
END;
$procedure$


/* Создание запроса для конкретного cus атрибуты подтягиваются из справочника */
CREATE PROCEDURE create_And_Exec(
   in  p_inf_id       numeric,
   in  p_icusnum      numeric,
   in  p_time_out     numeric,
   in  p_do_send      boolean,
   out p_res_code     int4,
   out p_req_id       numeric,
   out p_itm_id       numeric,
   out p_iState       numeric,
   out p_result_info  varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name  constant varchar(30) := 'create_and_exec.2';

   cPsrtRf numeric := MI_0007_api.get_PassportRF_Id();

   l_last_name       varchar;
   l_first_name      varchar;
   l_middle_name     varchar;
   l_birth_date      date;
   l_doc_ser         varchar;
   l_doc_num         varchar;
   l_doc_issue_date  date;
   l_region_code     varchar := null;

BEGIN

   p_res_code    := -1;
   p_req_id      := null;
   p_itm_id      := null;
   p_iState      := null;
   p_result_info := null;

   SELECT
         a.ccuslast_name,
         a.ccusfirst_name,
         a.ccusmiddle_name,
         a.dcusbirthday,
         b.doc_ser,
         b.doc_num,
         b.doc_date
     INTO
         l_last_name,
         l_first_name,
         l_middle_name,
         l_birth_date,
         l_doc_ser,
         l_doc_num,
         l_doc_issue_date
     FROM "CUS" a,
          cus_docum b
    WHERE a.icusnum   = b.icusnum
      AND b.id_doc_tp = cPsrtRf
      AND a.ccusflag  IN ( '1', '4' ) -- ФЛ и ИП
      AND ( b.doc_period IS NULL OR b.doc_period >= now()::date )
      AND a.icusnum   = p_iCusNum;

   IF NOT FOUND THEN
      p_res_code    := -1;
      p_result_info := 'Не найден клиент в справочнике по icusnum = ' || p_icusnum;

      CALL mi_logger.info( cLogger, 'create_And_Exec rejected: customer not found', p_inf_id, null::numeric, p_result_info, cAction_Name, 'icusnum=' || p_icusnum::varchar, cPkg_Name, 
                           null::numeric, p_icusnum, null::numeric, null::numeric );
      RETURN;

   END IF;

   CALL mi_0007_Api.create_And_Exec(
      p_inf_id,
      p_icusnum,
      l_last_name,
      l_first_name,
      l_middle_name,
      l_birth_date,
      l_doc_ser,
      l_doc_num,
      l_doc_issue_date,
      l_region_code,
      p_time_out,
      p_do_send,
      p_res_code,
      p_req_id,
      p_itm_id,
      p_iState,
      p_result_info
   );

END;
$procedure$


/* Создает запрос для 75 вида сведений - ручная установка */
CREATE PROCEDURE create_75_Person_Item(
   in  p_icusnum         numeric,
   in  p_last_name       varchar,
   in  p_first_name      varchar,
   in  p_middle_name     varchar,
   in  p_doc_ser         varchar,
   in  p_doc_num         varchar,
   in  p_doc_issue_date  date,
   in  p_birth_date      date,
   in  p_region_code     varchar,
   out p_res_code        int4,
   out p_res_info        varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name        CONSTANT varchar(20) := 'create_75_item';

   l_json_person       jsonb;
   l_person_id         numeric;
   l_req_id            numeric;
   l_itm_id            numeric;
   
BEGIN
   
   p_res_code := ret_Fail;
   p_res_info := NULL;

   l_json_person := mi_0007_Api.build_json_person (
      p_icusnum::numeric,
      p_last_name::varchar,
      p_first_name::varchar,
      p_middle_name::varchar,
      p_birth_date::date,
      p_doc_ser::varchar,
      p_doc_num::varchar,
      p_doc_issue_date::date,
      p_region_code::varchar
   );

   l_person_id := mi_person_Api.get_Or_Create (
      75::numeric,
      l_json_person
   );

   /*
     Последний request для inf_id = 75, нет - создаём новый СРАЗУ в status = 1
   */
   SELECT r.req_id
     INTO l_req_id
     FROM xxi.mi_req r
    WHERE r.inf_id = 75::numeric
    ORDER BY r.created_at DESC,
             r.req_id DESC
    LIMIT 1;

   IF NOT FOUND THEN

      l_req_id := mi_Request_Api.create_Request (
         p_inf_id    => 75::numeric,
         p_status_cd =>  1::numeric
      );

   END IF;

   l_itm_id := mi_request_Api.next_Itm_Id( );

   INSERT INTO xxi.mi_0007 (
      itm_id,
      req_id,
      person_id,
      created_at,
      ires_code,
      tres_time
   )
   VALUES(
      l_itm_id,
      l_req_id,
      l_person_id,
      clock_timestamp(),
      300::numeric,   
      clock_timestamp()
   );

   p_res_code := 0;
   p_res_info := 'Создан item 75. req_id=' || l_req_id || ', itm_id=' || l_itm_id;

   CALL mi_logger.info( cLogger, 'create_75_Person_Item completed', 75, l_req_id, p_res_info, cAction_Name, NULL::varchar,
                        cPkg_name, l_person_id, p_icusnum, l_itm_id, NULL::numeric );

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
                 75::numeric, l_req_id, 
                 TS.WhenOthersError( cPkg_Name || '.' || cAction_Name, ex ), 'exception', NULL::varchar, cPkg_Name 
            );

      END; 

   RAISE;

END;
$procedure$


/* Создание запроса с позициями на основе маркера в "CUS" */
CREATE PROCEDURE create_Person_Items_By_Marker (
    in p_marker_id      numeric,
   out p_req_id         numeric,
   out p_created_count  int4,
   out p_res_Code       int4,
   out p_res_Info       varchar
)
AS
$procedure$
   #package
DECLARE
   cAction_Name   constant varchar(20) := 'create_items_batch';
   cInf_Id        constant numeric     := 74::NUMERIC;
   r              record;
   l_has_rows     boolean;

   l_json_person  jsonb;
   l_person_id    numeric;
   l_itm_id       numeric;

BEGIN

   p_req_id        := NULL;
   p_created_count := 0;
   p_res_code      := 0;
   p_res_info      := NULL;

   /*
     Проверка marker. Если пустой - request НЕ создаём.
   */
   SELECT EXISTS (
      SELECT 1
        FROM xxi.mrk_id m WHERE m.idmarker = p_marker_id
   )
     INTO l_has_rows;

   IF NOT l_has_rows THEN
      p_res_code := 0;
      p_res_info := 'По marker_id = ' || p_marker_id || ' не найдено помеченных клиентов. Request не создан.';

      CALL mi_logger.info( cLogger, 'create_Person_Items_By_Marker skipped: marker is empty', cInf_Id, NULL::numeric, p_res_info, cAction_Name, 'marker_id=' || p_marker_id::varchar, cPkg_Name );

      RETURN;

   END IF;

   /*
     Новый request для всей batch-операции
   */
   p_req_id := mi_0007_Api.create_Request( );

   CALL mi_logger.info( cLogger, 'Batch request created', cInf_Id, p_req_id, 'marker_id=' || p_marker_id::varchar, cAction_Name, NULL::varchar, cPkg_Name );

   /*
     Клиенты из marker
   */
   FOR r IN 
   (
      SELECT c.icusnum,
             c.ccuslast_name last_Name,
             c.ccusfirst_name first_Name,
             c.ccusmiddle_name middle_Name,
             c.dcusbirthday birth_date,
             b.doc_ser doc_ser,
             b.doc_num doc_num,
             b.doc_date doc_issue_date,
             null::varchar AS region_code
        FROM xxi.mrk_id m
        JOIN xxi."CUS" c
          ON c.icusnum  = m.idrow
             join cus_docum b on c.icusnum = b.icusnum    
       WHERE m.idmarker = p_marker_id )
   LOOP

      l_json_person := mi_0007_Api.build_json_person (
         r.icusnum::numeric,
         r.last_name::varchar,
         r.first_name::varchar,
         r.middle_name::varchar,
         r.birth_date::date,
         r.doc_ser::varchar,
         r.doc_num::varchar,
         r.doc_issue_date::date,
         r.region_code::varchar
      );

      l_person_id := mi_person_Api.get_Or_Create (
         cInf_Id,
         l_json_person
      );

      l_itm_id := mi_0007_Api.create_Item (
         p_req_id,
         l_person_id
      );

      p_created_count := p_created_count + 1;

      CALL mi_logger.debug( cLogger, 'Batch item created', cInf_Id, p_req_id, NULL::varchar, cAction_Name, 'icusnum=' || r.icusnum::varchar, cPkg_Name, l_person_id, r.icusnum, l_itm_id, NULL::numeric );

   END LOOP;

   p_res_code := ret_OK;
   p_res_info := 'Создан request, req_id=' || p_req_id || ', item_count=' || p_created_count::varchar;

   CALL mi_logger.info( cLogger, 'create_Person_Items_By_Marker completed', cInf_Id, p_req_id, p_res_info, cAction_Name, 'marker_id=' || p_marker_id::varchar, cPkg_Name );

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
      
            p_res_Info := TS.WhenOthersError( cPkg_Name || '.' || cAction_Name, ex );

            CALL mi_logger.error ( 
                 cLogger, 
                 cAction_Name || ' failed',
                 cInf_Id, p_req_id, 
                 p_res_Info, 'exception', NULL::varchar, cPkg_Name 
            );

      END; 

   p_res_code := ret_Fail;
   p_res_info := coalesce( p_res_Info, SQLERRM );

   RAISE;

END;
$procedure$


/*
   Записать бизнес-результат по item
*/
CREATE PROCEDURE apply_Item_Result (

   in  p_request_uuid      uuid,
   in  p_message_uuid      uuid,
   in  p_item_uuid         uuid,

   in  p_response_kind     int4,

   in  p_response_code     varchar,
   in  p_response_info     varchar,
   in  p_response_details  text,
   in  p_response_time     timestamptz,

   in  p_payload_text      text,

  out p_ret_code          int4,
  out p_ret_info          varchar
)
AS
$procedure$
DECLARE

   cFunc constant varchar := cPkg_Name || '.apply_Item_Result';

   cAlready_applied constant int4 := 1;

   l_itm_id              numeric;
   l_current_message_uuid uuid;

   l_payload             jsonb;

   l_doc_status          numeric;
   l_ires_code           numeric;
   l_cres_info           text;

   l_row_count           int4;

BEGIN

   p_ret_code := ret_Fail;
   p_ret_info := NULL;

   /*
    * Базовая validation.
    */
   IF p_request_uuid IS NULL THEN
      p_ret_info := 'p_request_uuid is null';
      RETURN;
   END IF;

   IF p_message_uuid IS NULL THEN
      p_ret_info := 'p_message_uuid is null';
      RETURN;
   END IF;

   IF p_item_uuid IS NULL THEN
      p_ret_info := 'p_item_uuid is null';
      RETURN;
   END IF;

   IF p_response_kind IS NULL THEN
      p_ret_info := 'p_response_kind is null';
      RETURN;
   END IF;

   IF p_response_time IS NULL THEN
      p_ret_info := 'p_response_time is null';
      RETURN;
   END IF;

   if p_response_kind not in (ret_OK,ret_Fail) then
      p_ret_info := 'unsupported p_response_kind: ' || p_response_kind;
      RETURN;
   end if;   

   /*
    * Находим item исходного request.
    *
    */
   BEGIN
      SELECT i.itm_id,
             i.message_uuid
        INTO l_itm_id,
             l_current_message_uuid
        FROM xxi.mi_req r
        JOIN xxi.mi_0007 i
          ON i.req_id = r.req_id
       WHERE r.external_uuid = p_request_uuid
         AND i.external_uuid = p_item_uuid
       FOR UPDATE OF i;

   EXCEPTION
      WHEN no_data_found THEN
         p_ret_info := 'mi_0007 item not found: request_uuid=' || p_request_uuid || ', item_uuid=' || p_item_uuid;

         RETURN;

      WHEN too_many_rows THEN
         p_ret_info := 'more than one mi_0007 item found: request_uuid=' || p_request_uuid || ', item_uuid=' || p_item_uuid;

         RETURN;
   END;

   /*
    *
    * Тот же message_uuid уже применён -> OK, но already applied.
    * Другой message_uuid уже применён -> конфликт, не retry.
    */
   IF l_current_message_uuid IS NOT NULL 
   THEN
      IF l_current_message_uuid = p_message_uuid THEN
         p_ret_code := cAlready_applied;
         p_ret_info := 'Item already applied';

         RETURN;

      END IF;

      p_ret_info := 'mi_0007 item already applied by another message: current_message_uuid=' || l_current_message_uuid || ', new_message_uuid=' || p_message_uuid;
      RETURN;

   END IF;

   /*
    * Нормализованный OK.
    */
   IF p_response_kind = ret_OK THEN

      IF p_payload_text IS NULL OR btrim(p_payload_text) = '' THEN
         p_ret_info := 'p_payload_text is null or empty for successful item';
         RETURN;

      END IF;

      BEGIN
         l_payload := p_payload_text::jsonb;
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
            
                  p_ret_info := TS.WhenOthersError( cFunc, ex );
         END; 

         WHEN others THEN
            GET STACKED DIAGNOSTICS
                p_ret_info = MESSAGE_TEXT;

            p_ret_info := 'p_payload_text is not valid JSON: ' || p_ret_info;

            RETURN;
      END;

      BEGIN
         l_doc_status := NULLIF(l_payload ->> 'docStatus', '')::numeric;
      EXCEPTION
         WHEN others THEN
            p_ret_info := 'docStatus is not numeric in successful payload';
            RETURN;
      END;

      IF l_doc_status IS NULL THEN
         p_ret_info := 'docStatus is null in successful payload';
         RETURN;
      END IF;

      l_ires_code := l_doc_status;

      l_cres_info :=
         COALESCE(
            NULLIF(l_payload ->> 'comment', ''),
            'docStatus=' || l_doc_status
         );

   /*
    * Нормализованный FAIL.
    */
   ELSE -- p_response_kind = ret_Fail THEN

      IF p_payload_text IS NOT NULL THEN
         p_ret_info := 'p_payload_text must be null for failed item';
         RETURN;

      END IF;

      IF p_response_code IS NULL OR btrim(p_response_code) = '' THEN
         p_ret_info := 'p_response_code is null or empty for failed item';
         RETURN;

      END IF;

      l_ires_code := ret_Fail;

      l_cres_info := COALESCE( NULLIF(p_response_info, ''), NULLIF(p_response_details, ''), p_response_code );

   END IF;

   /*
    * p_ret_code = 0 даже для p_response_kind = -1,
    * если отрицательный outcome успешно сохранён в XXI.
    */
   UPDATE xxi.mi_0007
      SET ires_code    = l_ires_code,
          tres_time    = p_response_time,
          message_uuid = p_message_uuid,
          cres_info    = l_cres_info,
          error_code   = CASE WHEN p_response_kind = ret_Fail THEN p_response_code ELSE NULL END
    WHERE 
          itm_id = l_itm_id
      AND message_uuid IS NULL;

   GET DIAGNOSTICS l_row_count = ROW_COUNT;

   IF l_row_count <> 1 THEN
      p_ret_info :=
         'mi_0007 item outcome was not applied, row_count=' || l_row_count;
      RETURN;
   END IF;

   p_ret_code := c_ret_ok;
   p_ret_info := 'applied';

END;
$procedure$


/*
   helper:
   проставить результат item и статус request
CREATE PROCEDURE complete_Request (
   in p_itm_id         NUMERIC,
   in p_req_id         NUMERIC,
   in p_ires_code      NUMERIC,
   in p_cres_info      text DEFAULT NULL,
   in p_tres_time      timestamptz DEFAULT clock_timestamp(),
   in p_req_status_cd  NUMERIC DEFAULT NULL
)
   LANGUAGE
      plpgsql
AS
$procedure$
   #package
BEGIN
   CALL mi_0007_Api.apply_Item_Result (
      p_itm_id    => p_itm_id,
      p_ires_code => p_ires_code,
      p_cres_info => p_cres_info,
      p_tres_time => p_tres_time
   );

   IF p_req_status_cd IS NOT NULL THEN
      CALL mi_0007_Api.set_Request_Status(
         p_req_id    => p_req_id,
         p_status_cd => p_req_status_cd
      );
   END IF;
END;
$procedure$
*/

/* end_Of_Package */
;
