create or replace package MI_0001_Api

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
DECLARE

   cVersion     CONSTANT varchar(100) := '$id: {1.0.0} {27.05.2026}$';

   cPkg_Name    CONSTANT varchar(20 ) := 'mi_0001_Api'; 
   cLogger      CONSTANT varchar(20 ) := 'mi.0001'; 
   cLogger_Auto CONSTANT varchar(20 ) := 'mi.0001.auto'; 

   cLock_Name   CONSTANT varchar(20 ) := 'mi_0001_auto'; 

   ret_OK       CONSTANT int4 := 0;
   ret_FAIL     CONSTANT int4 := -1;

BEGIN
   raise debug 'Package "%" - % - initialized', cPkg_Name, cVersion;
END;
$init$


/* Версия */
CREATE FUNCTION get_Version()
   RETURNS 
      varchar
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
   Создать request для 0001.
   Wrap поверх ф-ции из mi_request_Api
*/
CREATE FUNCTION create_Request ( 
   in p_inf_Id NUMERIC DEFAULT 12::NUMERIC 
)
   RETURNS 
      NUMERIC
AS
$function$
   #package
   #private
BEGIN
   return MI_request_Api.create_Request( p_inf_Id, NULL::uuid );
END;
$function$


/*
   Создать item 0001
*/
CREATE FUNCTION create_Item (
   in p_req_id    numeric,
   in p_person_id numeric
)
   returns 
      numeric
   language 
      plPGsql
AS
$function$
   #package
   #private
DECLARE
   l_itm_id NUMERIC;
BEGIN

   call MI_logger.enter_f( cLogger, 'create_Item', 'p_person_id = ' || p_person_id || ', p_req_id = ' || p_req_id );

   l_itm_id := MI_request_Api.next_Itm_Id( );

   INSERT INTO xxi.mi_0001 (
      itm_id,
      req_id,
      person_id,
      icusnum,
      created_at
   )
   select
      l_itm_Id,
      p_req_Id,
      p_person_Id,
      mi_person.icusNum,
      clock_timestamp()
   from 
      mi_person
  where 
      mi_person.person_Id = p_person_Id;

   call MI_logger.variable_Value( cLogger, 'l_itm_id'::varchar, l_itm_id::varchar );

   RETURN l_itm_id;

END;
$function$


/*
   Вывод в лог инфы о подготовке данных о клиентах
*/
create procedure log_Auto (
   in p_message   varchar,
   in p_icusnum   numeric,
   in p_person_id numeric
)
as
$procedure$
   #package
   #private
begin
   call MI_logger.info ( 
      p_logger_name  => cLogger_Auto, 
      p_message_text => p_message, 
      p_inf_id       => 13::numeric, 
      p_action_cd    => 'check_4_Prepare', 
      p_person_Id    => p_person_Id, 
      p_icusnum      => p_icusnum
   );
end;
$procedure$


/* 
   Построить json-person из параметров
*/
CREATE FUNCTION build_Json_Person (
   in p_cus xxi.v_mi_0001_ca
)
   RETURNS 
      jsonb
AS
$function$
   #package
   #private
DECLARE
   l_json jsonb;
BEGIN
   l_json :=
      jsonb_build_object (
         'icusnum',         p_cus.icusnum,
         'last_name',       p_cus.last_name,
         'first_name',      p_cus.first_name,
         'middle_name',     p_cus.middle_name,
         'birth_date',      p_cus.birth_date,
         'birth_place',     p_cus.birth_place,
         'doc_type_code',   p_cus.doc_type_code,
         'doc_ser',         p_cus.doc_ser,
         'doc_num',         p_cus.doc_num,
         'doc_issue_date',  p_cus.doc_issue_date,
         'doc_issuer_code', p_cus.doc_issuer_code,
         'doc_issuer_name', p_cus.doc_issuer_name
      );

   RETURN jsonb_strip_nulls(l_json);

END;
$function$


/*
   Проверка данных клиента для массовой отправки
*/
create procedure check_4_Prepare (
    in p_cus              xxi.v_mi_0001_ca,
    in p_handle_Not_Found boolean,
    in p_wait_Hour_Range  int4,
   out p_create           boolean,
   out p_ids4Remove       numeric[],
   out p_error_Count      int4,
   out p_result_Info      varchar 
)
as
$procedure$
   #package
   #private
