create or replace package MI_0001_Api

CREATE FUNCTION __init__()
   RETURNS void
AS
$init$
DECLARE
   /*
      Entry point логики вида сведений 0001
      Работает поверх:
         - mi_req
         - xxi.mi_0001
         - xxi.v_mi_0001_req
         - mi_request_Api
         - mi_person_Api
   */
   
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
create procedure auto_Prepare( )
as
$procedure$ 
   #package
declare

   l_lock_Handle     varchar(100);

   l_wait_Hour_Range  int4   := 72::int4; 
   l_cus_Hour_Range   int4   := MI_prp.get_Wsp_Property( 1, 'CUS_HOUR_RANGE',   '48' )::int4; 
   l_handle_Not_Found boolean:= MI_prp.get_Wsp_Property( 1, 'HANDLE_NOT_FOUND', 'false' )::boolean; 

   l_error_Count      int4   := 0;

   l_doCreate         boolean:= false;  
   l_ids4Remove       numeric[];

   r                  xxi.v_mi_0001_ca%rowtype;

   l_req_Id           numeric;  
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

   l_req_Id := MI_0001_Api.create_Request( 13::numeric );

   for r in ( SELECT * FROM xxi.v_mi_0001_ca WHERE ( current_date - DCUSOPEN ) > make_interval( hours => l_cus_Hour_Range ))
   loop

      call MI_0001_Api.check_4_Prepare( r, l_handle_Not_Found, l_wait_Hour_Range, l_doCreate, l_ids4Remove, l_error_Count, l_result_Info );

      if not l_doCreate then
         continue;
      end if;

      l_itm_id := MI_0001_Api.create_Item( 13::numeric, l_req_Id, r, l_ids4Remove );

   end loop;

end;  
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


/* Сохранить результат обработки одного item */
CREATE PROCEDURE apply_Item_Result (
   in p_request_uuid        uuid,
   in p_message_uuid        uuid,
   in p_item_external_uuid  uuid,

   in p_inn                 varchar,
   in p_ires_code           numeric,
   in p_tres_time           timestamp,
   in p_cres_info           text,

   out p_res_code           int4,
   out p_res_info           varchar
)
AS
$procedure$
   #package
DECLARE

   cAction_Name constant varchar := cPkg_Name || '.apply_Item_Result';

   /*
    * Контракт с Java:
    *
    *  0 = APPLIED - ret_OK
    *  1 = ALREADY_APPLIED
    * -1 = FAILED - ret_Failed
    * -2 = CONFLICT
    *
    * Неожиданные SQL-ошибки не перехватываются.
    * Они должны выйти наружу и привести к retry сообщения.
    */

   cAlreadyApplied constant int4 :=  1;
   cConflict       constant int4 := -2;

   l_itm_id                numeric;
   l_req_id                numeric;

   l_current_message_uuid  uuid;
   l_current_inn           varchar;
   l_current_ires_code     numeric;
   l_current_tres_time     timestamp;
   l_current_cres_info     text;

   l_updated_count         int4;

