CREATE OR REPLACE TYPE clob_varray1_t AS VARRAY(1) OF CLOB;
/
create or replace package sqm_util as
/* SQM = SQl Macro
Package providing common services for parameters of type DBMS_TF.TABLE_T and DBMS_TF.COLUMNS_T
*/
 
------- Getting the contents of a DBMS_TF.TABLE_T structure: better than DBMS_TF.TRACE
 
  -- SQL table macro to store the TABLE_T data as JSON, then return it
  function get_table_t_json(
    p_table in dbms_tf.table_t
  ) return varchar2 sql_macro;
 
  -- SQL table macro to store the TABLE_T data, then return it flattened
  function get_table_t_flattened(
    p_table in dbms_tf.table_t
  ) return varchar2 sql_macro;
 
-------- Lookup table based on (type)(charsetform) from DBMS_TF.TABLE_T.column(i).description
  type t_col_data is record(
    column_name varchar2(130),  -- from TABLE_T.column(i).description.name
    type_label varchar2(128),   -- My label for datatype associated with each type/charsetform
    to_string varchar2(256),    -- expression translating the datatype to a string (useful for UNPIVOT + comparisons)
    comparable varchar2(256)    -- expression translating the datatype to something comparable (e.g. hash for LOB)
  );
  type tt_col_data is table of t_col_data;
 
  -- procedure that fills a tt_col_data variable based on the input TABLE_T structure
  procedure col_data_records(
    p_table in dbms_tf.table_t,
    pt_col_data in out nocopy tt_col_data
  );
 
  -- procedure that fills comma-separated lists of data from a tt_col_data instance
  -- columns listed in the optional EXCLUDE parameter are omitted
  procedure col_data_strings(
    p_table in dbms_tf.table_t,
    p_column_names in out nocopy long,
    p_type_labels in out nocopy long,
    p_to_strings in out nocopy long,
    p_comparables in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  );
 
  -- convenience procedures to fill any one of the above lists
  procedure col_column_names(
    p_table in dbms_tf.table_t,
    p_column_names in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  );
 
  procedure col_type_labels(
    p_table in dbms_tf.table_t,
    p_type_labels in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  );
 
  procedure col_to_strings(
    p_table in dbms_tf.table_t,
    p_to_strings in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  );
 
  procedure col_comparables(
    p_table in dbms_tf.table_t,
    p_comparables in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  );
 
  -- procedure to convert a DBMS_TF.COLUMNS_T table into a string list.
  -- Each item in the list is generated from p_template with '%s' replaced by the column name
  -- Items are delimited by p_delimiter
  -- All COLUMNS_T members are double-quoted, so there is an option to remove the quotes
  procedure list_columns(
    p_columns in dbms_tf.columns_t,
    p_column_list in out nocopy varchar2,
    p_template in varchar2 default '%s',
    p_delimiter in varchar2 default ',',
    p_remove_quotes boolean default false
  );
 
-------- The stuff that follows is meant to be called by SQL generated from macros
   
  -- function used in to_string expression when datatype is BFILE
  function get_bfile_info(p_bfile in bfile) return varchar2;
 
  -- CLOB to store trace of a DBMS_TF.TABLE_T structure (in JSON pretty print format)
  table_t_clob clob;
   
  -- procedure that stores a JSON equivalent of an input TABLE_T structure
  -- I add the "type_label" from my lookup table
  procedure put_table_t_clob(
    p_table in dbms_tf.table_t
  );
 
  -- table function to return contents of table_t_clob, then reset
  function get_table_t_clob return clob_varray1_t;
 
end sqm_util;
/