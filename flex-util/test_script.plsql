-- =============================================================================
-- xxx_flex_util  –  Test Script
--
-- Run sections individually in SQL Developer with DBMS_OUTPUT enabled.
-- All EDIT markers indicate values you must replace with ones valid on your
-- instance before running.  Sections are independent; run in any order.
--
-- Sections
--   1  DFF context column resolution
--   2  KFF structure filter
--   3  ORDER BY toggle
--   4  DFF discovery (dff_list_rc / dff_attrs_rc)
--   5  KFF discovery (kff_list_rc / kff_segs_rc)
--   6  Generated SQL output (_sample_sql)
--   7  Sample data output (_data_out)
--   8  Edge cases
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 1 – DFF context column resolution
-- Verifies that dff_data_out picks up the correct context discriminator column
-- rather than always defaulting to ATTRIBUTE_CATEGORY.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1a. GL_JE_LINES uses CONTEXT, not ATTRIBUTE_CATEGORY.
--     Header line should show  Ctx Col: CONTEXT
BEGIN
    xxx_flex_util.dff_data_out(
        dffName     => 'GL_JE_LINES',
        contextCode => 'XXX SYSTEM',
        baseTable   => 'GL_JE_LINES',
        rows        => 10,
        orderBy     => 'N'   -- large table; skip ORDER BY to avoid full scan
    );
END;
/

-- 1b. Confirm the generated SQL also uses the correct context column
DECLARE
    clob_ CLOB;
BEGIN
    clob_ := xxx_flex_util.dff_sample_sql(
                 dffName     => 'GL_JE_LINES',
                 contextCode => 'Purchasing Additions',
                 baseTable   => 'GL_JE_LINES',
                 orderBy     => 'N'
             );
    -- CLOB may exceed a single PUT_LINE; print in 20 K chunks
    FOR i IN 0..TRUNC(DBMS_LOB.GETLENGTH(clob_) / 20000) LOOP
        DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(clob_, 20000, (i * 20000) + 1));
    END LOOP;
END;
/

-- 1c. Standard DFF — should resolve ATTRIBUTE_CATEGORY
--     Header line should show  Ctx Col: ATTRIBUTE_CATEGORY
BEGIN
    xxx_flex_util.dff_data_out(
        dffName     => 'FND_FLEX_VALUES',   -- EDIT to a known DFF on your instance
        contextCode => 'XXX_GL_PCA',
        baseTable   => 'FND_FLEX_VALUES',   -- EDIT
        rows        => 5,
        orderBy     => 'Y'
    );
END;
/

-- 1d. Reference query: check what context_column_name FND metadata holds
--     for any DFF before running the blocks above
SELECT
    descriptive_flexfield_name,
    title,
    application_table_name,
    NVL(context_column_name, '(null — defaults to ATTRIBUTE_CATEGORY)') AS context_column_name
FROM   fnd_descriptive_flexs_vl
WHERE  descriptive_flexfield_name IN ('GL_JE_LINES', 'FND_FLEX_VALUES')
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 2 – KFF structure filter
-- Verifies that kff_segs_rc and kff_data_out correctly isolate one structure
-- and do not bleed rows from other structures.
-- ─────────────────────────────────────────────────────────────────────────────

-- 2a. Single structure — row count should match seg_count from kff_list_rc
DECLARE
    rc          SYS_REFCURSOR;
    strCode     VARCHAR2(30);    strName  VARCHAR2(240);
    seqNum      NUMBER;          dbCol    VARCHAR2(30);
    segName     VARCHAR2(240);   prompt   VARCHAR2(240);
    req         VARCHAR2(1);     vsetName VARCHAR2(60);
    valType     VARCHAR2(1);     created  VARCHAR2(20);
    createdBy   VARCHAR2(100);
    rowCnt      INTEGER := 0;
