-- 8a. SQL injection attempt -- should return a comment, not raise an exception
DECLARE
    l_sql CLOB;
BEGIN
    l_sql := XXX_FLEX_UTIL.dff_sample_sql(
                 dffName     => 'GL_JE_HEADERS',
                 contextCode => 'Global Data Elements',
                 baseTable   => 'GL_JE_HEADERS; DROP TABLE T--'  -- intentional bad input
             );
    DBMS_OUTPUT.PUT_LINE(l_sql);
END;
/

-- 8b. Unknown context code -- should print informational message, not raise exception
BEGIN
    XXX_FLEX_UTIL.dff_data_out(
        dffName     => 'GL_JE_HEADERS',
        contextCode => 'CONTEXT_THAT_DOES_NOT_EXIST',
        baseTable   => 'GL_JE_HEADERS',
        rows        => 5
    );
END;
/

-- 8c. Unknown KFF code -- should print "ERROR: KFF code not found", not raise exception
BEGIN
    XXX_FLEX_UTIL.kff_data_out(
        kffCode       => 'ZZZZ',
        structureCode => 'ANYTHING',
        rows          => 5
    );
END;
/