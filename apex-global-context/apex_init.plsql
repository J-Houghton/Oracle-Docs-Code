-- Replace XXX with the target page_id
DECLARE  
    client_id VARCHAR2(64) := :APP_USER || ':AppName:XXX';
BEGIN
    IF :APP_PAGE_ID = XXX AND :PXXX_SalaryIn IS NOT NULL THEN 
        xxx_app_ctx_helper_pkg.set_parameter_value(client_id, 'P_SalaryIn', :PXXX_SalaryIn);
    END IF;  
EXCEPTION
    WHEN OTHERS THEN
        apex_application.g_notification := '*** APEX ERROR > DB Session|Init: ' || SQLERRM; 
END;