BEGIN

   p_res_code := ret_FAIL;
   p_res_info := 'Unhandled error in ' || cAction_Name;

   /*
    * Проверка обязательных идентификаторов.
    */
   IF p_request_uuid IS NULL THEN
      p_res_info := 'p_request_uuid is null';
      RETURN;
   END IF;

   IF p_message_uuid IS NULL THEN
      p_res_info := 'p_message_uuid is null';
      RETURN;
   END IF;

   IF p_item_external_uuid IS NULL THEN
      p_res_info := 'p_item_external_uuid is null';
      RETURN;
   END IF;

   IF p_ires_code IS NULL THEN
      p_res_info := 'p_ires_code is null';
      RETURN;
   END IF;

   /*
    * Время результата должно приходить из сообщения.
    * Иначе можно запутаться при retry
    */
   IF p_tres_time IS NULL THEN
      p_res_info := 'p_tres_time is null';
      RETURN;
   END IF;

   /*
    * Находим item внутри конкретного request и сразу блокируем его до завершения транзакции.
    */
   BEGIN
      SELECT i.itm_id,
             i.req_id,
             i.message_uuid,
             i.inn,
             i.ires_code,
             i.tres_time,
             i.cres_info
        INTO STRICT
             l_itm_id,
             l_req_id,
             l_current_message_uuid,
             l_current_inn,
             l_current_ires_code,
             l_current_tres_time,
             l_current_cres_info
        FROM xxi.mi_0001 i
        JOIN xxi.mi_req r
          ON r.req_id = i.req_id
       WHERE r.external_uuid = p_request_uuid
         AND i.external_uuid = p_item_external_uuid
         FOR UPDATE OF i;

   EXCEPTION
      WHEN no_data_found THEN
         p_res_code := ret_Fail;
         p_res_info := 'Item not found: request_external_uuid=' || p_request_uuid || ', item_external_uuid=' || p_item_external_uuid;

         RETURN;

      WHEN too_many_rows THEN
         /*
          * При UNIQUE на mi_0001.external_uuid этого быть
          * не должно. Считаем нарушением данных.
          */
         RAISE EXCEPTION
            'More than one item found: request_external_uuid=%, item_external_uuid=%', p_request_uuid, p_item_external_uuid;
   END;

   /*
    * Item уже был финализирован.
    */
   IF l_current_message_uuid IS NOT NULL THEN

      /*
       * Повторная доставка того же сообщения.
       */
      IF l_current_message_uuid = p_message_uuid THEN

         /*
          * То же сообщение и ровно те же данные:
          * успешный идемпотентный no-op.
          */
         IF l_current_inn IS NOT DISTINCT FROM p_inn
            AND l_current_ires_code IS NOT DISTINCT FROM p_ires_code
            AND l_current_tres_time IS NOT DISTINCT FROM p_tres_time
            AND l_current_cres_info IS NOT DISTINCT FROM p_cres_info
         THEN
            p_res_code := cAlreadyApplied;
            p_res_info :=
                 'Item already applied: itm_id='
                 || l_itm_id
                 || ', message_uuid='
                 || p_message_uuid;

            RETURN;
         END IF;

         /*
          * Тот же UUID сообщения, но данные отличаются.
          * Это нарушение контракта сообщения.
          */
         p_res_code := cConflict;
         p_res_info :=
              'Item replay conflict: message_uuid='
              || p_message_uuid
              || ', itm_id='
              || l_itm_id
              || ', stored result differs from incoming result';

         RETURN;
      END IF;

      /*
       * Item уже обработан другим сообщением.
       * Политика first-wins.
       */
      p_res_code := cConflict;
      p_res_info :=
           'Item already finalized by another message: itm_id='
           || l_itm_id
           || ', stored_message_uuid='
           || l_current_message_uuid
           || ', incoming_message_uuid='
           || p_message_uuid;

      RETURN;
   END IF;

   /*
    * Первое применение результата.
    */
   UPDATE xxi.mi_0001
      SET inn                   = p_inn,
          ires_code             = p_ires_code,
          tres_time             = p_tres_time,
          cres_info             = p_cres_info,
          message_uuid = p_message_uuid
    WHERE itm_id = l_itm_id
      AND message_uuid IS NULL;

   GET DIAGNOSTICS l_updated_count = ROW_COUNT;

   /*
    * Строка заблокирована FOR UPDATE, поэтому отсутствие
    * обновления означает неожиданную проблему состояния.
    * Не превращаем её в бизнес-ответ, пусть XXL сделает retry.
    */
   IF l_updated_count <> 1 THEN
      RAISE EXCEPTION
         'Unexpected item update count: itm_id=%, updated_count=%',
         l_itm_id,
         l_updated_count;
   END IF;

   p_res_code := ret_Ok;
   p_res_info := 'Item applied: itm_id=' || l_itm_id || ', req_id=' || l_req_id || ', message_uuid=' || p_message_uuid;

END;
$procedure$;

-- end_of_Package
;