declare

   l_nCount   int4    := 0;
   l_doCreate boolean := TRUE;

   c_data cursor
   for
      select r.req_Id, r.inf_Id, r.status_Cd, i.iRes_Code, r.created_At, i.person_Id, i.itm_Id
        from xxi.mi_req r
             inner join xxi.mi_0001 i on r.req_Id = i.req_Id
       where 
             i.icusnum = p_cus.icusNum
       order 
          by r.created_At desc, 
             case r.status_cd 
               when  1 then -2
               when -1 then -3
               else
                    r.status_cd  
             end desc;     

   r record;
             
begin

   p_ids4Remove := '{}'; 
   p_result_Info:= null;

   for r in c_Data
   loop

      l_nCount := l_nCount + 1;

      IF r.status_Cd = 0 then
         -- уже есть подготовленный запрос по данному клиенту, но еще не принят в обработку службой отправки
         l_doCreate    := FALSE;
         p_result_Info := 'Для клиента ' || p_cus.icusnum || ' уже есть подготовленный запрос по данному клиенту, но еще не принят в обработку службой отправки';   

      elsif r.status_Cd = 1 AND r.iRes_Code IS NULL then
         -- есть успешно выполненный запрос, но не перенесен в ИНН в каталог клиентов
         l_doCreate    := FALSE;
         p_result_Info := 'Для клиента ' || p_cus.icusnum || ' есть успешно выполненный запрос, но не перенесен в ИНН в каталог клиентов';

      elsif r.status_Cd = 1 AND r.ires_code = 1 then
         
         if not p_handle_Not_Found then

            l_doCreate    := FALSE;
            p_result_Info := 'Для клиента ' || p_cus.icusnum || ' есть запрос со статусом "Сведения не найдены"';

         end if;      
            
      elsif r.status_Cd IN ( 2, 3 ) then
         -- есть запрос в обработке, но если он долго висит, то формируем новый
         if ( round( current_timestamp - r.created_At, 0 ) * 24 ) > p_wait_Hour_Range then

            call MI_0001_Api.log_Auto (  
               'Для клиента ' || p_cus.icusnum || ' удаляем подвисший запрос', r.person_Id, p_cus.icusnum
            );

            p_ids4Remove := array_append(p_ids4Remove, r.itm_Id );

         else
            l_doCreate := false;
         end if;

      elsif r.status_Cd = -1 then
            
            call MI_0001_Api.log_Auto (  
               'Для клиента ' || p_cus.icusnum || ' удаляем ошибочный запрос', r.person_Id, p_cus.icusnum
            );

            p_ids4Remove := array_append( p_ids4Remove, r.itm_Id );

      end if;

   end loop;

   if p_result_Info is not null then

      call MI_0001_Api.log_Auto (  
           p_result_Info, r.person_Id, p_cus.icusnum
      );

   end if;

   IF l_ncount > 0 THEN

      call MI_0001_Api.log_Auto (  
         'Для клиента ' || p_cus.icusnum || ' было ' || l_ncount || ' записей запросов', null::numeric, p_cus.icusnum
      );

   END IF;

   IF l_doCreate THEN
      -- если не корректные Имя или Фамилия
      -- пишем в лог и не обрабатываем
      IF p_cus.last_name IS NULL OR p_cus.first_name IS NULL THEN
         p_result_Info := 'У клиента ' || p_cus.icusnum || ' не заполнены Фамилия или Имя';
         l_doCreate    := FALSE;
      END IF;

      IF p_cus.birth_date IS NULL THEN
         p_result_Info :=  'У клиента ' || p_cus.icusnum || ' не заполнена Дата рождения';
         l_doCreate    := FALSE;
      END IF;

      IF p_cus.doc_type_code IS NULL OR p_cus.DOC_NUM IS NULL THEN
         p_result_Info := 'У клиента ' || p_cus.icusnum || ' не заполнен Вид документа или Номер документа';
         l_doCreate    := FALSE;
      END IF;

      IF NOT l_doCreate THEN
         p_error_Count := p_error_Count + 1;
      END IF;

      if p_result_Info is not null then

         call MI_0001_Api.log_Auto (  
            p_result_Info, null::numeric, p_cus.icusnum
         );

      end if;

   END IF;

   p_create := l_doCreate;

end; 
$procedure$


/* 
   Запись в запрос
*/
create function create_Item (
   in p_inf_Id numeric,
   in p_req_Id numeric,
   in p_cus    xxi.v_mi_0001_ca,
   in p_ids4Remove 
               numeric[]
)
   RETURNS
      NUMERIC
