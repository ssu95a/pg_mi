CREATE OR REPLACE PACKAGE MI_Person_Api

/* Тип для хранения списка используемых атрибутов из
   Person для конкретного inf */
CREATE TYPE MI_Person_Api.Inf_Attrs_t AS (
   inf_List int4[],
   atr_List varchar[]
)

CREATE FUNCTION __init__()
   RETURNS 
      void
AS
$init$
DECLARE
   /*
    Пакет для ведения логики MS
    Модуль person
   */
   cVersion Constant VARCHAR( 100 ) := '$id: {1.0.0} {11.03.2026} $';

   RET_OK   Constant numeric := 0;
   RET_FAIL Constant numeric := -1;

   cPkg_Name CONSTANT varchar(20) := 'MI_Person_Api'; 
   cLogger   Constant varchar(30) := 'ms.person';

   g_inf_Attrs MI_Person_Api.inf_Attrs_t[] := array[
      -- Паспорта
      ( array[74,75], array['doc_type_id', 'doc_ser', 'doc_num', 'doc_issue_date'] )::MI_Person_Api.inf_Attrs_t,
      ( array[1],     array['snils'] )::MI_Person_Api.inf_Attrs_t
   ];

BEGIN
   raise debug 'Package "MI_Person_Api" - % - initialized', cVersion;
END;
$init$


/* Версия */
CREATE FUNCTION get_Version()
   returns
      varchar
   LANGUAGE
      plpgsql
AS 
$function$
   #package
begin
   return cVersion;
end;
$function$


/* дебажим */
CREATE PROCEDURE dbg (
   in p_message_text  varchar,
   in p_inf_id        numeric default null::numeric,
   in p_details_Text  text    default null::text,
   in p_action_cd     varchar default null::varchar,
   in p_context_Value varchar default null::varchar,
   in p_person_id     numeric default null::numeric,
   in p_icusnum       numeric default null::numeric
)
AS
$procedure$
   #package
   #private
BEGIN
   CALL mi_logger.debug ( 
      p_logger_name  => cLogger, 
      p_message_text => p_message_text::text, 
      p_inf_id       => p_inf_id::numeric,
      p_details_text => p_details_text::text, 
      p_action_cd    => p_action_cd::varchar, 
      p_context_value=> p_context_value::varchar,
      p_object_name  => 'mi_person'::varchar, 
      p_person_id    => p_person_id::numeric, 
      p_icusnum      => p_icusnum::numeric 
   );
END;
$procedure$

/* inf */
CREATE PROCEDURE inf(
   in p_message_text  varchar,
   in p_inf_id        numeric default null,
   in p_details_text  text    default null,
   in p_action_cd     varchar default null,
   in p_context_value varchar default null,
   in p_person_id     numeric default null,
   in p_icusnum       numeric default null
)
AS
$procedure$
   #package
   #private
BEGIN
   CALL mi_logger.info ( 
      p_logger_name => cLogger, p_message_text => p_message_text, p_inf_id => p_inf_id, p_details_text => p_details_text, 
      p_action_cd => p_action_cd, p_context_value => p_context_value, p_object_name  => 'mi_person', p_person_id => p_person_id, p_icusnum => p_icusnum 
   );
END;
$procedure$

/* err */
CREATE PROCEDURE err (
   in p_message_text  varchar,
   in p_inf_id        numeric default null,
   in p_details_text  text    default null,
   in p_action_cd     varchar default null,
   in p_context_value varchar default null,
   in p_person_id     numeric default null,
   in p_icusnum       numeric default null
)
AS
$procedure$
   #package
   #private
BEGIN
   CALL mi_logger.error ( 
      p_logger_name => cLogger, p_message_text => p_message_text, p_inf_id => p_inf_id, p_details_text => p_details_text, 
      p_action_cd => p_action_cd, p_context_value => p_context_value, p_object_name  => 'mi_person', p_person_id => p_person_id, p_icusnum => p_icusnum 
   );
END;
$procedure$


/* Данные физ лица по person_Id */
create function get_Person ( 
   in p_person_Id numeric 
) 
   returns
      xxi.mi_person
AS 
$function$
   #package
declare
   r xxi.mi_person%rowType;
begin

   select *
     into strict r
     from xxi.mi_person
    where person_id = p_person_id;

   return r;

end;
$function$


