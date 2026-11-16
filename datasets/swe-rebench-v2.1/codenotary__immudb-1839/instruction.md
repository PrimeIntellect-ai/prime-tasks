openSession method does not lower the databaseName.
<!-- Please use this template while reporting a bug and provide as much info as possible.
If applicable, add shell logs or screenshots to help explain your problem.
Thanks! -->

**What happened**
I'm currently using the SDK immudb4j.
I tried to open a session (defaultdb, immudb, immudb).
Then create a new database.
Close the session.
And open a new one with the new DB.

----------------------------------------------------------------------------------

immuClient.openSession("defaultdb", "immudb", "immudb");

immuClient.createDatabase("hG82t45Plm", true);

immuClient.closeSession();

immuClient.openSession("hG82t45Plm", "immudb", "immudb");

**Database name are case sensitive or more precisely the are  create in lowercase**
**The createDatabase method lower the string "hG82t45Plm"**
**But the openSession method does not**
**So there is an Exception : _UNKNOWN: database does not exist_**

----------------------------------------------------------------------------------

**What you expected to happen**

I do not really know if it is a bug or not  but we can expect the method openSession, as the createDatabase, lower the Database name field.

**How to reproduce it (as minimally and precisely as possible)**

**Environment**
```shell
# run "immu* [v1.4.1]" and copy/paste the output here
```

**Additional info (any other context about the problem)**

### Additional contract requirements

When a non-administrator has permission for a database, opening a session using a differently cased spelling of that database must still be permitted. The database name used for the permission check must be normalized consistently with the name used to resolve the database.