as
$function$ 
   #package
   #private
DECLARE

   l_person_id numeric;
   l_itm_id    numeric;

   l_json_Person 
               jsonb;
BEGIN

   l_json_Person := MI_0001_Api.build_Json_Person(p_cus);

   l_person_id := MI_person_Api.get_Or_Create (
      p_inf_id   => p_inf_Id,
      p_person_J => l_json_Person
   );

   l_itm_id := MI_0001_Api.create_Item (
      p_req_id   => p_req_id,
      p_person_id=> l_person_id
   );

   if p_ids4remove is not null and array_length( p_ids4Remove, 1) > 0 then

      delete from xxi.mi_0001
            where itm_id = any( p_ids4Remove );

      call MI_logger.info ( 
         p_logger_name  => cLogger_Auto, 
         p_message_text => 'Для клиента удалено ' || array_length( p_ids4Remove, 1) || ' старых записей', 
         p_details_text => 'mi_0001.itm_id: ' || p_ids4Remove,
         p_inf_id       => p_inf_Id, 
         p_action_cd    => 'create_Item', 
         p_icusnum      => null
      );

   end if;

   return l_itm_id;

END;
$function$


/*
   Автоматический сбор и подготовка клиентов без ИНН для отправки
*/
create procedure auto_Prepare ( 
   in p_publish_Mbus boolean DEFAULT false
)
as
$procedure$ 
   #package
declare

   l_lock_Handle      varchar(100);

   l_wait_Hour_Range  int4   := 72::int4; 
   l_cus_Hour_Range   int4   := MI_prp.get_Wsp_Property( 1, 'CUS_HOUR_RANGE',   '48' )::int4; 
   l_handle_Not_Found boolean:= MI_prp.get_Wsp_Property( 1, 'HANDLE_NOT_FOUND', 'false' )::boolean; 

   l_error_Count      int4   := 0;

   l_doCreate         boolean:= false;  
   l_ids4Remove       numeric[];

   r                  xxi.v_mi_0001_ca%rowtype;

   l_req_id           numeric;
   l_itm_id           numeric;

   l_result_Info      varchar;

begin

   -- блокирование
   declare
      l_lock_Code int4;
      l_lock_Info varchar;
   begin
      
      call MI_utils.lock_Proc( cLock_Name, true, 0, l_lock_Code, l_lock_Info, l_lock_Handle );
      
      if l_lock_Code <> RET_OK then
         if l_lock_Code = 1 then
            raise exception 'Resource_Busy';
         else
            raise exception 'Bad_Data_Exception';
         end if;      
      end if;

   end;   

   for r in ( SELECT * FROM xxi.v_mi_0001_ca WHERE ( current_date - DCUSOPEN ) > make_interval( hours => l_cus_Hour_Range ))
   loop

      call MI_0001_Api.check_4_Prepare( r, l_handle_Not_Found, l_wait_Hour_Range, l_doCreate, l_ids4Remove, l_error_Count, l_result_Info );

      continue when not l_doCreate;

      if l_req_id is null then
         l_req_id := MI_0001_Api.create_Request( 13::numeric );
      end if;

      l_itm_id := MI_0001_Api.create_Item( 13::numeric, l_req_id, r, l_ids4Remove );

   end loop;

   if p_publish_Mbus and l_req_id is not null then
      CALL MBus_Api.send_Request( p_req_id => l_req_id );
   end if;

end;  
$procedure$ 