BEGIN
    rc := xxx_flex_util.kff_segs_rc(
              kffCode       => 'GL#',
              structureCode => 'XXX_ACCOUNTING_FLEXFIELD'
          );
    DBMS_OUTPUT.PUT_LINE(RPAD('STR_CODE', 30) || ' | ' || RPAD('#', 3)
        || ' | ' || RPAD('DB_COL', 12) || ' | PROMPT');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
    LOOP
        FETCH rc INTO strCode, strName, seqNum, dbCol, segName,
                      prompt, req, vsetName, valType, created, createdBy;
        EXIT WHEN rc%NOTFOUND;
        rowCnt := rowCnt + 1;
        DBMS_OUTPUT.PUT_LINE(RPAD(NVL(strCode, ''), 30) || ' | '
            || RPAD(NVL(TO_CHAR(seqNum), ''), 3) || ' | '
            || RPAD(NVL(dbCol, ''), 12) || ' | ' || NVL(prompt, ''));
    END LOOP;
    CLOSE rc;
    DBMS_OUTPUT.PUT_LINE('Segments for this structure: ' || rowCnt);
END;
/

-- 2b. NULL structureCode returns all structures.
--     If the count here equals 2a then only one structure exists for GL#.
DECLARE
    rc          SYS_REFCURSOR;
    strCode     VARCHAR2(30);    strName  VARCHAR2(240);
    seqNum      NUMBER;          dbCol    VARCHAR2(30);
    segName     VARCHAR2(240);   prompt   VARCHAR2(240);
    req         VARCHAR2(1);     vsetName VARCHAR2(60);
    valType     VARCHAR2(1);     created  VARCHAR2(20);
    createdBy   VARCHAR2(100);
    rowCnt      INTEGER := 0;
BEGIN
    rc := xxx_flex_util.kff_segs_rc(
              kffCode       => 'GL#',
              structureCode => NULL
          );
    LOOP
        FETCH rc INTO strCode, strName, seqNum, dbCol, segName,
                      prompt, req, vsetName, valType, created, createdBy;
        EXIT WHEN rc%NOTFOUND;
        rowCnt := rowCnt + 1;
    END LOOP;
    CLOSE rc;
    DBMS_OUTPUT.PUT_LINE('Total segments across ALL structures for GL#: ' || rowCnt);
    DBMS_OUTPUT.PUT_LINE('(Compare to single-structure count in 2a — difference = other structures)');
END;
/

-- 2c. Sample data — header should show which discriminator column was used
BEGIN
    xxx_flex_util.kff_data_out(
        kffCode       => 'GL#',
        structureCode => 'XXX_ACCOUNTING_FLEXFIELD',   -- EDIT
        rows          => 10,
        orderBy       => 'N'   -- GL_CODE_COMBINATIONS is large; skip ORDER BY
    );
END;
/

-- 2d. Reference query: check which discriminator columns exist on the KFF base table
SELECT
    i.id_flex_code,
    i.id_flex_name,
    i.application_table_name,
    CASE WHEN EXISTS (
             SELECT 1 FROM all_tab_columns
             WHERE  table_name  = i.application_table_name
             AND    column_name = 'ID_FLEX_NUM'
         ) THEN 'Y' ELSE 'N' END AS has_id_flex_num,
    CASE WHEN EXISTS (
             SELECT 1 FROM all_tab_columns
             WHERE  table_name  = i.application_table_name
             AND    column_name = 'CHART_OF_ACCOUNTS_ID'
         ) THEN 'Y' ELSE 'N' END AS has_chart_of_accts_id
FROM   fnd_id_flexs i
ORDER BY i.id_flex_code;


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 3 – ORDER BY toggle
-- ─────────────────────────────────────────────────────────────────────────────

-- 3a. orderBy => 'N' — ORDER BY clause must be absent from generated SQL
DECLARE
    clob_ CLOB;
