create or replace function compare_rowsets(
  p_old_table in dbms_tf.table_t,
  p_new_table in dbms_tf.table_t,
  p_key_cols in dbms_tf.columns_t default null,
  p_exclude_cols in dbms_tf.columns_t default null
) return clob sql_macro is
/*
Compares tables, views or named subqueries; one is "old", one is "new".
Optional excluded columns are excluded from the comparison and the output.
 
The output contains the values used for the comparison, which may differ
from the actual values of the data if the data types do not allow
direct comparison (LOBs for example).
 
Column "Z#_OP" indicates the type of change:
- I: Insert into old (present in new, not old)
- D: Delete from old (present in old, not new)
- U: Updated data (as present in new)
- O: Old data (as present in old)
 
If present, key column(s) must identify all rows uniquely.
 
Without key columns, the output contains only 'D' and 'I' rows,
and column "Z#_CNT" shows the number of rows to be deleted or inserted.
*/
  l_col_column_names_old long;
  l_col_comparables_old long;
  l_col_comparables_new long;
  l_col_keys long;
  l_sql clob;
begin
  sqm_util.col_column_names(p_old_table, l_col_column_names_old, p_exclude_cols);
  sqm_util.col_comparables(p_old_table, l_col_comparables_old, p_exclude_cols);
  sqm_util.col_comparables(p_new_table, l_col_comparables_new, p_exclude_cols);
   
  if p_key_cols is null then
   
    l_sql :=
    'select /*+ qb_name(COMPARE) */
      decode(sign(sum(Z#_NEW_CNT)), 1, ''I'', ''D'') Z#_OP,
      abs(sum(Z#_NEW_CNT)) Z#_CNT,
      '|| l_col_column_names_old ||'
    FROM (
      select /*+ qb_name(old) */
      '|| l_col_comparables_old ||'
        , -1 Z#_NEW_CNT
      from p_old_table O
      union all
      select /*+ qb_name(new) */
      '|| l_col_comparables_new ||'
        , 1 Z#_NEW_CNT
      from p_new_table N
    )
    group by
      '|| l_col_column_names_old ||'
    having sum(Z#_NEW_CNT) != 0';
 
  else
    sqm_util.list_columns(p_key_cols, l_col_keys);
    l_sql := 
      'select /*+ qb_name(COMPARE) */
        case count(*) over(partition by
          '|| l_col_keys ||'
        ) - Z#_NEW_CNT
          when 0 then ''I''
          when 1 then ''U''
          when 2 then ''D''
          when 3 then ''O''
        end Z#_OP,
        '|| l_col_column_names_old ||'
      FROM (
        select
          '|| l_col_column_names_old ||',
          sum(Z#_NEW_CNT) Z#_NEW_CNT
        FROM (
          select /*+ qb_name(old) */
          '|| l_col_comparables_old ||',
          -1 Z#_NEW_CNT
          from p_old_table O
          union all
          select /*+ qb_name(new) */
          '|| l_col_comparables_new ||',
          1 Z#_NEW_CNT
          from p_new_table N
        )
        group by
          '|| l_col_column_names_old ||'
        having sum(Z#_NEW_CNT) != 0
      )';
 
  end if;
  --dbms_output.put_line(l_sql);
  return l_sql;
end compare_rowsets;
/