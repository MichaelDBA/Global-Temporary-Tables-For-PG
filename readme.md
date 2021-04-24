# Global Temporary Tables For PostgreSQL

(c) 2021 SQLEXEC LLC
<br/>
GNU V3 and MIT licenses are conveyed accordingly.
<br/>
Bugs can be reported @ michaeldba@sqlexec.com

The main goal of this repo is to provide Oracle-like functionality with respect to Global Temporary Tables.  This comes into play a lot when migrating from Oracle to PostgreSQL.  The SQL file attached to this repo contains all that is needed to simulate Oracle GTTs in in PostgreSQL.  


## History
This repo is based on previous work done by Alexey Yakovlev, but which has not been updated since 2018.
https://www.codeproject.com/Articles/1176045/Oracle-style-global-temporary-tables-for-PostgreSQ
https://github.com/yallie/pg_global_temp_tables

I have made changes and added new features:
* temp table is not dropped after usage.  Instead, rows are simply truncated via ON COMMIT DELETE ROWS.
* user has a choice to make the temp table persistency apply within a transaction or within a connection session.


## Overview
There is currently a better solution for PostgreSQL global temporary tables written by Gilles Darold and available as a PostgreSQL extension.  Unfortunately, that does not help when working with PostgreSQL as a service, DBAAS.  There is no known cloud provider for PostgreSQL that supports this extension at this time.  Hence, the perceived need for this repo to fill in the gap.

## Requirements
None Required.  Just apply the 2 function definitions to the public schema of a target database.
<br/>

## Assumptions
None at this time.
<br/>

## Examples
The following commands will create 2 GTTs in a user-defined schema.  One is persistent within a transaction only, and the other one is persistent across all transactions within an existing connection.  This example simply copies info for active connections from the pg_stat_activity table.
<br/><br/>
set search_path = testing, public;
set client_min_messages = error;

Make sure GTTs don't already exist.
SELECT drop_permanent_temp_table(p_table_name => 'globaltemp1',p_schema => 'testing');
SELECT drop_permanent_temp_table(p_table_name => 'globaltemp2',p_schema => 'testing');

BEGIN;
CREATE TEMPORARY TABLE IF NOT EXISTS globaltemp1(pid integer PRIMARY KEY, datname name, usename name, state text, query text) ON COMMIT DELETE ROWS;
SELECT create_permanent_temp_table(p_schema => 'testing', p_table_name => 'globaltemp1', p_deleterows => True);   
END;

BEGIN;
CREATE TEMPORARY TABLE IF NOT EXISTS globaltemp2(pid integer PRIMARY KEY, datname name, usename name, state text, query text) ON COMMIT PRESERVE ROWS;
SELECT create_permanent_temp_table(p_schema => 'testing', p_table_name => 'globaltemp2', p_deleterows => False);   
END;

GRANT ALL on testing.globaltemp1 TO public;
GRANT ALL on testing.globaltemp2 TO public;




