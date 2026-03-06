CREATE OR REPLACE PACKAGE BODY xxx_app_ctx_helper_pkg AS
    PROCEDURE set_parameter_value(p_client_id IN VARCHAR2, p_attr IN VARCHAR2, p_val IN VARCHAR2) IS
    BEGIN
        DBMS_SESSION.set_context(
            namespace  => 'TEST_APP_CTX',
            attribute  => UPPER(p_attr),
            value      => p_val,
            username   => null,
            client_id  => p_client_id
        );
    END;
    PROCEDURE clear_ctx(p_client_id IN VARCHAR2) IS
    BEGIN
        DBMS_SESSION.clear_context(
            namespace  => 'TEST_APP_CTX',
            client_id  => p_client_id,
            attribute  => null  -- null clears ALL attributes for this client_id
        );
    END;
END xxx_app_ctx_helper_pkg;
/