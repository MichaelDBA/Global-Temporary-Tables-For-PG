-- ---------------------------------------------------------------------------
-- pg_global_temp_tables
--
-- Emulates Oracle-style global temporary tables in PostgreSQL
-- Based on article written by Alexey Yakovlev <yallie@yandex.ru>
-- Creates 2 functions: create_permanent_temp_table, drop_permanent_temp_table
-- ---------------------------------------------------------------------------
SET client_encoding TO 'UTF8';
SET search_path = public, pg_catalog;

-- create or replace function create_permanent_temp_table(p_table_name varchar, p_schema varchar default null)
create or replace function create_permanent_temp_table(p_table_name varchar, p_schema varchar, p_deleterows boolean default true)
returns void as $$
declare
        -- https://github.com/yallie/pg_global_temp_tables
        v_table_name varchar := p_table_name || '$tmp';
        v_trigger_name varchar := p_table_name || '$iud';
        v_final_statement text;
        v_table_statement text; -- create temporary table...
        v_index_statement text; -- create indexes for temp table if available
        v_all_column_list text; -- id, name, ...
        v_new_column_list text; -- new.id, new.name, ...
        v_assignment_list text; -- id = new.id, name = new.name, ...
        v_cols_types_list text; -- id bigint, name varchar, ...
        v_old_column_list text; -- id = old.id, name = old.name, ...
        v_old_pkey_column text; -- id = old.id
        pos1 INT;
        pos2 INT;
        aschema text;
