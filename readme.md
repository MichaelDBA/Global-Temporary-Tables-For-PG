# optimize_db

This python program determines whether a vacuum/analyze/freeze should be done and if so, which one.

(c) 2018-2020 SQLEXEC LLC
<br/>
GNU V3 and MIT licenses are conveyed accordingly.
<br/>
Bugs can be reported @ michaeldba@sqlexec.com


## History
The first version of this program was created in 2018.  

## Overview
This program is useful to identify and vacuum tables.  Most inputs are optional, and either an optional parameter is not used or a default value is used if not provided.  That means you can override internal parameters by specifying them on the command line.  Here are the parameters:
<br/>
-H --host     host name
-d --dbname       database name
-p --dbport       database port
-u --dbuser       database user
-m --maxsize      max table size that will be considered
-y --maxdays      vacuums/analyzes older than max days will be considered
-t --mindeadtups  minimum dead tups before considering a vacuum
-m --schema       if provided, perform actions only on this schema
-f --freeze       perform freeze if necessary
-r --dryrun       do a dry run for analysis before actually running it.
<br/>

## Requirements
1. python 2.7 or above
2. python packages: psycopg2
<br/>

## Examples
optimize_db.py -H localhost -d testing -p 5432 -u postgres --maxsize 400000000000 --maxdays 1 --mindeadtups 1000 --schema public --dryrun
optimize_db.py -H localhost -d testing -p 5432 -u postgres -s 400000000000 -y 1 -t 1000 -m public --freeze
