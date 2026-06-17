create or replace package MI_utils
CREATE FUNCTION __init__()
   RETURNS 
      void
as
$init$
declare
   /**
      Пакет для поддержки работы со СМЭВ 3
   */
   cVersion CONSTANT VARCHAR( 100 ) := '$id: {1.0.0} {28.06.2025} Sulimoff$';

   ret_OK          Constant INTEGER := 0;
   ret_Fail        Constant INTEGER := -1;
   ret_No_Data     Constant INTEGER := 1;

   FORMAT_MONEY    CONSTANT VARCHAR(50) := 'FM9999999999999990.9999';
   FORMAT_PERCENT  CONSTANT VARCHAR(50) := 'FM9999999999999990.99999999999999999';
      
begin
   raise debug 'Package "MI_utils" - % - initialized', cVersion;
end;
$init$


/* */
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


/* */
CREATE FUNCTION to_money ( 
   IN s VARCHAR 
)
RETURNS 
   NUMERIC
AS
$function$
begin
   return round( TO_NUMBER( replace( REGEXP_REPLACE( s, '[^,.0-9]', '' ), ',', '.' ), 'FM9999999999999990.9999' ), 2 );
end;   
$function$


/* 
   Блокировка процесса обработки данных, для других сессий
*/
CREATE PROCEDURE lock_Proc (
   in  lockname          VARCHAR,
   in  release_On_Commit BOOLEAN,
   in  locktimeOut       INTEGER,
   out ret_Code          INTEGER,
   out ret_Info          VARCHAR,
   out lock_handle       VARCHAR
)
AS
$procedure$
   #package
declare
   l_lock_Status INTEGER;
begin

   -- sm_logger.enter_f( 'lock_Proc', 'lockname=' || lockname || ', release_on_commit = ' || p_release_on_commit::varchar || ', lock_timeOut =  ' || lock_timeOut  );

   ret_Code := -1;

   call DBMS_LOCK.ALLOCATE_UNIQUE_AUTONOMOUS( $1, $6 );

   l_lock_status := DBMS_LOCK.REQUEST (
      $6,
      6,
      $3,
      $2
   );

   IF l_lock_status IN ( 0, 4 ) THEN
      $4 := RET_OK;
   ELSIF l_lock_status = 1 THEN
      $4 := 1;
      $5 := 'В данный момент идет обработка из другой сессии.';
   ELSE
      $5 := 'Error in call DBMS_LOCK.Request. error num = ' || l_lock_status || ' (' || 
      CASE l_lock_status
         WHEN 0 THEN 'Success'
         WHEN 1 THEN 'Timeout'
         WHEN 2 THEN 'Deadlock'
         WHEN 3 THEN 'Parameter error'
         WHEN 4 THEN 'Already own lock specified by id or lockhandle'
         WHEN 5 THEN 'Illegal lock handle'
         ELSE
            'неизвестный код возврата dbms_lock.Request. ' || l_lock_status 
         END || ')';
   END IF;

   -- sm_logger.exit_f( l_ret, p_resultInfo );
   
END;
$procedure$

-- end_Of_Packages
;

