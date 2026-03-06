SET DEFINE OFF;

CREATE OR REPLACE PACKAGE BODY XXX_FLEX_UTIL AS
-- =============================================================================
-- XXX_FLEX_UTIL  –  Package Body
--
-- Private helpers:
--   colExists         – single-column existence check against ALL_TAB_COLUMNS
--   escapeHTML        – escapes < > & for Markdown/HTML output
--   buildSelectSQL    – assembles the SELECT/FROM/WHERE/ORDER BY CLOB
--   buildSegsDFF      – populates t_seg_tab from FND DFF metadata
--   buildSegsKFF      – populates t_seg_tab from FND KFF metadata
--   getContextColDFF  – resolves the context discriminator column name
--   buildWhereDFF     – builds the WHERE clause for a DFF context filter
--   buildLabelArray   – merges segment labels with optional audit columns
--   executeHTML       – executes SQL via DBMS_SQL, returns Markdown table CLOB
--   executeOutput     – executes SQL via DBMS_SQL, prints via DBMS_OUTPUT
-- =============================================================================

    -- =========================================================================
    -- PRIVATE HELPERS
    -- =========================================================================

    -- Returns TRUE when columnName exists on tableName in ALL_TAB_COLUMNS.
    -- Used before appending optional audit columns and building WHERE clauses.
    FUNCTION colExists(
        tableName  IN VARCHAR2,
        columnName IN VARCHAR2
    ) RETURN BOOLEAN IS
        cnt PLS_INTEGER;
    BEGIN
        SELECT COUNT(*) INTO cnt
        FROM   all_tab_columns
        WHERE  table_name  = tableName
        AND    column_name = columnName;
        RETURN cnt > 0;
    END colExists;

    -- Escapes characters that would break a Markdown or HTML table cell.
    FUNCTION escapeHTML(str IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN REPLACE(REPLACE(REPLACE(str, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
    END escapeHTML;

    -- Assembles a SELECT statement from a pre-built segment array.
    -- addComments = TRUE emits column-name annotations
    -- used by the public sample and data functions so callers can see which attribute maps to which DB column.
    FUNCTION buildSelectSQL(
        segs        IN  t_seg_tab,
        segCount    IN  PLS_INTEGER,
        baseTable   IN  VARCHAR2,
        whereClause IN  VARCHAR2  DEFAULT NULL,
        maxRows     IN  NUMBER    DEFAULT 25,
        addComments IN  BOOLEAN   DEFAULT FALSE,
        orderBy     IN  VARCHAR2  DEFAULT 'Y'
    ) RETURN CLOB IS
        qry    CLOB;
        hasCdt BOOLEAN := colExists(baseTable, 'CREATION_DATE');
        hasCby BOOLEAN := colExists(baseTable, 'CREATED_BY');
        hasUpd BOOLEAN := colExists(baseTable, 'LAST_UPDATE_DATE');
    BEGIN
        qry := 'SELECT' || CHR(10);

        FOR i IN 1..segCount LOOP
            qry := qry || '    ' || segs(i).col_name;
            IF addComments THEN
                qry := qry || '  -- ' || segs(i).label;
            END IF;
            qry := qry || ',' || CHR(10);
        END LOOP;
    
        IF hasCdt THEN
            qry := qry || '    TO_CHAR(CREATION_DATE,  ''YYYY-MM-DD HH24:MI'')';
            IF addComments THEN qry := qry || '  -- Creation Date'; END IF;
            qry := qry || ',' || CHR(10);
        END IF;
        IF hasCby THEN
            qry := qry || '    TO_CHAR(CREATED_BY)';
            IF addComments THEN qry := qry || '  -- Created By'; END IF;
            qry := qry || ',' || CHR(10);
        END IF;
        IF hasUpd THEN
            qry := qry || '    TO_CHAR(LAST_UPDATE_DATE, ''YYYY-MM-DD HH24:MI'')';
            IF addComments THEN qry := qry || '  -- Last Updated'; END IF;
            qry := qry || CHR(10);
        ELSE
            -- strip trailing comma left by the last appended column
            qry := RTRIM(qry, ',' || CHR(10)) || CHR(10);
        END IF;

        qry := qry || 'FROM  ' || baseTable || CHR(10);

        IF whereClause IS NOT NULL THEN
            qry := qry || 'WHERE ' || whereClause || CHR(10);
        END IF;

        IF UPPER(orderBy) = 'Y' AND hasCdt THEN
            qry := qry || 'ORDER BY CREATION_DATE DESC' || CHR(10);
        END IF;

        qry := qry || 'FETCH FIRST ' || maxRows || ' ROWS ONLY';

        RETURN qry;
    END buildSelectSQL;

    -- Populates segs with the enabled DFF attributes for a context.
    -- Global Data Elements are always included
    -- Context specific attributes are tagged [C] to distinguish them in the generated SQL header.
    -- Deduplicates when a column appears in both Global and Context rows.
    PROCEDURE buildSegsDFF(
        dffName     IN  VARCHAR2,
        contextCode IN  VARCHAR2,
        baseTable   IN  VARCHAR2,
        segs        OUT t_seg_tab,
        segCount    OUT PLS_INTEGER
    ) IS
        CURSOR cGlobal IS
            SELECT dfcu.application_column_name  AS col_name,
                   '[G] ' || NVL(dfcu_t.form_left_prompt, dfcu.end_user_column_name) AS label
            FROM   fnd_descr_flex_column_usages    dfcu
            LEFT JOIN fnd_descr_flex_col_usage_tl  dfcu_t
                   ON  dfcu.application_id              = dfcu_t.application_id
                   AND dfcu.descriptive_flexfield_name  = dfcu_t.descriptive_flexfield_name
                   AND dfcu.descriptive_flex_context_code = dfcu_t.descriptive_flex_context_code
                   AND dfcu.application_column_name     = dfcu_t.application_column_name
                   AND dfcu_t.language                  = USERENV('LANG')
            WHERE  dfcu.descriptive_flexfield_name      = dffName
            AND    dfcu.descriptive_flex_context_code   = 'Global Data Elements'
            AND    dfcu.enabled_flag                    = 'Y'
            ORDER BY dfcu.column_seq_num;

        CURSOR cContext IS
            SELECT dfcu.application_column_name  AS col_name,
                   '[C] ' || NVL(dfcu_t.form_left_prompt, dfcu.end_user_column_name) AS label
            FROM   fnd_descr_flex_column_usages    dfcu
            LEFT JOIN fnd_descr_flex_col_usage_tl  dfcu_t
                   ON  dfcu.application_id              = dfcu_t.application_id
                   AND dfcu.descriptive_flexfield_name  = dfcu_t.descriptive_flexfield_name
                   AND dfcu.descriptive_flex_context_code = dfcu_t.descriptive_flex_context_code
                   AND dfcu.application_column_name     = dfcu_t.application_column_name
                   AND dfcu_t.language                  = USERENV('LANG')
            WHERE  dfcu.descriptive_flexfield_name      = dffName
            AND    dfcu.descriptive_flex_context_code   = contextCode
            AND    dfcu.enabled_flag                    = 'Y'
            ORDER BY dfcu.column_seq_num;

        pos     PLS_INTEGER := 0;
        seen    t_seg_tab;  -- tracks col names already added (reuse type, only col_name matters)
        seenCnt PLS_INTEGER := 0;
        isDupe  BOOLEAN;
    BEGIN
        -- Global Data Elements first
        FOR r IN cGlobal LOOP
            IF colExists(baseTable, r.col_name) THEN 
                pos := pos + 1;
                segs(pos).col_name := r.col_name;
                segs(pos).label    := r.label;
                seenCnt := seenCnt + 1;
                seen(seenCnt).col_name := r.col_name;
            END IF;
        END LOOP;

        -- Context-specific; skip any column already covered by Global
        FOR r IN cContext LOOP
            isDupe := FALSE;
            FOR s IN 1..seenCnt LOOP
                IF seen(s).col_name = r.col_name THEN isDupe := TRUE; EXIT; END IF;
            END LOOP;
            IF NOT isDupe AND colExists(baseTable, r.col_name) THEN
                pos := pos + 1;
                segs(pos).col_name := r.col_name;
                segs(pos).label    := r.label;
            END IF;
        END LOOP;

        segCount := pos;
    END buildSegsDFF;

    -- Populates segs with the enabled KFF segments for a structure.
    -- Also resolves the base combination table and id_flex_num so the caller 
    --  can build the correct structure-discriminator WHERE clause.
    PROCEDURE buildSegsKFF(
        kffCode       IN  VARCHAR2,
        structureCode IN  VARCHAR2,
        segs          OUT t_seg_tab,
        segCount      OUT PLS_INTEGER,
        baseTable     OUT VARCHAR2,
        flexNum       OUT NUMBER
    ) IS
        CURSOR cMeta IS
            SELECT idfs.application_table_name,
                   str.id_flex_num
            FROM   fnd_id_flexs           idfs
            JOIN   fnd_id_flex_structures_vl str
                   ON  idfs.application_id  = str.application_id
                   AND idfs.id_flex_code    = str.id_flex_code
            WHERE  idfs.id_flex_code             = kffCode
            AND    str.id_flex_structure_code     = structureCode
            AND    ROWNUM                         = 1;

        CURSOR cSegs IS
            SELECT seg.application_column_name                          AS col_name,
                   NVL(seg.form_left_prompt, seg.segment_name)          AS label
            FROM   fnd_id_flex_segments_vl   seg
            JOIN   fnd_id_flex_structures_vl str
                   ON  seg.application_id  = str.application_id
                   AND seg.id_flex_code    = str.id_flex_code
                   AND seg.id_flex_num     = str.id_flex_num
            WHERE  seg.id_flex_code              = kffCode
            AND    str.id_flex_structure_code     = structureCode
            AND    seg.enabled_flag               = 'Y'
            ORDER BY seg.segment_num;

        pos PLS_INTEGER := 0;
    BEGIN
        baseTable := NULL;
        flexNum   := NULL;

        OPEN cMeta;
        FETCH cMeta INTO baseTable, flexNum;
        CLOSE cMeta;

        IF baseTable IS NULL THEN
            segCount := 0;
            RETURN;
        END IF;

        FOR r IN cSegs LOOP
            pos := pos + 1;
            segs(pos).col_name := r.col_name;
            segs(pos).label    := r.label;
        END LOOP;

        segCount := pos;
    END buildSegsKFF;

    -- Returns the context column for a DFF.
    -- Most DFFs use ATTRIBUTE_CATEGORY, but some (e.g. GL_JE_LINES) 
    --  define a different column in FND_DESCRIPTIVE_FLEXS_VL.CONTEXT_COLUMN_NAME.
    FUNCTION getContextColDFF(
        dffName   IN VARCHAR2,
        baseTable IN VARCHAR2
    ) RETURN VARCHAR2 IS
        ctxCol VARCHAR2(30);
    BEGIN
        SELECT NVL(context_column_name, 'ATTRIBUTE_CATEGORY')
        INTO   ctxCol
        FROM   fnd_descriptive_flexs_vl
        WHERE  descriptive_flexfield_name = dffName
        AND    ROWNUM = 1;

        IF NOT colExists(baseTable, ctxCol) THEN
            RETURN NULL;
        END IF;
        RETURN ctxCol;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END getContextColDFF;

    -- Builds the WHERE clause that filters rows to the requested DFF context.
    -- Returns NULL when no context column exists on the table,
    --  meaning all rows will be returned without a context filter.
    FUNCTION buildWhereDFF(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2,
        baseTable   IN VARCHAR2
    ) RETURN VARCHAR2 IS
        ctxCol VARCHAR2(30);
    BEGIN
        ctxCol := getContextColDFF(dffName, baseTable);
        IF ctxCol IS NULL THEN
            RETURN NULL;
        END IF;
        RETURN ctxCol || ' = ''' || contextCode || '''';
    END buildWhereDFF;

    -- Executes qrsqly via DBMS_SQL and returns an HTML table CLOB.
    --
    -- Output targets APEX 24.2 Dynamic Content regions. 
    -- The u-Report CSS class hooks into APEX's built-in report theme; 
    --  inline styles are kept as a fallback so the table renders correctly outside a full APEX theme context.
    --
    -- colLabels must match the SELECT column count exactly — both are derived from build_label_array
    --  to keep DBMS_SQL DEFINE_COLUMN in sync with the actual SELECT list.  
    --  A mismatch causes ORA-01007 at runtime.
    FUNCTION executeHTML(
        qry       IN CLOB,
        colLabels IN t_seg_tab,
        colCount  IN PLS_INTEGER
    ) RETURN CLOB IS
        cur  INTEGER;
        rc   INTEGER;
        val  VARCHAR2(4000);
        buf  CLOB := '';
        rows INTEGER := 0;
    BEGIN
        buf := '<table class="u-Report" style="border-collapse:collapse;width:100%;font-size:0.85em">'
            || CHR(10) || '<thead><tr>';
        FOR i IN 1..colCount LOOP
            buf := buf
                || '<th style="border:1px solid #ccc;padding:4px 8px;background:#f5f5f5;white-space:nowrap">'
                || escapeHTML(colLabels(i).label)
                || '</th>';
        END LOOP;
        buf := buf || '</tr></thead>' || CHR(10) || '<tbody>';

        cur := DBMS_SQL.OPEN_CURSOR;
        DBMS_SQL.PARSE(cur, qry, DBMS_SQL.NATIVE);
        FOR i IN 1..colCount LOOP
            DBMS_SQL.DEFINE_COLUMN(cur, i, val, 4000);
        END LOOP;
        rc := DBMS_SQL.EXECUTE(cur);

        WHILE DBMS_SQL.FETCH_ROWS(cur) > 0 LOOP
            rows := rows + 1;
            buf  := buf || CHR(10) || '<tr>';
            FOR i IN 1..colCount LOOP
                DBMS_SQL.COLUMN_VALUE(cur, i, val);
                buf := buf
                    || '<td style="border:1px solid #ddd;padding:3px 7px;vertical-align:top">'
                    || CASE WHEN val IS NULL
                            THEN '<span style="color:#aaa">(null)</span>'
                            ELSE escapeHTML(SUBSTR(val, 1, 200))
                       END
                    || '</td>';
            END LOOP;
            buf := buf || '</tr>';
        END LOOP;

        DBMS_SQL.CLOSE_CURSOR(cur);

        IF rows = 0 THEN
            buf := buf || '<tr><td colspan="' || colCount
                       || '" style="padding:8px;color:#888;font-style:italic">No rows found.</td></tr>';
        END IF;

        buf := buf || CHR(10) || '</tbody></table>';
        RETURN buf;

    EXCEPTION
        WHEN OTHERS THEN
            IF DBMS_SQL.IS_OPEN(cur) THEN DBMS_SQL.CLOSE_CURSOR(cur); END IF;
            RETURN '<p style="color:red"><b>Error:</b> ' || escapeHTML(SQLERRM) || '</p>';
    END executeHTML;


    -- Executes sql via DBMS_SQL and prints fixed-width rows via DBMS_OUTPUT.
    -- headerCtx, when supplied, is printed as a banner before the column headers.
    PROCEDURE executeOutput(
        qry       IN CLOB,
        colLabels IN t_seg_tab,
        colCount  IN PLS_INTEGER,
        headerCtx IN VARCHAR2 DEFAULT NULL
    ) IS
        cur   INTEGER;
        rc    INTEGER;
        val   VARCHAR2(4000);
        line  VARCHAR2(32767);
        hdr   VARCHAR2(32767) := '';
        rows  INTEGER := 0;
    BEGIN
        IF headerCtx IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE(RPAD('=', 80, '='));
            DBMS_OUTPUT.PUT_LINE(headerCtx);
            DBMS_OUTPUT.PUT_LINE(RPAD('=', 80, '='));
        END IF;

        FOR i IN 1..colCount LOOP
            hdr := hdr || RPAD(SUBSTR(colLabels(i).label, 1, 27), 29) || ' | ';
        END LOOP;
        DBMS_OUTPUT.PUT_LINE(hdr);
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));

        cur := DBMS_SQL.OPEN_CURSOR;
        DBMS_SQL.PARSE(cur, qry, DBMS_SQL.NATIVE);
        FOR i IN 1..colCount LOOP
            DBMS_SQL.DEFINE_COLUMN(cur, i, val, 4000);
        END LOOP;
        rc := DBMS_SQL.EXECUTE(cur);

        WHILE DBMS_SQL.FETCH_ROWS(cur) > 0 LOOP
            rows := rows + 1;
            line := '';
            FOR i IN 1..colCount LOOP
                DBMS_SQL.COLUMN_VALUE(cur, i, val);
                line := line || RPAD(NVL(SUBSTR(val, 1, 27), '(null)'), 29) || ' | ';
            END LOOP;
            DBMS_OUTPUT.PUT_LINE(line);
        END LOOP;

        DBMS_SQL.CLOSE_CURSOR(cur);
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
        DBMS_OUTPUT.PUT_LINE('Rows: ' || rows);
    EXCEPTION
        WHEN OTHERS THEN
            IF DBMS_SQL.IS_OPEN(cur) THEN DBMS_SQL.CLOSE_CURSOR(cur); END IF;
            DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    END executeOutput;

    -- Merges segment labels with any audit columns (CREATION_DATE, CREATED_BY,
    --  LAST_UPDATE_DATE) that actually exist on the base table.
    PROCEDURE buildLabelArray(
        segs      IN  t_seg_tab,
        segCount  IN  PLS_INTEGER,
        baseTable IN  VARCHAR2,
        labels    OUT t_seg_tab,
        total     OUT PLS_INTEGER
    ) IS
        pos PLS_INTEGER := segCount;
    BEGIN
        FOR i IN 1..segCount LOOP
            labels(i) := segs(i);
        END LOOP;

        IF colExists(baseTable, 'CREATION_DATE') THEN
            pos := pos + 1;
            labels(pos).col_name := 'CREATION_DATE';
            labels(pos).label    := 'Creation Date';
        END IF;
        IF colExists(baseTable, 'CREATED_BY') THEN
            pos := pos + 1;
            labels(pos).col_name := 'CREATED_BY';
            labels(pos).label    := 'Created By';
        END IF;
        IF colExists(baseTable, 'LAST_UPDATE_DATE') THEN
            pos := pos + 1;
            labels(pos).col_name := 'LAST_UPDATE_DATE';
            labels(pos).label    := 'Last Updated';
        END IF;

        total := pos;
    END buildLabelArray;

    -- =========================================================================
    -- PUBLIC: DFF
    -- =========================================================================

    FUNCTION DFF_LIST_RC(
        appShortName IN VARCHAR2 DEFAULT NULL,
        search       IN VARCHAR2 DEFAULT NULL,
        showSystem   IN VARCHAR2 DEFAULT 'N'
    ) RETURN SYS_REFCURSOR IS
        rc SYS_REFCURSOR;
    BEGIN
        OPEN rc FOR
            SELECT
                dff.application_id,
                dff.descriptive_flexfield_name                                AS dff_name,
                dfcc.descriptive_flex_context_code                            AS context_code,
                NVL(dfcc.descriptive_flex_context_name, 'Global Data Elements') AS context_name,
                app_t.application_name                                        AS app_name,
                app.application_short_name                                    AS app_short_name,
                dff.application_table_name                                    AS base_table,
                dff.title                                                     AS dff_title,
                COUNT(dfcu.application_column_name)                           AS attr_count
            FROM   fnd_descriptive_flexs_vl      dff
            JOIN   fnd_descr_flex_contexts_vl    dfcc
                   ON  dff.application_id             = dfcc.application_id
                   AND dff.descriptive_flexfield_name = dfcc.descriptive_flexfield_name
            JOIN   fnd_descr_flex_column_usages  dfcu
                   ON  dfcc.application_id                  = dfcu.application_id
                   AND dfcc.descriptive_flexfield_name      = dfcu.descriptive_flexfield_name
                   AND dfcc.descriptive_flex_context_code   = dfcu.descriptive_flex_context_code
            JOIN   fnd_application_tl            app_t
                   ON  dff.application_id    = app_t.application_id
                   AND app_t.language        = USERENV('LANG')
            JOIN   fnd_application             app
                   ON  app_t.application_id  = app.application_id
            WHERE  dfcu.enabled_flag  = 'Y'
            AND    dfcc.enabled_flag  = 'Y'
            AND    dff.descriptive_flexfield_name NOT LIKE '$SRS$%'
            AND    (appShortName IS NULL OR app.application_short_name = appShortName)
            AND    (search IS NULL
                    OR UPPER(dff.descriptive_flexfield_name) LIKE '%' || UPPER(search) || '%'
                    OR UPPER(dff.title)                      LIKE '%' || UPPER(search) || '%')
            -- Exclude rows created by standard Oracle install accounts unless caller opts in
            AND    (showSystem = 'Y'
                    OR NVL(dfcu.created_by, -1) NOT IN (
                        SELECT user_id FROM fnd_user
                        WHERE  user_name IN ('AUTOINSTALL','INITIAL SETUP','SYSADMIN','ANONYMOUS')
                        OR     user_name LIKE '%ORACLE%'
                    ))
            GROUP BY
                dff.application_id,
                dff.descriptive_flexfield_name,
                dfcc.descriptive_flex_context_code,
                NVL(dfcc.descriptive_flex_context_name, 'Global Data Elements'),
                app_t.application_name,
                app.application_short_name,
                dff.application_table_name,
                dff.title
            ORDER BY
                app_t.application_name,
                dff.descriptive_flexfield_name,
                dfcc.descriptive_flex_context_code;
        RETURN rc;
    END DFF_LIST_RC;

    FUNCTION DFF_ATTRS_RC(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2 DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        rc SYS_REFCURSOR;
    BEGIN
        OPEN rc FOR
            SELECT
                dfcu.descriptive_flex_context_code                            AS context_code,
                CASE WHEN dfcu.descriptive_flex_context_code = 'Global Data Elements'
                     THEN 'Global' ELSE 'Context' END                        AS context_type,
                dfcu.column_seq_num                                           AS seq_num,
                dfcu.application_column_name                                  AS db_column,
                NVL(dfcu_t.form_left_prompt, dfcu.end_user_column_name)       AS prompt,
                dfcu.end_user_column_name                                     AS attribute_name,
                dfcu.required_flag,
                NVL(dfcu.default_value, ' ')                                 AS default_val,
                vs.flex_value_set_name,
                vs.validation_type,
                TO_CHAR(dfcu.creation_date, 'YYYY-MM-DD')                    AS created,
                usr.user_name                                                 AS created_by
            FROM   fnd_descr_flex_column_usages    dfcu
            LEFT JOIN fnd_descr_flex_col_usage_tl  dfcu_t
                   ON  dfcu.application_id              = dfcu_t.application_id
                   AND dfcu.descriptive_flexfield_name  = dfcu_t.descriptive_flexfield_name
                   AND dfcu.descriptive_flex_context_code = dfcu_t.descriptive_flex_context_code
                   AND dfcu.application_column_name     = dfcu_t.application_column_name
                   AND dfcu_t.language                  = USERENV('LANG')
            LEFT JOIN fnd_flex_value_sets vs
                   ON  dfcu.flex_value_set_id = vs.flex_value_set_id
            LEFT JOIN fnd_user usr
                   ON  usr.user_id = dfcu.created_by
            WHERE  dfcu.descriptive_flexfield_name = dffName
            AND    dfcu.enabled_flag               = 'Y'
            AND    (contextCode IS NULL
                    OR dfcu.descriptive_flex_context_code = contextCode)
            ORDER BY
                CASE WHEN dfcu.descriptive_flex_context_code = 'Global Data Elements' THEN 0 ELSE 1 END,
                dfcu.descriptive_flex_context_code,
                dfcu.column_seq_num;
        RETURN rc;
    END DFF_ATTRS_RC;

    FUNCTION DFF_SAMPLE_SQL(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2,
        baseTable   IN VARCHAR2,
        orderBy     IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB IS
        segs    t_seg_tab;
        cnt     PLS_INTEGER;
        where_  VARCHAR2(500);
        ctxCol  VARCHAR2(30);
    BEGIN
        IF NOT REGEXP_LIKE(baseTable, '^[A-Z][A-Z0-9_#$]*$') THEN
            RETURN '-- ERROR: Invalid table name: ' || baseTable;
        END IF;

        buildSegsDFF(dffName, contextCode, baseTable, segs, cnt);

        IF cnt = 0 THEN
            RETURN '-- No enabled attributes found for DFF [' || dffName
                || '] context [' || contextCode || '] on table [' || baseTable || ']';
        END IF;

        ctxCol := getContextColDFF(dffName, baseTable);
        where_ := buildWhereDFF(dffName, contextCode, baseTable);

        RETURN '-- Generated by XXX_FLEX_UTIL.DFF_SAMPLE_SQL' || CHR(10)
            || '-- DFF     : ' || dffName     || CHR(10)
            || '-- Context : ' || contextCode || CHR(10)
            || '-- Ctx Col : ' || NVL(ctxCol, '(none — no context discriminator on this table)') || CHR(10)
            || '-- [G]=Global Data Elements  [C]=Context-specific' || CHR(10)
            || '-- ORDER BY: ' || CASE UPPER(orderBy) WHEN 'Y' THEN 'ON (CREATION_DATE DESC)' ELSE 'OFF' END || CHR(10)
            || buildSelectSQL(segs, cnt, baseTable, where_, 25, TRUE, orderBy);
    END DFF_SAMPLE_SQL;

    FUNCTION DFF_SAMPLE_HTML(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2,
        baseTable   IN VARCHAR2,
        rows        IN NUMBER   DEFAULT 25,
        orderBy     IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB IS
        segs     t_seg_tab;
        segCnt   PLS_INTEGER;
        labels   t_seg_tab;
        total    PLS_INTEGER;
        where_   VARCHAR2(500);
        execSql  CLOB;
    BEGIN
        IF NOT REGEXP_LIKE(baseTable, '^[A-Z][A-Z0-9_#$]*$') THEN
            RETURN '**Error:** Invalid table name: ' || escapeHTML(baseTable) || CHR(10);
        END IF;

        buildSegsDFF(dffName, contextCode, baseTable, segs, segCnt);

        IF segCnt = 0 THEN
            RETURN CHR(10) || 'No enabled attributes found for DFF [' || escapeHTML(dffName)
                || '] context [' || escapeHTML(contextCode) || ']' || CHR(10);
        END IF;

        buildLabelArray(segs, segCnt, baseTable, labels, total);
        where_  := buildWhereDFF(dffName, contextCode, baseTable);
        execSql := buildSelectSQL(segs, segCnt, baseTable, where_, rows, FALSE, orderBy);
        RETURN executeHTML(execSql, labels, total);
    END DFF_SAMPLE_HTML;

    PROCEDURE DFF_DATA_OUT(
        dffName     IN VARCHAR2,
        contextCode IN VARCHAR2,
        baseTable   IN VARCHAR2,
        rows        IN NUMBER   DEFAULT 25,
        orderBy     IN VARCHAR2 DEFAULT 'Y'
    ) IS
        segs    t_seg_tab;
        segCnt  PLS_INTEGER;
        labels  t_seg_tab;
        total   PLS_INTEGER;
        where_  VARCHAR2(500);
        ctxCol  VARCHAR2(30);
        execSql CLOB;
    BEGIN
        DBMS_OUTPUT.ENABLE(1000000);

        IF NOT REGEXP_LIKE(baseTable, '^[A-Z][A-Z0-9_#$]*$') THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: Invalid table name: ' || baseTable);
            RETURN;
        END IF;

        buildSegsDFF(dffName, contextCode, baseTable, segs, segCnt);

        IF segCnt = 0 THEN
            DBMS_OUTPUT.PUT_LINE('No enabled attributes found for DFF [' || dffName
                || '] context [' || contextCode || ']');
            RETURN;
        END IF;

        ctxCol  := getContextColDFF(dffName, baseTable);
        where_  := buildWhereDFF(dffName, contextCode, baseTable);
        buildLabelArray(segs, segCnt, baseTable, labels, total);
        execSql := buildSelectSQL(segs, segCnt, baseTable, where_, rows, FALSE, orderBy);

        executeOutput(
            execSql, labels, total,
            'DFF: '     || dffName     || '  Context: ' || contextCode
            || '  Ctx Col: ' || NVL(ctxCol, '(none)')
            || '  Table: '   || baseTable
            || '  ORDER BY: ' || CASE UPPER(orderBy) WHEN 'Y' THEN 'ON' ELSE 'OFF' END
        );
    END DFF_DATA_OUT;

    -- =========================================================================
    -- PUBLIC: KFF
    -- =========================================================================

    FUNCTION KFF_LIST_RC(
        appShortName IN VARCHAR2 DEFAULT NULL,
        search       IN VARCHAR2 DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        rc SYS_REFCURSOR;
    BEGIN
        OPEN rc FOR
            SELECT
                idfs.application_id,
                idfs.id_flex_code                 AS kff_code,
                idfs.id_flex_name                 AS kff_name,
                str.id_flex_num                   AS structure_num,
                str.id_flex_structure_code        AS structure_code,
                str.id_flex_structure_name        AS structure_name,
                app_t.application_name            AS app_name,
                app.application_short_name        AS app_short_name,
                idfs.application_table_name       AS base_table,
                COUNT(seg.application_column_name) AS seg_count
            FROM   fnd_id_flexs             idfs
            JOIN   fnd_id_flex_segments_vl  seg
                   ON  idfs.application_id = seg.application_id
                   AND idfs.id_flex_code   = seg.id_flex_code
            JOIN   fnd_id_flex_structures_vl str
                   ON  seg.application_id = str.application_id
                   AND seg.id_flex_code   = str.id_flex_code
                   AND seg.id_flex_num    = str.id_flex_num
            JOIN   fnd_application_tl       app_t
                   ON  idfs.application_id = app_t.application_id
                   AND app_t.language      = USERENV('LANG')
            JOIN   fnd_application          app
                   ON  app_t.application_id = app.application_id
            WHERE  seg.enabled_flag = 'Y'
            AND    (appShortName IS NULL OR app.application_short_name = appShortName)
            AND    (search IS NULL
                    OR UPPER(idfs.id_flex_code) LIKE '%' || UPPER(search) || '%'
                    OR UPPER(idfs.id_flex_name) LIKE '%' || UPPER(search) || '%')
            GROUP BY
                idfs.application_id, idfs.id_flex_code, idfs.id_flex_name,
                str.id_flex_num, str.id_flex_structure_code, str.id_flex_structure_name,
                app_t.application_name, app.application_short_name, idfs.application_table_name
            ORDER BY
                app_t.application_name, idfs.id_flex_name, str.id_flex_structure_name;
        RETURN rc;
    END KFF_LIST_RC;

    FUNCTION KFF_SEGS_RC(
        kffCode       IN VARCHAR2,
        structureCode IN VARCHAR2 DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        rc SYS_REFCURSOR;
    BEGIN
        OPEN rc FOR
            SELECT
                str.id_flex_structure_code                           AS structure_code,
                str.id_flex_structure_name                           AS structure_name,
                seg.segment_num                                      AS seq_num,
                seg.application_column_name                          AS db_column,
                seg.segment_name,
                NVL(seg.form_left_prompt, seg.segment_name)          AS prompt,
                seg.required_flag,
                vs.flex_value_set_name,
                vs.validation_type,
                TO_CHAR(seg.creation_date, 'YYYY-MM-DD')            AS created,
                usr.user_name                                        AS created_by
            FROM   fnd_id_flex_segments_vl   seg
            JOIN   fnd_id_flex_structures_vl str
                   ON  seg.application_id = str.application_id
                   AND seg.id_flex_code   = str.id_flex_code
                   AND seg.id_flex_num    = str.id_flex_num
            LEFT JOIN fnd_flex_value_sets vs
                   ON  seg.flex_value_set_id = vs.flex_value_set_id
            LEFT JOIN fnd_user usr
                   ON  usr.user_id = seg.created_by
            WHERE  seg.id_flex_code  = kffCode
            AND    seg.enabled_flag  = 'Y'
            -- NULL structureCode returns all structures (useful for full KFF audit)
            AND    (structureCode IS NULL OR str.id_flex_structure_code = structureCode)
            ORDER BY str.id_flex_structure_code, seg.segment_num;
        RETURN rc;
    END KFF_SEGS_RC;

    FUNCTION KFF_SAMPLE_SQL(
        kffCode       IN VARCHAR2,
        structureCode IN VARCHAR2,
        orderBy       IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB IS
        segs     t_seg_tab;
        cnt      PLS_INTEGER;
        baseTbl  VARCHAR2(240);
        flexNum  NUMBER;
        where_   VARCHAR2(200);
        note     VARCHAR2(500) := '';
    BEGIN
        buildSegsKFF(kffCode, structureCode, segs, cnt, baseTbl, flexNum);

        IF baseTbl IS NULL THEN
            RETURN '-- ERROR: KFF code not found: ' || kffCode;
        END IF;
        IF cnt = 0 THEN
            RETURN '-- No enabled segments found for KFF [' || kffCode
                || '] structure [' || structureCode || ']';
        END IF;

        IF flexNum IS NOT NULL THEN
            IF colExists(baseTbl, 'ID_FLEX_NUM') THEN
                where_ := 'ID_FLEX_NUM = ' || flexNum;
            ELSIF colExists(baseTbl, 'CHART_OF_ACCOUNTS_ID') THEN
                -- GL_CODE_COMBINATIONS stores the structure reference as CHART_OF_ACCOUNTS_ID
                where_ := 'CHART_OF_ACCOUNTS_ID = ' || flexNum;
            ELSE
                -- No standard discriminator column; caller must add their own filter if needed
                note := '-- NOTE: No structure filter applied — ' || baseTbl
                    || ' has no ID_FLEX_NUM or CHART_OF_ACCOUNTS_ID column.' || CHR(10)
                    || '-- Resolved id_flex_num = ' || flexNum
                    || ' (add new filter if a structure discriminator exists).' || CHR(10);
            END IF;
        END IF;

        RETURN '-- Generated by XXX_FLEX_UTIL.KFF_SAMPLE_SQL' || CHR(10)
            || '-- KFF       : ' || kffCode       || CHR(10)
            || '-- Structure : ' || structureCode || CHR(10)
            || '-- id_flex_num: ' || NVL(TO_CHAR(flexNum), '(not resolved)') || CHR(10)
            || '-- ORDER BY  : ' || CASE UPPER(orderBy) WHEN 'Y' THEN 'ON (CREATION_DATE DESC)' ELSE 'OFF' END || CHR(10)
            || note
            || buildSelectSQL(segs, cnt, baseTbl, where_, 25, TRUE, orderBy);
    END KFF_SAMPLE_SQL;

    FUNCTION KFF_SAMPLE_HTML(
        kffCode       IN VARCHAR2,
        structureCode IN VARCHAR2,
        rows          IN NUMBER   DEFAULT 25,
        orderBy       IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB IS
        segs    t_seg_tab;
        segCnt  PLS_INTEGER;
        labels  t_seg_tab;
        total   PLS_INTEGER;
        baseTbl VARCHAR2(240);
        flexNum NUMBER;
        where_  VARCHAR2(200);
        execSql CLOB;
    BEGIN
        buildSegsKFF(kffCode, structureCode, segs, segCnt, baseTbl, flexNum);

        IF baseTbl IS NULL THEN
            RETURN CHR(10) || 'KFF code not found: ' || escapeHTML(kffCode) || CHR(10);
        END IF;
        IF segCnt = 0 THEN
            RETURN CHR(10) || 'No enabled segments found for KFF [' || escapeHTML(kffCode)
                || '] structure [' || escapeHTML(structureCode) || ']' || CHR(10);
        END IF;

        IF flexNum IS NOT NULL THEN
            IF colExists(baseTbl, 'ID_FLEX_NUM') THEN
                where_ := 'ID_FLEX_NUM = ' || flexNum;
            ELSIF colExists(baseTbl, 'CHART_OF_ACCOUNTS_ID') THEN
                where_ := 'CHART_OF_ACCOUNTS_ID = ' || flexNum;
            END IF;
        END IF;

        buildLabelArray(segs, segCnt, baseTbl, labels, total);
        execSql := buildSelectSQL(segs, segCnt, baseTbl, where_, rows, FALSE, orderBy);
        RETURN executeHTML(execSql, labels, total);
    END KFF_SAMPLE_HTML;

    PROCEDURE KFF_DATA_OUT(
        kffCode       IN VARCHAR2,
        structureCode IN VARCHAR2,
        rows          IN NUMBER   DEFAULT 25,
        orderBy       IN VARCHAR2 DEFAULT 'Y'
    ) IS
        segs    t_seg_tab;
        segCnt  PLS_INTEGER;
        labels  t_seg_tab;
        total   PLS_INTEGER;
        baseTbl VARCHAR2(240);
        flexNum NUMBER;
        where_  VARCHAR2(200);
        discCol VARCHAR2(30) := '(none)';
        execSql CLOB;
    BEGIN
        DBMS_OUTPUT.ENABLE(1000000);
        buildSegsKFF(kffCode, structureCode, segs, segCnt, baseTbl, flexNum);

        IF baseTbl IS NULL THEN
            DBMS_OUTPUT.PUT_LINE('ERROR: KFF code not found: ' || kffCode);
            RETURN;
        END IF;
        IF segCnt = 0 THEN
            DBMS_OUTPUT.PUT_LINE('No segments found for KFF [' || kffCode
                || '] structure [' || structureCode || ']');
            RETURN;
        END IF;

        IF flexNum IS NOT NULL THEN
            IF colExists(baseTbl, 'ID_FLEX_NUM') THEN
                where_  := 'ID_FLEX_NUM = ' || flexNum;
                discCol := 'ID_FLEX_NUM';
            ELSIF colExists(baseTbl, 'CHART_OF_ACCOUNTS_ID') THEN
                where_  := 'CHART_OF_ACCOUNTS_ID = ' || flexNum;
                discCol := 'CHART_OF_ACCOUNTS_ID';
            END IF;
        END IF;

        buildLabelArray(segs, segCnt, baseTbl, labels, total);
        execSql := buildSelectSQL(segs, segCnt, baseTbl, where_, rows, FALSE, orderBy);

        executeOutput(
            execSql, labels, total,
            'KFF: '       || kffCode       || '  Structure: ' || structureCode
            || '  id_flex_num: ' || NVL(TO_CHAR(flexNum), '?')
            || '  Disc Col: '    || discCol
            || '  Table: '       || baseTbl
            || '  ORDER BY: '    || CASE UPPER(orderBy) WHEN 'Y' THEN 'ON' ELSE 'OFF' END
        );
    END KFF_DATA_OUT;

END XXX_FLEX_UTIL;
/