SET DEFINE OFF;

CREATE OR REPLACE PACKAGE XXX_FLEX_UTIL AS
/**********************************************************************************************
    NAME:       XXX_FLEX_UTIL

    PURPOSE:    EBS Flexfield Utility, Provides discovery and sample-data routines for DFFs and KFFs.
                All public functions return SYS_REFCURSORs or CLOBs so callers can choose how to consume results; 
                    the [dff|kff]_data_out wrappers print directly via DBMS_OUTPUT for quick SQL Developer use.
        
    Public API
        DFF  : dff_list_rc, dff_attrs_rc, dff_sample_sql, dff_sample_html, dff_data_out
        KFF  : kff_list_rc, kff_segs_rc,  kff_sample_sql, kff_sample_html, kff_data_out 

    Date        Version      Description
    ----------  -----------  ------------------------------------
    03/05/2026  v1           Created this package to track KFFs and DFFs automatically
**********************************************************************************************/  

    -- Shared type: holds one segment/attribute column name and display label.
    -- Used by the internal build and exec routines.
    TYPE T_SEG_REC IS RECORD (
        col_name  VARCHAR2(30),
        label     VARCHAR2(240)
    );
    TYPE T_SEG_TAB IS TABLE OF T_SEG_REC INDEX BY PLS_INTEGER;

    -- ========================================================================= 
    -- DFFs
    -- ========================================================================= 

    -- Returns one row per enabled DFF context/attribute combination
    -- Pass p_show_system => 'Y' to include Oracle created entries
    FUNCTION DFF_LIST_RC(
        appShortName IN VARCHAR2 DEFAULT NULL,
        search       IN VARCHAR2 DEFAULT NULL,
        showSystem   IN VARCHAR2 DEFAULT 'N'
    ) RETURN SYS_REFCURSOR;

    -- Returns attribute detail for a single DFF; NULL contextCode returns all contexts
    FUNCTION DFF_ATTRS_RC(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2 DEFAULT NULL
    ) RETURN SYS_REFCURSOR;

    -- Returns a formatted, ready-to-run SELECT statement as a CLOB
    FUNCTION DFF_SAMPLE_SQL(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2,
        baseTable   IN VARCHAR2,
        orderBy     IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB;

    -- Returns sample data rendered as Markdown for APEX or similar HTML consumers
    FUNCTION DFF_SAMPLE_HTML(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2,
        baseTable   IN VARCHAR2,
        rows        IN NUMBER   DEFAULT 25,
        orderBy     IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB;

    -- Prints sample DFF data to DBMS_OUTPUT (SQL Developer convenience wrapper)
    PROCEDURE DFF_DATA_OUT(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2,
        baseTable   IN VARCHAR2,
        rows        IN NUMBER   DEFAULT 25,
        orderBy     IN VARCHAR2 DEFAULT 'Y'
    );

    -- =========================================================================
    -- KFFs
    -- =========================================================================

    -- Returns one row per enabled KFF structure with segment count
    FUNCTION KFF_LIST_RC(
        appShortName IN VARCHAR2 DEFAULT NULL,
        search       IN VARCHAR2 DEFAULT NULL
    ) RETURN SYS_REFCURSOR;

    -- Returns segment detail for a KFF; NULL structureCode returns all structures
    FUNCTION KFF_SEGS_RC(
        kffCode       IN VARCHAR2,
        structureCode IN VARCHAR2 DEFAULT NULL
    ) RETURN SYS_REFCURSOR;

    -- Returns a formatted, ready-to-run SELECT statement as a CLOB
    FUNCTION KFF_SAMPLE_SQL(
        kffCode       IN VARCHAR2,
        structureCode IN VARCHAR2,
        orderBy       IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB;

    -- Returns sample data rendered as Markdown for APEX or similar HTML consumers
    FUNCTION KFF_SAMPLE_HTML(
        kffCode       IN VARCHAR2,
        structureCode IN VARCHAR2,
        rows          IN NUMBER   DEFAULT 25,
        orderBy       IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB;

    -- Prints sample KFF data to DBMS_OUTPUT
    PROCEDURE KFF_DATA_OUT(
        kffCode       IN VARCHAR2,
        structureCode IN VARCHAR2,
        rows          IN NUMBER   DEFAULT 25,
        orderBy       IN VARCHAR2 DEFAULT 'Y'
    );

END XXX_FLEX_UTIL;
/