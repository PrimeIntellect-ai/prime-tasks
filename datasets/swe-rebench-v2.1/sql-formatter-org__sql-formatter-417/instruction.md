Regression with the token PRECEDING with version 10 for bigquery formatting
**Describe the bug**
There seems to be a regression in what is supported by sql-formatter for the bigquery SQL language.

**Expected behavior**
I expected the version 10 to still support the token PRECEDING.

**Actual behavior**

I got the following error :
<img width="1448" alt="187225626-99e10276-3d9e-49a1-914e-4015bfc19f6d" src="https://user-images.githubusercontent.com/1980396/187443697-c61a7e49-a384-467d-9992-06cd61eec8e3.png">

**Usage**

- How are you calling / using the library?
```
format(sql, {
    language: 'bigquery',
});
```
- What SQL language(s) does this apply to?
 bigquery
- Which SQL Formatter version are you using?
10

### Additional contract requirements

- For BigQuery, queries using a window-frame clause such as `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` must format successfully. `PRECEDING` must be accepted and retained in the formatted SQL.
