BEGIN
    DBMS_OUTPUT.PUT_LINE('=== BEGIN ==='); 

    xxx_app_ctx_helper_pkg.set_parameter_value('client_id123', 'ATTRIBUTEIN', 'valueIN');
    DBMS_OUTPUT.PUT_LINE(SYS_CONTEXT('TEST_APP_CTX', 'ATTRIBUTEIN'));  
    
    FOR r IN (SELECT namespace, attribute, value FROM GLOBAL_CONTEXT) LOOP
        DBMS_OUTPUT.PUT_LINE(r.namespace || ':' || r.attribute || '=' || r.value);
    END LOOP;
    
    xxx_app_ctx_helper_pkg.clear_ctx('client_id123');
    DBMS_OUTPUT.PUT_LINE('==== END ====');
END;

-- Expected output:
-- === BEGIN ===
-- valueIN
-- TEST_APP_CTX:ATTRIBUTEIN=valueIN
-- ==== END ====