BEGIN
    clob_ := xxx_flex_util.dff_sample_sql(
                 dffName     => 'GL_JE_LINES',
                 contextCode => 'XXX CASHIERS',
                 baseTable   => 'GL_JE_LINES',
                 orderBy     => 'N'
             );
    DBMS_OUTPUT.PUT_LINE('-- ORDER BY N output (no ORDER BY clause expected):');
    DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(clob_, 32000, 1));
END;
/

-- 3b. KFF with orderBy => 'N' — useful for GL_CODE_COMBINATIONS (no index on CREATION_DATE)
BEGIN
    xxx_flex_util.kff_data_out(
        kffCode       => 'GL#',
        structureCode => 'XXX_ACCOUNTING_FLEXFIELD',   -- EDIT
        rows          => 15,
        orderBy       => 'N'
    );
END;
/

-- 3c. orderBy => 'Y' on a table without CREATION_DATE — should be a no-op,
--     not an error (build_select_sql guards with col_exists before appending ORDER BY)
BEGIN
    xxx_flex_util.dff_data_out(
        dffName     => 'FND_FLEX_VALUES',
        contextCode => 'XXX_GL_FUND_SOURCE',
        baseTable   => 'FND_FLEX_VALUES',
        rows        => 10,
        orderBy     => 'Y'
    );
END;
/


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 4 – DFF discovery
-- ─────────────────────────────────────────────────────────────────────────────

-- 4a. All custom DFFs (system noise filtered out)
DECLARE
    rc          SYS_REFCURSOR;
    appId       NUMBER;          dffName     VARCHAR2(240);
    ctxCode     VARCHAR2(150);   ctxName     VARCHAR2(240);
    appName     VARCHAR2(240);   appShort    VARCHAR2(50);
    baseTable   VARCHAR2(240);   dffTitle    VARCHAR2(240);
    attrCount   NUMBER;
    rowCnt      INTEGER := 0;
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    rc := xxx_flex_util.dff_list_rc(
              appShortName => NULL,
              search       => NULL,
              showSystem   => 'N'
          );
    DBMS_OUTPUT.PUT_LINE(RPAD('APP', 12)       || ' | ' || RPAD('DFF_NAME', 40)
        || ' | ' || RPAD('CONTEXT_CODE', 30) || ' | ' || RPAD('BASE_TABLE', 35) || ' | #');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 140, '-'));
    LOOP
        FETCH rc INTO appId, dffName, ctxCode, ctxName, appName, appShort,
                      baseTable, dffTitle, attrCount;
        EXIT WHEN rc%NOTFOUND;
        rowCnt := rowCnt + 1;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(NVL(appShort,  ''), 12) || ' | ' ||
            RPAD(NVL(dffName,   ''), 40) || ' | ' ||
            RPAD(NVL(ctxCode,   ''), 30) || ' | ' ||
            RPAD(NVL(baseTable, ''), 35) || ' | ' ||
            attrCount
        );
        EXIT WHEN rowCnt >= 50;   -- cap output for interactive use
    END LOOP;
    CLOSE rc;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 140, '-'));
    DBMS_OUTPUT.PUT_LINE('Rows shown: ' || rowCnt);
END;
/

-- 4b. DFFs filtered by application short name — edit 'SQLGL' as needed
DECLARE
    rc          SYS_REFCURSOR;
    appId       NUMBER;          dffName   VARCHAR2(240);
    ctxCode     VARCHAR2(150);   ctxName   VARCHAR2(240);
    appName     VARCHAR2(240);   appShort  VARCHAR2(50);
    baseTable   VARCHAR2(240);   dffTitle  VARCHAR2(240);
    attrCount   NUMBER;
    rowCnt      INTEGER := 0;
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    rc := xxx_flex_util.dff_list_rc(appShortName => 'SQLGL');
    LOOP
        FETCH rc INTO appId, dffName, ctxCode, ctxName, appName, appShort,
                      baseTable, dffTitle, attrCount;
        EXIT WHEN rc%NOTFOUND;
        rowCnt := rowCnt + 1;
        DBMS_OUTPUT.PUT_LINE(RPAD(NVL(dffName, ''), 40) || ' | '
            || RPAD(NVL(ctxCode, ''), 30) || ' | ' || attrCount || ' attrs');
    END LOOP;
    CLOSE rc;
    DBMS_OUTPUT.PUT_LINE('Rows: ' || rowCnt);
