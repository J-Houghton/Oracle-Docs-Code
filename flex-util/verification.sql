-- 1. Confirm all required FND objects are visible from your custom schema
SELECT object_name, status
FROM   all_objects
WHERE  object_name IN (
    'FND_DESCRIPTIVE_FLEXS_VL','FND_DESCR_FLEX_CONTEXTS_VL',
    'FND_DESCR_FLEX_COLUMN_USAGES','FND_DESCR_FLEX_COL_USAGE_TL',
    'FND_ID_FLEXS','FND_ID_FLEX_STRUCTURES','FND_ID_FLEX_STRUCTURES_VL',
    'FND_ID_FLEX_SEGMENTS_VL','FND_FLEX_VALUE_SETS',
    'FND_APPLICATION','FND_APPLICATION_TL','FND_USER'
)
ORDER BY object_name;
-- Expected: 12 rows, all STATUS = 'VALID'

-- 2. Confirm FETCH FIRST syntax is supported (Oracle 12c+)
SELECT 1 FROM dual FETCH FIRST 1 ROWS ONLY;

-- 3. Confirm NLS language matches an installed FND language
SELECT USERENV('LANG') AS session_lang FROM dual;
SELECT language_code    FROM fnd_languages WHERE installed_flag = 'B';
-- Expected: session_lang appears in the installed language list