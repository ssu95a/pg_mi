create or replace package MI_prp
CREATE FUNCTION __init__()
   RETURNS 
      void
as
$init$
declare
   /*
      Пакет службы свойств
   */
   cVersion CONSTANT VARCHAR( 100 ) := '$id: {1.0.0} {19.03.2026} Sulimoff$';

   ret_OK      Constant INTEGER := 0;
   ret_Fail    Constant INTEGER := -1;
   ret_No_Data Constant INTEGER := 1;
      
begin
   raise debug 'Package "MI_prp" - % - initialized', cVersion;
end;
$init$


/* */
create function get_Version()
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


/* */
create function make_Prpoperty_Name (  
   in p_objId NUMERIC, -- Id модуля
   in p_prpId VARCHAR  -- Id свойства    
)
   RETURNS
      VARCHAR
   LANGUAGE
      plPGsql
AS
$function$
   #private
   #package
begin

   if p_objId is null or p_prpId is null then
      return p_prpId;
   end if;

   if p_objId = 0::numeric then
      return concat_Ws( '_', 'mi_'::varchar, 'sys'::varchar, null::varchar, p_prpId );
   end if;

   if p_objId < 0::numeric then
      return concat_Ws( '_', 'mi_'::varchar, 'w_'::varchar || abs( p_objId )::varchar, '#'::varchar, p_prpId );
   end if;

   declare
      l_wspId varchar;
   begin

      select 'w_' || wsp_id 
        into l_wspId strict 
        from mi_inf where inf_Id = p_objId;

      return concat_Ws( '_', 'mi_'::varchar, l_wspId, 'i_' || p_objId::varchar, p_prpId );

   end;   

end;
$function$


/* Получение свойства АРМ модуля СМЕВ 3*/
CREATE FUNCTION get_Property (
  in p_objId    NUMERIC, -- Id модуля
  in p_prpId    VARCHAR, -- Id свойства    
  in p_defValue VARCHAR DEFAULT NULL::VARCHAR
)
   RETURNS
      VARCHAR
   LANGUAGE
      plPGsql
AS
$function$
   #private
   #package
declare
   l_retValue varchar;
begin

   select pref.Get_Global_Preference(  
      MI_prp.make_Prpoperty_Name( $1, $2 ),
      $3
   )
   into l_retValue;

   RETURN coalesce( l_retValue, $3 );

END;
$function$


/* Получение свойства АРМ модуля СМЕВ 3*/
CREATE FUNCTION get_Wsp_Property (
  in p_wspId    NUMERIC, -- Id модуля
  in p_prpId    VARCHAR, -- Id свойства    
  in p_defValue VARCHAR DEFAULT NULL::VARCHAR
)
   RETURNS
      VARCHAR
   LANGUAGE
      plPGsql
AS
$function$
   #package
declare
   l_retValue varchar;
begin
   return MI_prp.get_Property( p_wspId * -1, p_prpId, p_defValue );
END;
$function$


/* Получение свойства модуля */
CREATE FUNCTION get_Inf_Property (
  in p_infId    NUMERIC, -- Id модуля
  in p_prpId    VARCHAR, -- Id свойства    
  in p_defValue VARCHAR DEFAULT NULL::VARCHAR
)
   RETURNS
      VARCHAR
   LANGUAGE
      plPGsql
AS
$function$
   #package
declare
   l_retValue varchar;
begin
   return MI_prp.get_Property( p_infId, p_prpId, p_defValue );
END;
$function$


/* Получение свойства системы*/
CREATE FUNCTION get_Sys_Property (
  in p_prpId    VARCHAR, -- Id свойства    
  in p_defValue VARCHAR DEFAULT NULL::VARCHAR
)
   RETURNS
      VARCHAR
   LANGUAGE
      plPGsql
AS
$function$
   #package
declare
   l_retValue varchar;
begin
   return MI_prp.get_Property( 0, p_prpId, p_defValue );
END;
$function$


-- end_Of_Package
;
