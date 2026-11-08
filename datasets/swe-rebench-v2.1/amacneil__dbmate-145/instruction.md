Credentials are leaked to stderr when database URL is malformed
Let's say I give Dbmate a malformed database URL. In this case, it has a base64-encoded password which I forgot to properly URL-encode.
```bash
export DATABASE_URL=mysql://username:otS33+tb/e4=@localhost:3306/database
```
If I run `dbmate up`, I get the following output to stderr:
```
Error: parse "mysql://username:otS33+tb/e4=@localhost:3306/database": invalid port ":otS33+tb" after host
```
This leaks the database credentials to stderr, which could be problematic if stderr is being logged somewhere. I ran into this problem when trying to run Dbmate in a serverless function, which is a reasonable use-case for accessing a database which might be locked behind a VPC.

Do you think it's reasonable to mask the database credentials in the output?
