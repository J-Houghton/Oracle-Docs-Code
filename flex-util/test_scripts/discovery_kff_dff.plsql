-- SECTION 3 -- ORDER BY toggle
-- 3a. orderBy = 'Y' (default): output should include ORDER BY CREATION_DATE DESC
-- 3b. orderBy = 'N': output should not include ORDER BY clause
DECLARE
    l_sql CLOB;
BEGIN
    l_sql := XXX_FLEX_UTIL.dff_sample_sql(
                 dffName     => 'GL_JE_HEADERS',
                 contextCode => 'Global Data Elements',
                 baseTable   => 'GL_JE_HEADERS',
                 orderBy     => 'Y'  -- toggle between 'Y' and 'N' to compare
             );
    DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(l_sql, 32767, 1));
END;
/

-- SECTION 4 -- DFF discovery (dff_list_rc / dff_attrs_rc)
VAR rc REFCURSOR;
BEGIN
    -- List DFFs; pass appShortName => 'GL' to narrow scope
    :rc := XXX_FLEX_UTIL.dff_list_rc(appShortName => NULL, showSystem => 'N');
END;
/
PRINT rc;

BEGIN
    -- Attribute detail for a specific DFF; NULL contextCode = all contexts
    :rc := XXX_FLEX_UTIL.dff_attrs_rc(
               dffName     => 'GL_JE_HEADERS',
               contextCode => NULL
           );
END;
/
PRINT rc;

-- SECTION 5 -- KFF discovery (kff_list_rc / kff_segs_rc)
BEGIN
    :rc := XXX_FLEX_UTIL.kff_list_rc(appShortName => 'SQLGL');
END;
/
PRINT rc;

BEGIN
    :rc := XXX_FLEX_UTIL.kff_segs_rc(
               kffCode       => 'GL#',
               structureCode => NULL  -- NULL returns all structures
           );
END;
/
PRINT rc;