END;
/

-- 4c. Attribute detail for a single DFF — NULL contextCode returns all contexts
DECLARE
    rc          SYS_REFCURSOR;
    ctxCode     VARCHAR2(150);   ctxType   VARCHAR2(20);
    seqNum      NUMBER;          dbCol     VARCHAR2(30);
    prompt      VARCHAR2(240);   attrName  VARCHAR2(240);
    req         VARCHAR2(1);     defVal    VARCHAR2(240);
    vsetName    VARCHAR2(60);    valType   VARCHAR2(1);
    created     VARCHAR2(20);    createdBy VARCHAR2(100);
    rowCnt      INTEGER := 0;
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    rc := xxx_flex_util.dff_attrs_rc(
              dffName     => 'GL_JE_LINES',   -- EDIT
              contextCode => NULL
          );
    DBMS_OUTPUT.PUT_LINE(RPAD('CTX_TYPE', 10) || ' | ' || RPAD('CTX_CODE', 30)
        || ' | ' || RPAD('#', 4) || ' | ' || RPAD('DB_COL', 20)
        || ' | ' || RPAD('PROMPT', 30) || ' | VSET');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 120, '-'));
    LOOP
        FETCH rc INTO ctxCode, ctxType, seqNum, dbCol, prompt, attrName,
                      req, defVal, vsetName, valType, created, createdBy;
        EXIT WHEN rc%NOTFOUND;
        rowCnt := rowCnt + 1;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(NVL(ctxType, ''), 10)           || ' | ' ||
            RPAD(NVL(ctxCode, ''), 30)           || ' | ' ||
            RPAD(NVL(TO_CHAR(seqNum), ''), 4)   || ' | ' ||
            RPAD(NVL(dbCol, ''), 20)             || ' | ' ||
            RPAD(NVL(prompt, ''), 30)            || ' | ' ||
            NVL(vsetName, '(none)')
        );
    END LOOP;
    CLOSE rc;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 120, '-'));
    DBMS_OUTPUT.PUT_LINE('Rows: ' || rowCnt);
END;
/


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 5 – KFF discovery
-- ─────────────────────────────────────────────────────────────────────────────

-- 5a. All KFFs
DECLARE
    rc          SYS_REFCURSOR;
    appId       NUMBER;          kffCode   VARCHAR2(4);
    kffName     VARCHAR2(240);   strNum    NUMBER;
    strCode     VARCHAR2(30);    strName   VARCHAR2(240);
    appName     VARCHAR2(240);   appShort  VARCHAR2(50);
    baseTable   VARCHAR2(240);   segCount  NUMBER;
    rowCnt      INTEGER := 0;
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    rc := xxx_flex_util.kff_list_rc(
              appShortName => NULL,
              search       => NULL
          );
    DBMS_OUTPUT.PUT_LINE(RPAD('KFF_CODE', 10) || ' | ' || RPAD('KFF_NAME', 35)
        || ' | ' || RPAD('STRUCTURE_CODE', 35) || ' | ' || RPAD('BASE_TABLE', 35) || ' | SEGS');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 130, '-'));
    LOOP
        FETCH rc INTO appId, kffCode, kffName, strNum, strCode, strName,
                      appName, appShort, baseTable, segCount;
        EXIT WHEN rc%NOTFOUND;
        rowCnt := rowCnt + 1;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(NVL(kffCode,   ''), 10) || ' | ' ||
            RPAD(NVL(kffName,   ''), 35) || ' | ' ||
            RPAD(NVL(strCode,   ''), 35) || ' | ' ||
            RPAD(NVL(baseTable, ''), 35) || ' | ' ||
            segCount
        );
        EXIT WHEN rowCnt >= 50;
    END LOOP;
    CLOSE rc;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 130, '-'));
    DBMS_OUTPUT.PUT_LINE('Rows shown: ' || rowCnt);