/* */
CREATE PROCEDURE submit_Auto_Prepare (
   OUT p_job_id       bigint,
   IN  p_publish_Mbus int4    DEFAULT 1::int4,
   IN  p_source       varchar DEFAULT NULL::varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS
$procedure$
   #package
DECLARE
   c_job_name CONSTANT text := 'MI_0001_AUTO_PREPARE';
BEGIN

   IF p_publish_Mbus NOT IN (0, 1) THEN
      RAISE EXCEPTION 'Invalid p_publish_mbus value: %. Expected 0 or 1', p_publish_Mbus;
   END IF;

   PERFORM pg_advisory_xact_lock (
      hashtext('MI_0001_API'),
      hashtext('AUTO_PREPARE')
   );

   SELECT j.id
          INTO p_job_id
     FROM schedule.job_status j
    WHERE j.name = c_job_name AND j.status::text IN ('submitted', 'processing')
    ORDER 
         BY j.id DESC
    LIMIT 1;

   IF FOUND THEN
      p_job_id := -p_job_id;
      RETURN;
   END IF;

   p_job_id := schedule.submit_job (
      query  => 'CALL MI_0001_Api.auto_Prepare($1::boolean)',
      params => ARRAY[p_publish_Mbus::text],
      name   => c_job_name,
      comments 
             => format( 'source=%s, publish_mbus=%s', COALESCE(p_source, 'UNKNOWN'), p_publish_Mbus )
   );

END;
$procedure$


/* Создает персональный запрос для получения ИНН для физ лица */
create procedure create_Personal_Request (
   in p_cus    xxi.v_mi_0001_ca,
  out p_req_Id numeric,
  out p_itm_id numeric,
  out p_res_Code
               int4,
  out p_res_Info 
               varchar
)
as
$procedure$ 
   #package
declare

   l_wait_Hour_Range  int4    := 72::int4; 
   l_cus_Hour_Range   int4    := MI_prp.get_Wsp_Property( 1, 'CUS_HOUR_RANGE',  '48' )::int4; 
   l_handle_Not_Found boolean := MI_prp.get_Wsp_Property( 1, 'HANDLE_NOT_FOUND','false' )::boolean; 
   l_doCreate         boolean := false;  
   l_ids4Remove       numeric[];

begin

   p_res_Code := ret_FAIL;
   p_req_Id   := null;
   p_itm_id   := null;

   begin

      call MI_0001_Api.check_4_Prepare( p_cus, l_handle_Not_Found, l_wait_Hour_Range, l_doCreate, l_ids4Remove, l_error_Count, p_res_Info );

      if l_doCreate then
         
         p_req_Id := MI_0001_Api.create_Request( 12::numeric );
         p_itm_id := MI_0001_Api.create_Item   ( 12::numeric, p_req_Id, p_cus, l_ids4Remove );

         p_res_Code := ret_OK;
         
      end if;

   exception
      when others then
      declare
         ex TS.T_StackedDiagnostics;
      begin
         GET STACKED DIAGNOSTICS
            ex.RETURNED_SQLSTATE    = RETURNED_SQLSTATE,  
            ex.MESSAGE_TEXT         = MESSAGE_TEXT,
            ex.PG_EXCEPTION_DETAIL  = PG_EXCEPTION_DETAIL,
            ex.PG_EXCEPTION_HINT    = PG_EXCEPTION_HINT,
            ex.PG_EXCEPTION_CONTEXT = PG_EXCEPTION_CONTEXT;   

            p_res_Info := TS.WhenOthersError( 'MI_0001_Api.create_Personal_Request', ex );
      end;
   end;
end;
$procedure$ 


/* Раскладка payLoad по таблицам */
CREATE FUNCTION map_Item_Result (
   in p_itm_Id  numeric(12),
   in p_payload jsonb
)
RETURNS
   MI_Item_Result_Api.Item_Result
as
$function$ 
   #package
declare

   -- cFunc varchar := cPkg_Name || '.map_Item_Result';

   l_valInn varchar;
   l_result MI_Item_Result_Api.Item_Result;
begin

   l_valInn := l_payload ->> 'innPhP';

   if l_valInn is null then
      l_result.cRes_info := 'Данные не найдены';
      l_result.iRes_Code := 1; -- 'NO_DATA_FOUND';
   end if;

   update xxi.mi_0001 
      set inn    = l_valInn
    where 
          itm_Id = p_itm_Id; 

   return l_result;

end;
$function$


/** */
CREATE PROCEDURE apply_Item_Result (

   in p_request_uuid      uuid,
   in p_message_uuid      uuid,
   in p_item_uuid         uuid,

   in p_response_kind     int4,

   in p_response_code     varchar,
   in p_response_info     varchar,
   in p_response_details  text,
   in p_response_time     timestamptz,

   in p_payload_text      text,

   out p_ret_code         int4,
   out p_ret_info         varchar
)
AS
   $procedure$
BEGIN

   CALL
      MI_Item_Result_Api.apply_Item_Result (

         'xxi.mi_0001'::regclass,
         'MI_0001_Api.map_Item_Result'::regproc,

         p_request_uuid,
         p_message_uuid,
         p_item_uuid,

         p_response_kind,

         p_response_code,
         p_response_info,
         p_response_details,
         p_response_time,

         p_payload_text,

         p_ret_code,
         p_ret_info
   );

END;
$procedure$

-- end_of_Package
;