create or replace package body sqm_util as
 
---- Types, constants, variables, functions and procedures accessible within BODY only
 
  -- Length of substring displayed for LOBs
  c_substr_length constant number := 1000;
 
  -- Constant values for stringifying datatypes (must produce %CHAR%, not N%CHAR%)
  c_self constant varchar2(128) := '%s';
  c_to_char constant varchar2(128) := 'to_char(%s) %s';
  c_num_to_string constant varchar2(128) := 'to_char(%s, ''TM'') %s';
  c_long_to_string constant varchar2(128) := '''(LONG* unsupported)'' %s';
  c_date_to_string constant varchar2(128) := 'to_char(%s, ''yyyy-mm-dd"T"hh24:mi:ss'') %s';
  c_raw_to_string constant varchar2(128) := 'rawtohex(%s) %s';
  c_xml_to_string constant varchar2(128) := '(%s).getstringval() %s';
  c_rowid_to_string constant varchar2(128) := 'rowidtochar(%s) %s';
  c_clob_to_string constant varchar2(128) := 'to_char(substr(%s, 1, '||c_substr_length||')) %s';
  c_nclob_to_string constant varchar2(128) := 'cast(to_char(substr(%s, 1, '||c_substr_length||')) as varchar2('||c_substr_length||')) %s';
  c_blob_to_string constant varchar2(128) := 'rawtohex(substrb(%s, 1, '||c_substr_length||')) %s';
  c_bfile_to_string constant varchar2(128) := 'sqm_util.get_bfile_info(%s) %s';
  c_json_to_string constant varchar2(128) := 'json_serialize(%s) %s';
  c_object_to_string constant varchar2(128) := 'json_object(%s) %s';
  c_collection_to_string constant varchar2(128) := 'json_array(%s) %s';
  c_ts_to_string constant varchar2(128) := 'to_char(%s, ''fmyyyy-mm-dd"T"hh24:mi:ss.ff'') %s';
  c_tsz_to_string constant varchar2(128) := 'to_char(%s, ''fmyyyy-mm-dd"T"hh24:mi:ss.ff tzr'') %s';
  c_tsltz_to_string constant varchar2(128) := 'to_char(%s at time zone ''UTC'', ''fmyyyy-mm-dd"T"hh24:mi:ss.ff tzr'') %s';
   
  -- Allow comparison, group by, etc. for datatypes that do not allow it natively
  c_lob_comparable constant varchar2(128) := '''HASH_SH256: ''||dbms_crypto.hash(%s, 4) %s';  
   
  -- Constant lookup table (indexed by type, charsetform) providing templates for col_data records
  -- Copy the template to the output record, plug the column name into the COLUMN_NAME field
  -- and in the other fields replace %s with the column name
  type taa_col_data is table of t_col_data index by pls_integer;
  type ttaa_col_data is table of taa_col_data index by pls_integer;
  ctaa_col_data constant ttaa_col_data := ttaa_col_data(
    1=>taa_col_data(
                    1=>t_col_data(null, 'VARCHAR2',       c_self,                 c_self),
                    2=>t_col_data(null, 'NVARCHAR2',      c_to_char,              c_self)
    ),
    2=>taa_col_data(0=>t_col_data(null, 'NUMBER',         c_num_to_string,        c_self)),
    8=>taa_col_data(0=>t_col_data(null, 'LONG',           c_long_to_string,       c_long_to_string)),
   12=>taa_col_data(0=>t_col_data(null, 'DATE',           c_date_to_string,       c_self)),
   13=>taa_col_data(0=>t_col_data(null, 'EDATE',          c_date_to_string,       c_self)),
   23=>taa_col_data(0=>t_col_data(null, 'RAW',            c_raw_to_string,        c_self)),
   24=>taa_col_data(0=>t_col_data(null, 'LONG_RAW',       c_long_to_string,       c_long_to_string)),
   58=>taa_col_data(0=>t_col_data(null, 'XMLTYPE',        c_xml_to_string,        c_xml_to_string)),
   69=>taa_col_data(0=>t_col_data(null, 'ROWID',          c_rowid_to_string,      c_self)),
      -- As of 2021-02-14 typecode 1 is returned instead of 96
   96=>taa_col_data(
                    1=>t_col_data(null, 'CHAR',           c_self,                 c_self),
                    2=>t_col_data(null, 'NCHAR',          c_to_char,              c_self)
  ),
  100=>taa_col_data(0=>t_col_data(null, 'BINARY_FLOAT',   c_num_to_string,        c_self)),
  101=>taa_col_data(0=>t_col_data(null, 'BINARY_DOUBLE',  c_num_to_string,        c_self)),
  112=>taa_col_data(
                    1=>t_col_data(null, 'CLOB',           c_clob_to_string,       c_lob_comparable),
                    2=>t_col_data(null, 'NCLOB',          c_nclob_to_string,      c_lob_comparable)
  ),
  113=>taa_col_data(0=>t_col_data(null, 'BLOB',           c_blob_to_string,       c_lob_comparable)),
  114=>taa_col_data(0=>t_col_data(null, 'BFILE',          c_bfile_to_string,      c_bfile_to_string)),
  119=>taa_col_data(0=>t_col_data(null, 'JSON',           c_json_to_string,       c_json_to_string)),
  121=>taa_col_data(0=>t_col_data(null, 'UDT_OBJECT',     c_object_to_string,     c_object_to_string)),
  122=>taa_col_data(0=>t_col_data(null, 'UDT_NESTED',     c_collection_to_string, c_collection_to_string)),
  123=>taa_col_data(0=>t_col_data(null, 'UDT_VARRAY',     c_collection_to_string, c_collection_to_string)),
  180=>taa_col_data(0=>t_col_data(null, 'TIMESTAMP',      c_ts_to_string,         c_self)),
  181=>taa_col_data(0=>t_col_data(null, 'TIMESTAMP_TZ',   c_tsz_to_string,        c_self)),
  182=>taa_col_data(0=>t_col_data(null, 'INTERVAL_YM',    c_to_char,              c_self)),
  183=>taa_col_data(0=>t_col_data(null, 'INTERVAL_DS',    c_to_char,              c_self)),
  187=>taa_col_data(0=>t_col_data(null, 'ETIMESTAMP',     c_ts_to_string,         c_self)),
  188=>taa_col_data(0=>t_col_data(null, 'ETIMESTAMP_TZ',  c_tsz_to_string,        c_self)),
  189=>taa_col_data(0=>t_col_data(null, 'EINTERVAL_YM',   c_to_char,              c_self)),
  190=>taa_col_data(0=>t_col_data(null, 'EINTERVAL_DS',   c_to_char,              c_self)),
  231=>taa_col_data(0=>t_col_data(null, 'TIMESTAMP_LTZ',  c_tsltz_to_string,      c_self)),
  232=>taa_col_data(0=>t_col_data(null, 'ETIMESTAMP_LTZ', c_tsltz_to_string,      c_self))
  );
 