/* Сравнение двух "Person"- записей (normalized compare)
create function eq_Person ( 
   in p_n1 xxi.mi_person,
   in p_n2 xxi.mi_person
) 
   returns 
      BOOLEAN 
   LANGUAGE
      plpgsql
AS 
$function$
   #package
BEGIN
   RETURN
      concat_Ws( ':', p_n1.first_Name, p_n1.last_Name, p_n1.middle_Name, p_n1.ctzn_Country_Code, p_n1.birth_Date, p_n1.inn, p_n1.doc_Type_Id, p_n1.doc_Ser, p_n1.doc_Num, p_n1.doc_Issue_Date )
      =
      concat_Ws( ':', p_n2.first_Name, p_n2.last_Name, p_n2.middle_Name, p_n2.ctzn_Country_Code, p_n2.birth_Date, p_n2.inn, p_n2.doc_Type_Id, p_n2.doc_Ser, p_n2.doc_Num, p_n2.doc_Issue_Date )
      ;
END;
$function$
 */

/*
   Нормализация входного json: 
    - null-ключи выкидываем
*/
CREATE FUNCTION json_Normalize (
   in p_person_J jsonb
)
   RETURNS 
      jsonb
   LANGUAGE 
      plpgsql
AS
$function$
   #package
   #private
BEGIN
   RETURN jsonb_strip_nulls( coalesce(p_person_J, '{}'::jsonb) );
END;
$function$


/* Построить person-кандидата payload переданных данных */
CREATE FUNCTION json_Build_Person (
   in p_person_J jsonb
)
   RETURNS 
      xxi.mi_person
   LANGUAGE 
      plpgsql
AS
$function$
   #package
   #private
DECLARE
   r_person xxi.mi_person%RowType;
BEGIN
   r_person := jsonb_populate_record (
      null::xxi.mi_person,
      MI_Person_Api.json_Normalize(p_person_J)
   );
   RETURN r_person;
END;
$function$


/* Проверить, что в json есть все нужные атрибуты и они не null */
CREATE FUNCTION json_Contains_All_Attrs (
   in p_person_J jsonb,
   in p_attrs    varchar[]
)
   RETURNS
      boolean
   LANGUAGE 
      plpgsql
AS
$function$
   #package
   #private
DECLARE
   c text;
   j jsonb;
BEGIN

   if p_attrs is null or array_length(p_attrs, 1) is null 
   then
      return false;
   end if;

   FOREACH c IN ARRAY p_attrs
   LOOP
      IF NOT (p_person_J ? c) THEN
         RETURN false;
      END IF;

      j := p_person_J -> c;

      IF j IS NULL OR j = 'null'::jsonb THEN
         RETURN false;
      END IF;
   END LOOP;

   RETURN true;
END;
$function$


/* 
   Построить динамический SQL для получения экземпляра person
   Параметры:
   p_by_inf = true  -> искать только среди person, уже связанных с inf_id
   p_by_inf = false -> искать глобально по всей mi_person
*/
CREATE FUNCTION build_Match_Sql_Select(
   in p_attrs  varchar[],
   in p_by_inf boolean
)
   RETURNS 
      text
AS
$function$
   #package
   #private
DECLARE
   l_pred text;
   l_sql  text;
BEGIN

   IF p_attrs IS NULL OR array_length(p_attrs, 1) IS NULL THEN
      RAISE EXCEPTION USING
            ERRCODE = 'MI',
            MESSAGE = 'MI_Person_Api#build_Match_Sql_Select: p_attrs is empty';
   END IF;

   SELECT string_agg (
             format('p.%I is not distinct from ($1).%I', c, c),
             ' and '
          )
     INTO l_pred
     FROM unnest(p_attrs) c;

   IF p_by_inf THEN
      l_sql :=
      'select p.person_id
         from xxi.mi_person p
         join xxi.mi_p2i i
           on i.person_id = p.person_id
        where i.inf_id = $2
          and ' || l_pred || '
        order by p.created_at desc, p.person_id desc
        limit 1';
   ELSE
      l_sql :=
      'select p.person_id
         from xxi.mi_person p
        where ' || l_pred || '
        order by p.created_at desc, p.person_id desc
        limit 1';
   END IF;

   RETURN l_sql;

END;
$function$


/* 
   Выполнить поиск по exact/null-safe профилю
   Сначала среди person этого inf_id, потом глобально.
*/
CREATE FUNCTION try_Find_Person_Id (
   in p_inf_id numeric,
   in p_person xxi.mi_person,
   in p_attrs  varchar[]
)
   RETURNS numeric
   LANGUAGE plpgsql
AS
$function$
   #package
   #private
DECLARE
   l_person_id numeric;
   l_sql       text;