END;
/

-- 5b. Segment detail for a single structure
DECLARE
    rc          SYS_REFCURSOR;
    strCode     VARCHAR2(30);    strName   VARCHAR2(240);
    seqNum      NUMBER;          dbCol     VARCHAR2(30);
    segName     VARCHAR2(240);   prompt    VARCHAR2(240);
    req         VARCHAR2(1);     vsetName  VARCHAR2(60);
    valType     VARCHAR2(1);     created   VARCHAR2(20);
    createdBy   VARCHAR2(100);
    rowCnt      INTEGER := 0;
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    rc := xxx_flex_util.kff_segs_rc(
              kffCode       => 'GL#',                       -- EDIT
              structureCode => 'XXX_ACCOUNTING_FLEXFIELD'   -- EDIT
          );
    DBMS_OUTPUT.PUT_LINE(RPAD('#', 4) || ' | ' || RPAD('DB_COL', 20)
        || ' | ' || RPAD('PROMPT', 30) || ' | ' || RPAD('VSET', 30) || ' | REQ');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 100, '-'));
    LOOP
        FETCH rc INTO strCode, strName, seqNum, dbCol, segName,
                      prompt, req, vsetName, valType, created, createdBy;
        EXIT WHEN rc%NOTFOUND;
        rowCnt := rowCnt + 1;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(NVL(TO_CHAR(seqNum), ''), 4) || ' | ' ||
            RPAD(NVL(dbCol,  ''), 20)         || ' | ' ||
            RPAD(NVL(prompt, ''), 30)         || ' | ' ||
            RPAD(NVL(vsetName, '(none)'), 30) || ' | ' ||
            NVL(req, 'N')
        );
    END LOOP;
    CLOSE rc;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 100, '-'));
    DBMS_OUTPUT.PUT_LINE('Rows: ' || rowCnt);
END;
/


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 6 – Generated SQL output (_sample_sql)
-- ─────────────────────────────────────────────────────────────────────────────

-- 6a. DFF Global Data Elements
DECLARE
    clob_   CLOB;
    pos_    INTEGER := 1;
    len_    INTEGER;
    chunk_  VARCHAR2(32767);
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    clob_ := xxx_flex_util.dff_sample_sql(
                 dffName     => 'GL_JE_HEADERS',        -- EDIT
                 contextCode => 'Global Data Elements',
                 baseTable   => 'GL_JE_HEADERS'          -- EDIT
             );
    DBMS_OUTPUT.PUT_LINE('--- DFF GENERATED SQL ---');
    len_ := DBMS_LOB.GETLENGTH(clob_);
    WHILE pos_ <= len_ LOOP
        chunk_ := DBMS_LOB.SUBSTR(clob_, 20000, pos_);
        DBMS_OUTPUT.PUT_LINE(chunk_);
        pos_ := pos_ + 20000;
    END LOOP;
END;
/

-- 6b. DFF context-specific
DECLARE
    clob_   CLOB;
    pos_    INTEGER := 1;
    len_    INTEGER;
    chunk_  VARCHAR2(32767);
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    clob_ := xxx_flex_util.dff_sample_sql(
                 dffName     => 'FND_FLEX_VALUES',       -- EDIT
                 contextCode => 'XXX_GL_FUND_SOURCE',    -- EDIT
                 baseTable   => 'FND_FLEX_VALUES'         -- EDIT
             );
    DBMS_OUTPUT.PUT_LINE('--- DFF CONTEXT-SPECIFIC GENERATED SQL ---');
    len_ := DBMS_LOB.GETLENGTH(clob_);
    WHILE pos_ <= len_ LOOP
        chunk_ := DBMS_LOB.SUBSTR(clob_, 20000, pos_);
        DBMS_OUTPUT.PUT_LINE(chunk_);
        pos_ := pos_ + 20000;
    END LOOP;
