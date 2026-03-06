-- 2a. Single structure — row count should match seg_count from kff_list_rc
DECLARE
    rc          SYS_REFCURSOR;
    strCode     VARCHAR2(30);  strName   VARCHAR2(240);
    seqNum      NUMBER;        dbCol     VARCHAR2(30);
    segName     VARCHAR2(240); prompt    VARCHAR2(240);
    req         VARCHAR2(1);   vsetName  VARCHAR2(60);
    valType     VARCHAR2(1);   created   VARCHAR2(20);
    createdBy   VARCHAR2(100);
    rowCnt      INTEGER := 0;
BEGIN
    rc := XXX_FLEX_UTIL.kff_segs_rc(
              kffCode       => 'GL#',
              structureCode => 'XXX_ACCOUNTING_FLEXFIELD'  -- EDIT: your GL# structure code
          );
    DBMS_OUTPUT.PUT_LINE(RPAD('STR_CODE', 30) || ' | ' || RPAD('#', 3) || ' | ' || RPAD('DB_COL', 12) || ' | PROMPT');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
    LOOP
        FETCH rc INTO strCode, strName, seqNum, dbCol, segName, prompt, req, vsetName, valType, created, createdBy;
        EXIT WHEN rc%NOTFOUND;
        rowCnt := rowCnt + 1;
        DBMS_OUTPUT.PUT_LINE(RPAD(NVL(strCode,''), 30) || ' | ' || RPAD(NVL(TO_CHAR(seqNum),''), 3)
            || ' | ' || RPAD(NVL(dbCol,''), 12) || ' | ' || NVL(prompt,''));
    END LOOP;
    CLOSE rc;
    DBMS_OUTPUT.PUT_LINE('Segments for this structure: ' || rowCnt);
END;
/

-- 2c. Sample data — header should show which discriminator column was used
BEGIN
    XXX_FLEX_UTIL.kff_data_out(
        kffCode       => 'GL#',
        structureCode => 'XXX_ACCOUNTING_FLEXFIELD',  -- EDIT: your GL# structure code
        rows          => 10,
        orderBy       => 'N'  -- GL_CODE_COMBINATIONS is large; skip ORDER BY
    );
END;
/

-- 2d. REFERENCE QUERY: check which discriminator columns exist on the KFF base table
SELECT
    i.id_flex_code,
    i.id_flex_name,
    i.application_table_name,
    CASE WHEN EXISTS (SELECT 1 FROM all_tab_columns WHERE table_name = i.application_table_name AND column_name = 'ID_FLEX_NUM')
         THEN 'Y' ELSE 'N' END AS has_id_flex_num,
    CASE WHEN EXISTS (SELECT 1 FROM all_tab_columns WHERE table_name = i.application_table_name AND column_name = 'CHART_OF_ACCOUNTS_ID')
         THEN 'Y' ELSE 'N' END AS has_chart_of_accts_id
FROM   fnd_id_flexs i
ORDER BY i.id_flex_code;