---- Public functions / procedures: see package specification for description
 
  function get_bfile_info(p_bfile in bfile) return varchar2 is
    l_dir_alias varchar2(128);
    l_filename varchar2(128);
  begin
    dbms_lob.filegetname (p_bfile, l_dir_alias, l_filename); 
    return 'bfilename(''' || l_dir_alias || ''', ''' || l_filename ||''')';
  end get_bfile_info;
 
  procedure put_table_t_clob(
    p_table in dbms_tf.table_t
  ) is
    l_column dbms_tf.table_columns_t;
    ja_column json_array_t;
    jo_table json_object_t;
   
    procedure get_description(
      p_description in dbms_tf.column_metadata_t,
      jo_description in out nocopy json_object_t
    ) is
    begin
      jo_description := new json_object_t;
      jo_description.put('type', p_description.type);
      jo_description.put('max_len', p_description.max_len);
      jo_description.put('name', p_description.name);
      jo_description.put('name_len', p_description.name_len);
      jo_description.put('precision', p_description.precision);
      jo_description.put('scale', p_description.scale);
      jo_description.put('charsetid', p_description.charsetid);
      jo_description.put('charsetform', p_description.charsetform);
      jo_description.put('collation', p_description.collation);
      jo_description.put('type_label', ctaa_col_data(p_description.type)(p_description.charsetform).type_label);
      -- following lines commented out until Oracle supports this info
      --jo_description.put('schema_name', p_description.schema_name);
      --jo_description.put('schema_name_len', p_description.schema_name_len);
      --jo_description.put('type_name', p_description.type_name);
      --jo_description.put('type_name_len', p_description.type_name_len);
    end get_description;
     
    procedure get_column_element(
      p_column_element dbms_tf.column_t,
      jo_column_element in out nocopy json_object_t
    ) is
      l_description dbms_tf.column_metadata_t;
      jo_description json_object_t;
    begin
      jo_column_element := new json_object_t;
      l_description := p_column_element.description;
      get_description(l_description, jo_description);
      jo_column_element.put('description', jo_description);
      jo_column_element.put('pass_through', p_column_element.pass_through);
      jo_column_element.put('for_read', p_column_element.for_read);
    end get_column_element;
     
    procedure get_column(
      p_column dbms_tf.table_columns_t,
      ja_column in out nocopy json_array_t
    ) is
      l_column_element dbms_tf.column_t;
      jo_column_element json_object_t;
    begin
      ja_column := new json_array_t;
      for i in 1..p_column.count loop
        l_column_element := p_column(i);
        get_column_element(l_column_element, jo_column_element);
        ja_column.append(jo_column_element);
      end loop;
    end get_column;  
     
  begin
    jo_table := new json_object_t;
    jo_table.put('schema_name',p_table.schema_name);
    jo_table.put('package_name',p_table.package_name);
    jo_table.put('ptf_name',p_table.ptf_name);
    -- jo_table.put('table_schema_name',p_table.table_schema_name);
    -- jo_table.put('table_name',p_table.table_name);
    l_column := p_table.column;
    get_column(l_column, ja_column);
    jo_table.put('column',ja_column);
    sqm_util.table_t_clob := jo_table.to_clob;
    select json_serialize(sqm_util.table_t_clob returning clob pretty)
      into sqm_util.table_t_clob
    from dual;
  end put_table_t_clob;
 
  function get_table_t_clob return clob_varray1_t is
    l_clob clob := sqm_util.table_t_clob;
  begin
    sqm_util.table_t_clob := null;
    return clob_varray1_t(l_clob);
  end get_table_t_clob;
 
  function get_table_t_json(
    p_table in dbms_tf.table_t
  ) return varchar2 sql_macro is
    l_sql varchar2(4000) :=
      'select column_value table_t_json from sqm_util.get_table_t_clob()';
  begin
    put_table_t_clob(p_table);
    return l_sql;
  end get_table_t_json;
 
  function get_table_t_flattened(
    p_table in dbms_tf.table_t
  ) return varchar2 sql_macro is
    l_sql varchar2(4000) := '
      select j.*
      from sqm_util.get_table_t_clob(), json_table(
        column_value, ''$'' columns (
      --    table_schema_name, table_name,
          nested path ''$.column[*].description'' columns (
            column_id for ordinality,
            type number, charsetform number, type_label, max_len number,
            name, name_len number,
            precision number, scale number, charsetid number, collation number
          )
        )
      ) j';
  begin
    put_table_t_clob(p_table);
    return l_sql;
  end get_table_t_flattened;
   
  procedure col_data_records(
    p_table in dbms_tf.table_t,
    pt_col_data in out nocopy tt_col_data
  ) is
    l_table_columns_t dbms_tf.table_columns_t := p_table.column;
    l_meta dbms_tf.column_metadata_t;
    l_col_data t_col_data;
  begin
    pt_col_data := new tt_col_data();
    for i in 1..l_table_columns_t.count loop
      l_meta := l_table_columns_t(i).description;
      l_col_data := ctaa_col_data(l_meta.type)(l_meta.charsetform);
      l_col_data.column_name := l_meta.name;
      l_col_data.to_string := replace(l_col_data.to_string, '%s', l_meta.name);
      l_col_data.comparable := replace(l_col_data.comparable, '%s', l_meta.name);
      pt_col_data.extend;
      pt_col_data(i) := l_col_data;
    end loop;
  end col_data_records;
 
  procedure col_data_strings(
    p_table in dbms_tf.table_t,
    p_column_names in out nocopy long,
    p_type_labels in out nocopy long,
    p_to_strings in out nocopy long,
    p_comparables in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  ) is
    l_table_columns_t dbms_tf.table_columns_t := p_table.column;
    l_meta dbms_tf.column_metadata_t;
    l_col_data t_col_data;
    type t_cols_lookup is table of int index by varchar2(130);
    lt_cols_lookup t_cols_lookup;
    is_first_item boolean := true;
  begin
    if p_exclude_cols is not null then
      for i in 1..p_exclude_cols.count loop
        lt_cols_lookup(p_exclude_cols(i)) := 0;
      end loop;
    end if;
     
  for i in 1..l_table_columns_t.count loop
      l_meta := l_table_columns_t(i).description;
      if lt_cols_lookup.exists(l_meta.name) then
        continue;
      end if;
      l_col_data := ctaa_col_data(l_meta.type)(l_meta.charsetform);
      p_column_names := case when not is_first_item then p_column_names || ',' end
                        || l_meta.name;
      p_type_labels  := case when not is_first_item then p_type_labels  || ',' end
                        || l_col_data.type_label;
      p_to_strings   := case when not is_first_item then p_to_strings   || ',' end
                        || replace(l_col_data.to_string, '%s', l_meta.name);
      p_comparables  := case when not is_first_item then p_comparables  || ',' end
                        || replace(l_col_data.comparable, '%s', l_meta.name);
      is_first_item := false;
    end loop;
  end col_data_strings;
 
  procedure col_column_names(
    p_table in dbms_tf.table_t,
    p_column_names in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  ) is
    l_type_labels long;
    l_to_strings long;
    l_comparables long;
  begin
    col_data_strings(p_table, p_column_names,l_type_labels,l_to_strings,l_comparables,
      p_exclude_cols);
  end col_column_names;
 
  procedure col_type_labels(
    p_table in dbms_tf.table_t,
    p_type_labels in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  ) is
    l_column_names long;
    l_to_strings long;
    l_comparables long;
  begin
    col_data_strings(p_table, l_column_names,p_type_labels,l_to_strings,l_comparables,
      p_exclude_cols);
  end col_type_labels;
 
  procedure col_to_strings(
    p_table in dbms_tf.table_t,
    p_to_strings in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  ) is
    l_column_names long;
    l_type_labels long;
    l_comparables long;
  begin
    col_data_strings(p_table, l_column_names,l_type_labels,p_to_strings,l_comparables,
      p_exclude_cols);
  end col_to_strings;
 
  procedure col_comparables(
    p_table in dbms_tf.table_t,
    p_comparables in out nocopy long,
    p_exclude_cols in dbms_tf.columns_t default null
  ) is
    l_column_names long;
    l_type_labels long;
    l_to_strings long;
  begin
    col_data_strings(p_table, l_column_names,l_type_labels,l_to_strings,p_comparables,
      p_exclude_cols);
  end col_comparables;
 
  procedure list_columns(
    p_columns in dbms_tf.columns_t,
    p_column_list in out nocopy varchar2,
    p_template in varchar2 default '%s',
    p_delimiter in varchar2 default ',',
    p_remove_quotes boolean default false
  ) is
    l_column varchar2(130);
  begin
    for i in 1..p_columns.count loop
      l_column := p_columns(i);
      if p_remove_quotes then
        l_column := trim('"' from l_column);
      end if;
      p_column_list :=
        case when i > 1 then p_column_list || p_delimiter end ||
        replace(p_template, '%s', l_column);
    end loop;
  end list_columns;
 
end sqm_util;
/
