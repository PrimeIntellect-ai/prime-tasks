Tsql table names with square brackets are not resolved correctly
Tsql:
When the same table name or column name has square brackets, the parsing result is considered to be two different objects, but it should actually be the same object.
Is there any configuration where I find that mysql backquotes can be parsed correctly

当相同的表名或列名有方括号时，解析结果认为是两个不同的对象，实际应该为同一个对象。
是有什么配置吗，我发现mysql的反引号是可以正确解析的

**SQL**
```sql
insert into [t1] select id from user_tab;
insert into t2 select id from t1
```

**shell**
```shell
sqllineage -e "insert into [t1] select id from user_tab;insert into t2 select id from t1" -d tsql
```

Current parsing
```
Statements(#): 2
Source Tables:
    <default>.t1
    <default>.user_tab
Target Tables:
    <default>.[t1]
    <default>.t2
```

Correct parsing
```
Statements(#): 2
Source Tables:
    <default>.user_tab
Target Tables:
    <default>.t2
Intermediate Tables:
    <default>.t1
```

**Python version (available via `python --version`)**
 - 3.12.1

**SQLLineage version (available via `sqllineage --version`):**
 - 1.5.1
