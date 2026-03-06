CREATE OR REPLACE PACKAGE xxx_app_ctx_helper_pkg AUTHID DEFINER AS

    PROCEDURE set_parameter_value(
        p_client_id IN VARCHAR2, 
        p_attr      IN VARCHAR2, 
        p_val       IN VARCHAR2
    );

    PROCEDURE clear_ctx(p_client_id IN VARCHAR2);

END xxx_app_ctx_helper_pkg;
/