END;
/

-- 6c. KFF generated SQL
DECLARE
    clob_   CLOB;
    pos_    INTEGER := 1;
    len_    INTEGER;
    chunk_  VARCHAR2(32767);
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    clob_ := xxx_flex_util.kff_sample_sql(
                 kffCode       => 'GL#',                      -- EDIT
                 structureCode => 'XXX_ACCOUNTING_FLEXFIELD'  -- EDIT
             );
    DBMS_OUTPUT.PUT_LINE('--- KFF GENERATED SQL ---');
    len_ := DBMS_LOB.GETLENGTH(clob_);
    WHILE pos_ <= len_ LOOP
        chunk_ := DBMS_LOB.SUBSTR(clob_, 20000, pos_);
        DBMS_OUTPUT.PUT_LINE(chunk_);
        pos_ := pos_ + 20000;
    END LOOP;
END;
/


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 7 – Sample data output (_data_out)
-- ─────────────────────────────────────────────────────────────────────────────

-- 7a. DFF Global Data Elements
BEGIN
    xxx_flex_util.dff_data_out(
        dffName     => 'GL_JE_HEADERS',
        contextCode => 'XXX SYSTEM',
        baseTable   => 'GL_JE_HEADERS',
        rows        => 20
    );
END;
/

-- 7b. DFF context-specific — exercises [G]/[C] deduplication and WHERE = contextCode path
BEGIN
    xxx_flex_util.dff_data_out(
        dffName     => 'FND_FLEX_VALUES',
        contextCode => 'XXX_GL_FUND_SOURCE',
        baseTable   => 'FND_FLEX_VALUES',
        rows        => 15
    );
END;
/

-- 7c. KFF sample data
BEGIN
    xxx_flex_util.kff_data_out(
        kffCode       => 'GL#',
        structureCode => 'XXX_ACCOUNTING_FLEXFIELD',   -- EDIT
        rows          => 20
    );
END;
/

-- 7d. Second KFF structure — compare against 7c to confirm no row mixing between structures
BEGIN
    xxx_flex_util.kff_data_out(
        kffCode       => 'GLLE',                      -- EDIT
        structureCode => 'XXX_ACCOUNTING_FLEXFIELD',  -- EDIT
        rows          => 10
    );
END;
/


-- ─────────────────────────────────────────────────────────────────────────────
-- SECTION 8 – Edge cases
-- ─────────────────────────────────────────────────────────────────────────────

-- 8a. SQL injection attempt — should return a comment, not raise an exception
DECLARE
    clob_ CLOB;
BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    clob_ := xxx_flex_util.dff_sample_sql(
                 dffName     => 'GL_JE_HEADERS',
                 contextCode => 'Global Data Elements',
                 baseTable   => 'GL_JE_HEADERS; DROP TABLE T--'
             );
    DBMS_OUTPUT.PUT_LINE(clob_);
END;
/

-- 8b. Unknown context code — should print informational message, not raise exception
BEGIN
    xxx_flex_util.dff_data_out(
        dffName     => 'GL_JE_HEADERS',
        contextCode => 'CONTEXT_THAT_DOES_NOT_EXIST',
        baseTable   => 'GL_JE_HEADERS',
        rows        => 5
    );
END;
/

-- 8c. Unknown KFF code — should print ERROR: KFF code not found, not raise exception
BEGIN
    xxx_flex_util.kff_data_out(
        kffCode       => 'ZZZZ',
        structureCode => 'ANYTHING',
        rows          => 5
    );
END;
/