begin
        -- check if the temporary table exists
        if not exists(select 1 from pg_class where relname = p_table_name and relpersistence = 't') then
                raise exception 'Temporary table % does not exist. %', p_table_name, 'Create an ordinary temp ' ||
                        'table first, then use create_permanent_temp_table function to convert it to a permanent one.'
                        using errcode = 'UTMP1';
        end if;

        -- make sure that the schema is defined
        if p_schema is null or p_schema = '' then
                p_schema := current_schema;
        end if;

        -- generate the temporary table statement
        with pkey as
        (
                select cc.conrelid, format(E',
                constraint %I primary key(%s)', cc.conname,
                        string_agg(a.attname, ', ' order by array_position(cc.conkey, a.attnum))) pkey
                from pg_catalog.pg_constraint cc
                        join pg_catalog.pg_class c on c.oid = cc.conrelid
                        join pg_catalog.pg_attribute a on a.attrelid = cc.conrelid and a.attnum = any(cc.conkey)
                where cc.contype = 'p'
                group by cc.conrelid, cc.conname
        )
        select format(E'\tcreate temporary table if not exists %I\n\t(\n%s%s\n\t)\n\tON COMMIT',
                v_table_name,
                string_agg(
			format(E'\t\t%I %s%s%s',
				a.attname,
				pg_catalog.format_type(a.atttypid, a.atttypmod),
				case when a.attnotnull then ' not null' else '' end,
			        case when a.atthasdef = true then ' default ' || pg_get_expr(d.adbin, d.adrelid) else '' end
			), E',\n'
			order by a.attnum
                ),
                (select pkey from pkey where pkey.conrelid = c.oid)) as sql
        into v_table_statement
        from pg_catalog.pg_class c
		join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attnum > 0
		left outer join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
		join pg_catalog.pg_type t on a.atttypid = t.oid
	where c.relname = p_table_name and c.relpersistence = 't'
        group by c.oid, c.relname;

	-- MJV CHANGE: allow session life or transaction life
        IF p_deleterows THEN
          v_table_statement := v_table_statement || ' DELETE ROWS;';
        ELSE
          v_table_statement := v_table_statement || ' PRESERVE ROWS;';
        END IF;

        set client_min_messages to notice;        
        -- RAISE NOTICE 'table=%', v_table_statement;

       -- MJV CHANGE: create indexes as part of table statement if available
       -- NOT WORKING YET since we are querying
       -- RAISE NOTICE 'p_table_name=%  v_table_name=%', p_table_name, v_table_name;
       select string_agg(pg_get_indexdef(indexrelid) || ';', E'\n' ) INTO v_index_statement from pg_index where indrelid = p_table_name::regclass;
       -- need to remove internal schema qualifier from indexdef
       -- RAISE NOTICE 'indexes before=%', v_index_statement;
       pos1 := POSITION(' ON pg_temp' IN v_index_statement);
       pos2 := POSITION('."' IN v_index_statement);
       select substring(v_index_statement, pos1+3, pos2+1-pos1-3) INTO aschema;
       v_index_statement := REPLACE(v_index_statement, aschema, ' ');
       v_index_statement := REPLACE(v_index_statement, p_table_name, v_table_name);
       v_index_statement := REPLACE(v_index_statement, ' INDEX ', ' INDEX IF NOT EXISTS ');
      
       -- RAISE NOTICE 'indexes after =%', v_index_statement;
       v_table_statement := v_table_statement || E'\n' || v_index_statement;
       
       set client_min_messages to error;        

	-- generate the lists of columns
	select
		string_agg(a.attname, ', '),
		string_agg(format('%s', case when a.atthasdef = true then 'coalesce(new.' || a.attname || ', ' || pg_get_expr(d.adbin, d.adrelid) || ')' else 'new.' || a.attname end), ', '),
		string_agg(format('%I = new.%I', a.attname, a.attname), ', '),
		string_agg(format('%I %s', a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod)), ', '),
		string_agg(format('%I = old.%I', a.attname, a.attname), ' and ')
	into
		v_all_column_list, v_new_column_list, v_assignment_list, v_cols_types_list, v_old_column_list
	from pg_catalog.pg_class c
		join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attnum > 0
		left outer join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
		join pg_catalog.pg_type t on a.atttypid = t.oid
	where c.relname = p_table_name and c.relpersistence = 't';

	-- generate the list of primary key columns
	select string_agg(format('%I = old.%I', a.attname, a.attname), ' and ' 
		order by array_position(cc.conkey, a.attnum))
	into v_old_pkey_column
	from pg_catalog.pg_constraint cc
		join pg_catalog.pg_class c on c.oid = cc.conrelid
		join pg_catalog.pg_attribute a on a.attrelid = cc.conrelid and a.attnum = any(cc.conkey)
		left outer join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
	where cc.contype = 'p' and c.relname = p_table_name and c.relpersistence = 't'
	group by cc.conrelid, cc.conname;

        -- if primary key is defined, use the primary key columns
        if length(v_old_pkey_column) > 0 then
                v_old_column_list := v_old_pkey_column;
        end if;

        -- generate the view function
        v_final_statement := format(E'-- rename the original table to avoid the conflict
alter table %I rename to %I;

-- the function to select from the temporary table
create or replace function %I.%I() returns table(%s) as $x$
begin
        -- generated by pg_global_temp_tables
        -- create table statement
%s

        return query select * from %I;
end;
$x$ language plpgsql
set client_min_messages to error;\n',
        p_table_name, v_table_name,
        p_schema, p_table_name, v_cols_types_list,
        v_table_statement, v_table_name);

        -- generate the view
        v_final_statement := v_final_statement || format(E'
create or replace view %I.%I as
        select * from %I.%I();\n',
        p_schema, p_table_name, p_schema, p_table_name);

        -- generate the trigger function
        v_final_statement := v_final_statement || format(E'
create or replace function %I.%I() returns trigger as $x$
begin
        -- generated by pg_global_temp_tables
        -- create temporary table
%s

        -- handle the trigger operation
        if lower(tg_op) = \'insert\' then
                insert into %I(%s)
                values (%s);
                return new;
        elsif lower(tg_op) = \'update\' then
                update %I
                set %s
                where %s;
                return new;
        elsif lower(tg_op) = \'delete\' then
                delete from %I
                where %s;
                return old;
        end if;
end;
$x$ language plpgsql set client_min_messages to error;\n',
        p_schema, v_trigger_name, v_table_statement,  -- function header
        v_table_name, v_all_column_list, v_new_column_list, -- insert
        v_table_name, v_assignment_list, v_old_column_list, -- update
        v_table_name, v_old_column_list); -- delete

        -- generate the view trigger
        v_final_statement := v_final_statement || format(E'
drop trigger if exists %I on %I.%I;
create trigger %I
        instead of insert or update or delete on %I.%I
        for each row
        execute procedure %I.%I();',
        v_trigger_name, p_schema, p_table_name,
        v_trigger_name, p_schema, p_table_name,
        p_schema, v_trigger_name);

        -- create all objects at once
        execute v_final_statement;
end;
$$ language plpgsql set client_min_messages to error;

create or replace function drop_permanent_temp_table(p_table_name varchar, p_schema varchar default null)
returns void as $$
declare
        -- https://github.com/yallie/pg_global_temp_tables
        v_table_name varchar := p_table_name || '$tmp';
        v_trigger_name varchar := p_table_name || '$iud';
        v_count int;
        v_drop_statements text;
begin
        -- make sure that the schema is defined
        if p_schema is null or p_schema = '' then
                p_schema := current_schema;
        end if;

        -- check if the supporting functions exist
        select count(*)
        into v_count
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where p.proname in (p_table_name, v_trigger_name) and
                p.pronargs = 0 and n.nspname = p_schema and
                p.prosrc like '%pg_global_temp_tables%';

        if v_count <> 2 then
                raise exception 'The table %.% does not seem to be persistent temporary table. %', p_schema,
                        p_table_name, 'The function only supports tables created by pg_global_temp_tables library.'
                        using errcode = 'UTMP2';
        end if;

        -- generate the drop function statements
        v_drop_statements := format(E'-- drop the functions and cascade the view
                drop function %I.%I() cascade;
                drop function %I.%I() cascade;',
                p_schema, p_table_name, p_schema, v_trigger_name);

        -- drop the functions
        execute v_drop_statements;
end;
$$ language plpgsql set client_min_messages to error;
