[FORMATTING] postgresql timestamp datatype on create table adds unnecessary newline
**Input data**
Which SQL and options did you provide as input?

```sql
create table test (
	a int,
	b int,
	c TIMESTAMP with time zone,
	d int
);
```

**Expected Output**

```sql
CREATE    TABLE test (
                    a INT,
                    b INT,
                    c TIMESTAMP WITH TIME ZONE,
                    d INT
                    );
```

**Actual Output**

```sql
CREATE    TABLE test (
                    a INT,
                    b INT,
                    c TIMESTAMP
                    WITH      TIME ZONE,
                              d INT
                    );
```

**Usage**

- How are you calling / using the library? By coc-sql
- What SQL language(s) does this apply to? postgresql
- Which SQL Formatter version are you using? latest with coc-sql
