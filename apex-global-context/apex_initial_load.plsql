-- Place in: Page → Before Header → Process → Execute PL/SQL Code
IF :APP_PAGE_ID = XXX THEN
    DECLARE  
        client_id     VARCHAR2(64) := :APP_USER || ':AppName:XXX';
        defaultSalary NUMBER       := 1000; -- or: SELECT col INTO defaultSalary FROM table
    BEGIN
        IF :PXXX_SalaryIn IS NULL THEN 
            xxx_app_ctx_helper_pkg.set_parameter_value(client_id, 'P_SalaryIn', defaultSalary);
        END IF;  
    EXCEPTION
        WHEN OTHERS THEN
            apex_application.g_notification := '*** APEX ERROR > Init Seed: ' || SQLERRM; 
    END;
END IF;