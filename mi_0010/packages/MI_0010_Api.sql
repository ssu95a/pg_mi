create or replace package MI_0010_Api

CREATE FUNCTION __init__()
	RETURNS void
AS
$init$
DECLARE
	/*
		Entry point логики вида сведений 0010
	*/
	cVersion  CONSTANT varchar(100) := '$id: {1.0.0} {16.07.2026}$';

	cPkg_Name CONSTANT varchar(20 ) := 'mi_0010_Api'; 
	cLogger   CONSTANT varchar(20 ) := 'mi.0010'; 

	ret_OK    CONSTANT int4 := 0;
	ret_FAIL  CONSTANT int4 := -1;

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


/* 
   Построить json-person из параметров
*/
CREATE FUNCTION build_Json_Person (

   in p_last_name   varchar,
   in p_first_name  varchar,
   in p_middle_name varchar,

   in p_inn varchar,

   in p_birth_date 	 date,
   in p_death_date	 date,

   in p_doc_Type_Id	 numeric,
   in p_doc_Series	 varchar,
   in p_doc_Number	 varchar,
   in p_doc_Issue_Date date
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
         'last_name',      p_last_name,
         'first_name',     p_first_name,
         'middle_name',    p_middle_name,
         'birth_date',     p_birth_date,
         'death_date',		p_death_date,
         'doc_type_id',    p_doc_Type_Id,
         'doc_ser',        p_doc_series,
         'doc_num',        p_doc_number,
         'doc_issue_date', p_doc_issue_date,
         'inn', 				p_inn
      );

   RETURN jsonb_strip_nulls(l_json);

END;
$function$


/*
	Сохранить доп атрибуты для клиента
	по настройке сохраняем также 
	для связанных по 17 связи клиентов
*/
create procedure save_Cus_Attrs (
	p_itm_Id   IN  numeric,
	p_iCusNum  IN  numeric
)
AS
$procedure$
	#package
DECLARE

	l_update17Lnk boolean := MI_prp.get_Inf_Property( 23, 'INF_23_UPDATE_17_LNK', '0' ) <> '1';

	c_attr_Info CURSOR 
	for
		SELECT Rec_Num, rec_date,
				 zags_Code, zags_Name, iPr_dBth, iPr_dDth, 
				 to_char( DeReg_Date,'DD.MM.YYYY' ) cDeReg
		  FROM xxi.mi_0010
		 WHERE 
				 itm_Id = p_itm_Id;

	l_row record;

	l_ret int4;

	l_cus_Id	  numeric;
	l_ids_List numeric[] := '{}';

begin

		open c_attr_info; 
			fetch c_attr_info into l_row; 
				close c_attr_info;

		if l_update17Lnk then

			l_ids_List := array (
				SELECT icusnum FROM (
					SELECT id_cus_parent AS icusnum FROM cus_lnk WHERE id_Lnk_Type = 17 AND id_Cus_child = p_iCusNum
					UNION
				  	SELECT id_cus_child FROM cus_lnk WHERE id_Lnk_Type = 17 AND id_Cus_parent = p_iCusNum
				  	UNION
				  	SELECT p_iCusNum
				) t
			);

		else
			l_ids_List := l_ids_List || p_iCusNum;
		end if;

		foreach l_cus_Id in array l_ids_List
		loop
		
			l_ret := pcusattr.set_cli_add_attr( l_cus_Id, NULL, 329, l_row.rec_date::varchar );
			
			IF l_row.Rec_Num IS NOT NULL THEN
				l_ret := pcusattr.set_cli_add_attr( l_cus_Id, 699, 700, l_row.Rec_Num::varchar );
			END IF;
			IF l_row.rec_date IS NOT NULL THEN
				l_ret := pcusattr.set_cli_add_attr( l_cus_Id, 699, 701, l_row.rec_Date::varchar);
			END IF;
			IF l_row.zags_name IS NOT NULL THEN
				l_ret := pcusattr.set_cli_add_attr( l_cus_Id, 699, 702, l_row.zags_name );
			END IF;
			IF l_row.zags_code IS NOT NULL THEN
				l_ret := pcusattr.set_cli_add_attr( l_cus_Id, 699, 703, l_row.zags_code );
			END IF;                                                                                                              
			IF l_row.iPr_dBth IS NOT NULL THEN
				l_ret := pcusattr.set_cli_add_attr( l_cus_Id, 699, 704, l_row.iPr_dBth::varchar );
			END IF;
			IF l_row.iPr_dDth IS NOT NULL THEN
				l_ret := pcusattr.set_cli_add_attr( l_cus_Id, 699, 705, l_row.iPr_dDth::varchar );
			END IF;
			IF l_row.cDeReg IS NOT NULL THEN
				l_ret := pcusattr.set_cli_add_attr( l_cus_Id, 699, 709, l_row.cDeReg );
			END IF;

		end loop;
	
END;
$procedure$


/* */
CREATE PROCEDURE apply_Request (

   in p_message_uuid          uuid,
   in p_original_request_uuid uuid,
   in p_correlation_id        uuid,

   in p_request_time          timestamptz,

   in p_ctaxreq_id            varchar,

   in p_payload_text          text,

  out p_ret_code              int4,
  out p_ret_info              varchar
)
AS
$procedure$
   #package
