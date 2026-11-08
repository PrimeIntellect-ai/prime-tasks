Mismatch of steps and table names in report when launch data driven spec in multithreading
Mismatch within steps and names in the table in the report after running data-driven specifications in multiple threads. The issue appears after upgrade from 1.0.6 to 1.0.8.

**Expected behavior**
Table data in report and steps bellow should be matched to each other

**Steps to reproduce:**
- create data-driven spec with using data from table in step name
- run it multiple threads
- get report
- compare names in the table above and steps bellow

**Versions**
_Configuration when the issue reproduced:_
Gauge version: 1.0.8
Commit Hash: 28617ea
html-report (4.0.10) or lower (also checked with 4.0.6 and 4.0.3)
java (0.7.4) or 0.7.3
screenshot (0.0.1)
spectacle (0.1.3)
xml-report (0.2.2)

_Configuration when the issue didn't reproduce:_
Gauge version: 1.0.6
Commit Hash: 2bc49db
html-report (4.0.6)
java (0.7.3)
screenshot (0.0.1)
spectacle (0.1.3)
xml-report (0.2.2)


**Comands**
gauge:execute
-Dtags=%gauge.tags%
-DinParallel=true
-Dnodes=%parallel.threads%
-DspecsDir=%specsDir%

**Environment**
Ubuntu 18.04.3 LTS (GNU/Linux 4.15.0-76-generic x86_64)
