# Global Temporary Tables For PostgreSQL

(c) 2021 SQLEXEC LLC
<br/>
GNU V3 and MIT licenses are conveyed accordingly.
<br/>
Bugs can be reported @ michaeldba@sqlexec.com

The main goal of this repo is to provide Oracle-like functionality with respect to Global Temporary Tables.  This comes into play a lot when migrating from Oracle to PostgreSQL.  The SQL file attached to this repo contains all that is needed to simulate Oracle GTTs in in PostgreSQL.  
<br/>

## History
This repo is based on previous work done by Alexey Yakovlev, but which has not been updated since 2018.
https://www.codeproject.com/Articles/1176045/Oracle-style-global-temporary-tables-for-PostgreSQ
https://github.com/yallie/pg_global_temp_tables
<br/>
I have made changes and added new features:
* temp table is not dropped after usage.  Instead, rows are simply truncated via ON COMMIT DELETE ROWS.
* user has a choice to make the temp table persistency apply within a transaction or within a connection session.
<br/>

## Overview
There is currently a better solution for PostgreSQL global temporary tables written by Gilles Darold and available as a PostgreSQL extension. 
<br/>
See https://github.com/darold/pgtt
<br/><br/>
Unfortunately, that does not help when working with PostgreSQL as a service, DBAAS.  There is no known cloud provider for PostgreSQL that supports this extension at this time.  Hence, the perceived need for this repo to fill in the gap.
<br/><br/>
How does it work? When you invoke the public function, create_permanent_temp_table(), it creates 3 things: a view, a function, and a trigger function.  The view calls the function. The view selects rows from the function, and we can make it updatable by means of the instead of trigger.  You never see the actual temp table, since it is actually, the view name concatenated with "$tmp".
<br/>
<br/>
## Requirements
None Required.  Just apply the 2 function definitions to the public schema of a target database.
<br/>

## Assumptions
None at this time.
<br/>

## Example 1: Create the user-defined GTTs
The following commands will create 2 GTTs in a user-defined schema.  One is persistent within a transaction only, and the other one is persistent across all transactions within an existing connection.  This example simply copies info for active connections from the pg_stat_activity table.
<br/><br/>
`set search_path = testing, public;`<br/>
`set client_min_messages = error;`
<br/><br/>
Make sure GTTs don't already exist.<br/>
`SELECT drop_permanent_temp_table(p_table_name => 'globaltemp1',p_schema => 'testing');`<br/>
`SELECT drop_permanent_temp_table(p_table_name => 'globaltemp2',p_schema => 'testing');`
<br/><br/>
`BEGIN;`<br/>
`CREATE TEMPORARY TABLE IF NOT EXISTS globaltemp1(pid integer PRIMARY KEY, datname name, usename name, state text, query text) ON COMMIT DELETE ROWS;`<br/>
`SELECT create_permanent_temp_table(p_schema => 'testing', p_table_name => 'globaltemp1', p_deleterows => True);`<br/>
`END;`
<br/><br/>
`BEGIN;`<br/>
`CREATE TEMPORARY TABLE IF NOT EXISTS globaltemp2(pid integer PRIMARY KEY, datname name, usename name, state text, query text) ON COMMIT PRESERVE ROWS;`<br/>
`SELECT create_permanent_temp_table(p_schema => 'testing', p_table_name => 'globaltemp2', p_deleterows => False);`<br/>
`END;`
<br/><br/>
`GRANT ALL on testing.globaltemp1 TO public;`<br/>
`GRANT ALL on testing.globaltemp2 TO public;`
<br/><br/>
## Example 2: Work with the transaction persistent user-defined GTT
Show search path<br/>
`show search_path;`<br/>
   search_path<br/>
-----------------<br/>
 "$user", public
<br/><br/>
Query 1st temp table<br/>
`select * from globaltemp1;`<br/>
ERROR:  relation "globaltemp1" does not exist<br/>
LINE 1: select * from globaltemp1;<br/>
                      ^
<br/><br/>                      
Search path needs to be modified to point to user schema<br/>
`set search_path = testing, public;`<br/>
SET
<br/><br/>
See if we can see the GTT now<br/>
`select * from globaltemp1;`<br/>
 pid | datname | usename | state | query<br/>
-----+---------+---------+-------+-------<br/>
(0 rows)
<br/><br/>
Put something in the GTT<br/>
`INSERT INTO globaltemp1 (select pid, datname, usename, state, query from pg_stat_activity where state = 'active');`<br/>
INSERT 0 1
<br/><br/>
1 row was inserted, let's check our GTT again<br/>
`select * from globaltemp1;`<br/>
 pid | datname | usename | state | query<br/>
-----+---------+---------+-------+-------<br/>
(0 rows)
<br/><br/>
As expected, the changes to our temporary table only live for the life of the transaction.<br/>
Let's modify our temp table and query it again within a transaction.<br/>
`BEGIN;`<br/>
BEGIN
<br/><br/>
`INSERT INTO globaltemp1 (select pid, datname, usename, state, query from pg_stat_activity where state = 'active');`<br/>
INSERT 0 1
<br/><br/>
`select * from globaltemp1;`<br/>
 pid  |   datname   | usename  | state  |                                                       query<br/>
------+-------------+----------+--------+------------------------------------------------------------------------------------------------------------------<br/>
 2264 | gtt_testing | postgres | active | INSERT INTO globaltemp1 (select pid, datname, usename, state, query from pg_stat_activity where state = 'active');<br/>
(1 row)
<br/><br/>
`commit;`<br/>
COMMIT
<br/><br/>
As expected, the GTT still exists but it is empty again.<br/>
`select * from globaltemp1;`<br/>
 pid | datname | usename | state | query<br/>
-----+---------+---------+-------+-------<br/>
(0 rows)
<br/><br/>

