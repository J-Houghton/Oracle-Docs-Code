-- 1a. GL_JE_LINES uses CONTEXT, not ATTRIBUTE_CATEGORY.
--     Header line should show: Ctx Col: CONTEXT
BEGIN
    XXX_FLEX_UTIL.dff_data_out(
        dffName     => 'GL_JE_LINES',
        contextCode => 'XXX SYSTEM',           -- EDIT: replace with valid context code
        baseTable   => 'GL_JE_LINES',
        rows        => 10,
        orderBy     => 'N'                     -- large table; skip ORDER BY
    );
END;
/

-- 1b. Confirm generated SQL also uses the correct context column
DECLARE
    l_sql CLOB;
BEGIN
    l_sql := XXX_FLEX_UTIL.dff_sample_sql(
                 dffName     => 'GL_JE_LINES',
                 contextCode => 'Purchasing Additions',  -- EDIT: replace with valid context code
                 baseTable   => 'GL_JE_LINES',
                 orderBy     => 'N'
             );
    FOR i IN 0..TRUNC(DBMS_LOB.GETLENGTH(l_sql) / 20000) LOOP
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(l_sql, 20000, (i * 20000) + 1));
    END LOOP;
END;
/

-- 1c. Standard DFF — should resolve ATTRIBUTE_CATEGORY
BEGIN
    XXX_FLEX_UTIL.dff_data_out(
        dffName     => 'FND_FLEX_VALUES',  -- EDIT: replace with a known DFF on your instance
        contextCode => 'XXX_GL_PCA',       -- EDIT: replace with a valid context code for that DFF
        baseTable   => 'FND_FLEX_VALUES',  -- EDIT: replace with the correct base table
        rows        => 5,
        orderBy     => 'Y'
    );
END;
/

-- 1d. REFERENCE QUERY: check context_column_name for any DFF before running the above
SELECT
    descriptive_flexfield_name,
    title,
    application_table_name,
    NVL(context_column_name, '(null — defaults to ATTRIBUTE_CATEGORY)') AS context_column_name
FROM   fnd_descriptive_flexs_vl
WHERE  descriptive_flexfield_name IN ('GL_JE_LINES', 'FND_FLEX_VALUES')
ORDER BY 1;