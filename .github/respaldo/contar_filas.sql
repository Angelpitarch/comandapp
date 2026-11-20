-- Filas de cada tabla de public y private: "esquema.tabla cantidad", una por linea.
-- Lo usa el respaldo (backup.yml) para comparar produccion con la copia restaurada. No muestra datos.
select format('%s.%s', table_schema, table_name),
       (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text::bigint
  from information_schema.tables
 where table_schema in ('public', 'private') and table_type = 'BASE TABLE'
 order by 1;