BEGIN

   l_sql := MI_Person_Api.build_Match_Sql_Select(p_attrs, true);

   CALL MI_Person_Api.dbg(
      p_message_text => 'try_Find_Person_Id by inf_Id'::varchar,
      p_inf_id       => p_inf_id::numeric,
      p_details_text => l_sql::text,
      p_action_cd    => 'sql'::varchar,
      p_icusnum      => p_person.icusnum::numeric
   );

   EXECUTE l_sql
      INTO l_person_id
     USING 
           p_person, p_inf_id;

   IF l_person_Id IS NOT NULL THEN
      RETURN l_person_id;
   END IF;

   l_sql := MI_Person_Api.build_Match_Sql_Select(p_attrs, false);

   CALL MI_Person_Api.dbg(
      p_message_text => 'try_Find_Person_Id global'::varchar,
      p_inf_id       => p_inf_id::numeric,
      p_details_text => l_sql::text,
      p_action_cd    => 'sql'::varchar,
      p_icusnum      => p_person.icusnum::numeric
   );

   EXECUTE l_sql
      INTO l_person_id
      USING p_person;

   RETURN l_person_id;
END;
$function$


/* Найти person ID для inf */
CREATE FUNCTION find_Person_Id (
   in p_inf_id   numeric,
   in p_person_r xxi.mi_person,
   in p_person_j jsonb
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
   l_person_id numeric;
   l_attrs     varchar[];
   l_itm       MI_Person_Api.inf_Attrs_t;
   l_inf       int4;
BEGIN
   l_attrs := null;

   FOREACH l_itm IN ARRAY g_inf_Attrs
   LOOP
      FOREACH l_inf IN ARRAY l_itm.inf_list
      LOOP
         IF l_inf = p_inf_id THEN
            l_attrs := l_itm.atr_list;
            EXIT;
         END IF;
      END LOOP;

      EXIT WHEN l_attrs IS NOT NULL;
   END LOOP;

   CALL MI_Person_Api.dbg(
      p_message_text => 'find_Person_Id profile selected',
      p_inf_id       => p_inf_id,
      p_details_text => coalesce( array_to_string(l_attrs, ','), '<NULL>'),
      p_action_cd    => 'find',
      p_icusnum      => p_person_r.icusnum
   );

   IF l_attrs IS NULL OR array_length(l_attrs, 1) IS NULL THEN
      RETURN NULL;
   END IF;

   IF MI_Person_Api.json_Contains_All_Attrs(p_person_j, l_attrs) THEN
      l_person_id := MI_Person_Api.try_Find_Person_Id(
         p_inf_id,
         p_person_r,
         l_attrs
      );
      IF l_person_id IS NOT NULL THEN
         RETURN l_person_id;
      END IF;
   END IF;

   RETURN NULL;
END;
$function$


/* 
   Вставить нового person
   created_at и person_id из default
*/
CREATE FUNCTION insert_Person(
   in p_person xxi.mi_person
)
   RETURNS numeric
   LANGUAGE plpgsql
AS
$function$
   #package
   #private
DECLARE
   l_person_id numeric;
BEGIN
   INSERT INTO xxi.mi_person(
      icusnum,
      first_name,
      last_name,
      middle_name,
      first_name_lat,
      last_name_lat,
      middle_name_lat,
      gender_id,
      ctzn_type_id,
      ctzn_country_code,
      inn,
      snils,
      doc_type_id,
      doc_type_code,
      doc_ser,
      doc_num,
      doc_issue_date,
      doc_issuer_code,
      doc_expire_date,
      doc_issuer_name,
      doc_invalid_from,
      birth_date,
      birth_date_raw,
      birth_place,
      death_date,
      phone,
      email,
      region_code,
      coid
   )
   VALUES(
      p_person.icusnum,
      p_person.first_name,
      p_person.last_name,
      p_person.middle_name,
      p_person.first_name_lat,
      p_person.last_name_lat,
      p_person.middle_name_lat,
      p_person.gender_id,
      p_person.ctzn_type_id,
      p_person.ctzn_country_code,
      p_person.inn,
      p_person.snils,
      p_person.doc_type_id,
      p_person.doc_type_code,
      p_person.doc_ser,
      p_person.doc_num,
      p_person.doc_issue_date,
      p_person.doc_issuer_code,
      p_person.doc_expire_date,
      p_person.doc_issuer_name,
      p_person.doc_invalid_from,
      p_person.birth_date,
      p_person.birth_date_raw,
      p_person.birth_place,
      p_person.death_date,
      p_person.phone,
      p_person.email,
      p_person.region_code,
      p_person.coid
   )
   RETURNING person_id
        INTO l_person_id;

   CALL MI_Person_Api.inf(
      p_message_text => 'person inserted',
      p_action_cd    => 'insert',
      p_person_id    => l_person_id,
      p_icusnum      => p_person.icusnum
   );        

   RETURN l_person_id;
END;
$function$


/* Связть person к mi_inf*/
CREATE PROCEDURE link_Person_To_Inf (
   in p_person_id numeric,
   in p_inf_id    numeric
)
   LANGUAGE 
      plpgsql
AS
$procedure$
   #package
   #private
BEGIN
   INSERT INTO xxi.mi_p2i( person_id, inf_id )
   VALUES (p_person_id, p_inf_id)
   ON CONFLICT (person_id, inf_id)
      DO NOTHING;

   CALL MI_Person_Api.dbg(
      p_message_text => 'person linked to inf',
      p_inf_id       => p_inf_id,
      p_action_cd    => 'link',
      p_person_id    => p_person_id
   );

END;
$procedure$


/* 
   Главная публичная функция по работе с person
*/
CREATE FUNCTION get_Or_Create(
   in p_inf_id   numeric,
   in p_person_J jsonb
)
   returns 
      numeric
AS
$function$
   #package
DECLARE
   l_person    xxi.MI_person%rowtype;
   l_person_id NUMERIC;
   l_json      jsonb;
BEGIN
/*
   in p_message_text  varchar,
   in p_inf_id        numeric default null::numeric,
   in p_details_Text  text    default null::text,
   in p_action_cd     varchar default null::varchar,
   in p_context_Value varchar default null::varchar,
   in p_person_id     numeric default null::numeric,
   in p_icusnum       numeric default null::numeric
*/
   CALL MI_Person_Api.dbg ( 
         'get_Or_Create enter'::varchar, 
          p_inf_id::numeric, 
          left( coalesce(p_person_J::text, '<NULL>'::text), 2000)::text, 
          'enter_f'::varchar, null::varchar, 
          null::numeric, null::numeric 
        );

   l_json   := MI_Person_Api.json_Normalize(p_person_J);
   l_person := MI_Person_Api.json_Build_Person(l_json);

   -- CALL dbg ( 'person built'::varchar, p_inf_id::numeric, left(l_json::text, 2000)::text, 'val'::varchar, l_person.icusnum::numeric );   

   l_person_id := MI_Person_Api.find_Person_Id (
      p_inf_id,
      l_person,
      l_json
   );

   IF l_person_id IS NULL THEN

      CALL MI_Person_Api.dbg (
         'person not found, insert'::varchar, p_inf_id::numeric, null::text, 'insert'::varchar, null::varchar, null::numeric, l_person.icusnum::numeric
      );

      l_person_id := MI_Person_Api.insert_Person(l_person);

   ELSE

      CALL MI_Person_Api.dbg (
         'person matched'::varchar, p_inf_id::numeric, null::text, 'find'::varchar, null::varchar, l_person_id::numeric, l_person.icusnum::numeric 
      );

   END IF;

   CALL MI_Person_Api.link_Person_To_Inf(l_person_id, p_inf_id);

   RETURN l_person_id;

END;
$function$


/* Если icusnum приходит отдельно от json */
CREATE FUNCTION get_Or_Create(
   in p_inf_id   numeric,
   in p_icusnum  numeric,
   in p_person_J jsonb
)
   RETURNS 
      numeric
   LANGUAGE 
      plpgsql
AS
$function$
   #package
DECLARE
   l_json jsonb;
BEGIN
   
   l_json := coalesce(p_person_J, '{}'::jsonb);

   IF p_icusnum IS NOT NULL AND NOT (l_json ? 'icusnum') THEN
      l_json := l_json || jsonb_build_object('icusnum', p_icusnum);
   END IF;

   RETURN MI_Person_Api.get_Or_Create(p_inf_id, l_json);
END;
$function$


/* Id последней записи person, для icusnum */
create function get_Last_person_Id (
   in p_icusnum numeric,
   in p_inf_id  numeric default null
)
   returns
      numeric
   language
      plpgsql
AS
$function$
   #package
declare
   l_person_Id numeric;
begin

   select person_id
          into l_person_id
     from xxi.mi_person p
    where 
         icusnum = p_icusnum
      and ( p_inf_id is null or exists ( select null from xxi.mi_p2i l where l.person_id = p.person_id and l.inf_id = p_inf_id ) )      
    order 
         by created_at desc, person_id desc
    limit 1;

   return l_person_Id;

end;
$function$

/*end_Of_Package*/
;