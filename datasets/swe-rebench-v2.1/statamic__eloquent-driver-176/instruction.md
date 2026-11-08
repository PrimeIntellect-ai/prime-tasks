The offset parameter does not work on collections
When I try this:
```
{{ collection:articles offset="1" }}
  {{ partial src="partials/article_teaser" }}
{{ /collection:articles }}
```
it throws an error, and I think the problem is the way the SQL query is built:
```
select * from `entries` where `collection` in (articles) and `status` = published and `date` < 2023-06-21 23:35:12 and (json_extract(`data`, '$."redirect"') is null OR json_type(json_extract(`data`, '$."redirect"')) = 'NULL') order by json_unquote(json_extract(`data`, '$."title"')) desc offset 1
```
The error is:
**SQLSTATE[42000]: Syntax error or access violation: 1064 You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near 'offset 1' at line 1**

Here is the setup:
Environment
Application Name: xxx
Laravel Version: 9.52.7
PHP Version: 8.1.17
Composer Version: 2.5.5
Environment: local
Debug Mode: ENABLED
URL: xxx.test
Maintenance Mode: OFF

Cache
Config: NOT CACHED
Events: NOT CACHED
Routes: NOT CACHED
Views: CACHED

Drivers
Broadcasting: log
Cache: statamic
Database: mysql
Logs: stack / single
Mail: smtp
Queue: sync
Session: file

Statamic
Addons: 6
Antlers: runtime
Stache Watcher: Enabled
Static Caching: Disabled
Version: 3.4.11 PRO

Statamic Addons
aryehraber/statamic-captcha: 1.10.0
properti/estate-items-import: dev-main
properti/properti-dashboard: dev-main
r8edge/imagemap: dev-main
r8edge/welcome-widget: dev-main
statamic/eloquent-driver: 1.2.0