declare

	l_payLoad jsonb;

	l_req_Id  numeric(12);
	l_itm_Id  numeric(12);

	l_person_Id 	numeric(12);
	l_person_J  	jsonb;

	l_doc_Typ_Cod	varchar;
	l_doc_Typ_Num	numeric;
	l_doc_Ser_num	varchar;
	l_doc_Ser		varchar;
	l_doc_Num		varchar;

	l_update17Lnk  numeric := MI_prp.get_Inf_Property( 23, 'INF_23_UPDATE_17_LNK', '0' )::numeric;

begin

   call MI_logger.enter_f( cLogger, cPkg_Name || '.apply_Item_Result', 'p_message_uuid = ' || p_message_uuid || ', p_ctaxreq_id = ' || p_ctaxreq_id );

   p_ret_code := ret_Fail;
   p_ret_info := NULL;

   IF p_message_uuid IS NULL THEN
      p_ret_info := 'p_message_uuid is null';
      return;
   END IF;

   IF p_ctaxreq_id IS NULL THEN
      p_ret_info := 'p_ctaxreq_id is null';
      return;
   END IF;

   IF p_request_time IS NULL THEN
      p_ret_info := 'p_request_time is null';
      return;
   END IF;

	IF p_payload_text IS NULL OR btrim(p_payload_text) = '' THEN
      p_ret_info := 'p_payload_text is null';
      return;
	END IF;

	call MI_item_Result_Api.parse_Json_Payload( p_payload_text, l_payLoad, p_ret_code, p_ret_Info );

	if p_ret_code <> ret_OK then
		return;
	end if;

	l_doc_Typ_Cod := replace( l_payLoad -> 'identityDocument' ->> 'docType', ' ', '' );

	/* Разбираем тип документа */
   SELECT MIN(pud.iPudId)
          INTO l_doc_Typ_Num
     FROM pud
    WHERE 
          pud.cpudCode9 = l_doc_Typ_Cod
      AND pud.ipuduse = 0;

	if l_doc_Typ_Num is null then
		p_ret_Info := 'Не удается по коду "' || l_doc_Typ_Cod  || '" определить тип ДУЛа в таблице pud'; 
		return;
	end if;

	/* Разбираем серию номер документа */
   IF l_doc_Typ_Cod = '21' THEN
      -- Паспорт может приходить по разному
		l_doc_Ser_num := replace( l_payLoad -> 'identityDocument' ->> 'seriesNumber', ' ', '' );
	   l_doc_Ser := SUBSTR( r_nat.CDOC_SER_NUM, 1, 4 );
      l_doc_Num := SUBSTR( r_nat.CDOC_SER_NUM, 5 );
   ELSE         
		l_doc_Ser_num := l_payLoad -> 'identityDocument' ->> 'seriesNumber';
      l_doc_Ser := trim(REGEXP_SUBSTR( r_nat.CDOC_SER_NUM, '\w*' ));
      l_doc_Num := trim(REGEXP_SUBSTR( r_nat.CDOC_SER_NUM, '\s+\w*' ));
   END IF;         

   IF l_doc_Num IS NULL THEN 
      l_doc_Num := l_doc_Ser; 
      l_doc_Ser := NULL; 
   END IF;

	l_person_J := MI_0010_Api.build_Json_Person (
		
		p_json -> 'fullName' ->> 'family',
		p_json -> 'fullName' ->> 'firstName',
		p_json -> 'fullName' ->> 'patronymic',
		
		p_json ->> 'inn',

		NULLIF( p_json ->> 'birthDate', '' )::date,
		NULLIF( p_json ->> 'deathDate', '' )::date,

		l_doc_Typ_Num,
		l_doc_Ser,
		l_doc_Num,
		NULLIF(p_json -> 'identityDocument' ->> 'issueDate', '')::date
	);

	l_person_id := mi_person_Api.get_Or_Create( 10::numeric, l_person_J );

	/*
		Пишем заголовок внешнего запроса
	*/
	l_req_Id := MI_Request_Api.create_Request(
	   p_inf_id                => 10::numeric,
	   p_correlation_id        => p_correlation_id,
	   p_original_request_uuid => p_original_request_uuid,
	   p_ctaxreq_id            => p_ctaxreq_id,
	   p_message_uuid          => p_message_uuid,
	   p_status_cd             => 1::numeric
	);

	/* Данные внешнего запроса */
	insert into 
		xxi.mi_0010( req_id, message_uuid, person_id, rec_num, rec_date, zags_code, zags_name, dereg_date, ipr_dbth, ipr_ddth, ipr_cus17 )
	values( l_req_Id, 
			  p_message_uuid, 
			  l_person_id, 
			  l_payLoad ->> 'actRecordNumber',
			 (l_payLoad ->> 'actRecordDate')::date, 
			  l_payLoad ->> 'registryOfficeCode',
			  l_payLoad ->> 'registryOfficeName',
			 (l_payLoad ->> 'deregistrationDate')::date,
			 (l_payLoad ->> 'birthDateFlag')::numeric,
			 (l_payLoad ->> 'deathDateFlag')::numeric,
			 l_update17Lnk
			 )	
returning
		itm_Id into l_itm_Id;

		p_ret_code := ret_OK;

END;
$procedure$

; -- end_Of_Package
