-- Replace XXX with the target page_id
DECLARE
    client_id VARCHAR2(64) := :APP_USER || ':AppName:XXX';
BEGIN      
    xxx_app_ctx_helper_pkg.clear_ctx(client_id);
EXCEPTION 
    WHEN OTHERS THEN 
        apex_application.g_notification := '*** APEX ERROR > DB Session|Cleanup: ' || SQLERRM;
END;