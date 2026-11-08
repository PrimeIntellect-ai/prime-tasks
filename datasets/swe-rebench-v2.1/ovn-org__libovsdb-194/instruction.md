`Where(...).Update(...)` throws server side OVS DB error: `syntax error: Member 'where' is present but not allowed here.`
Whenever a client performs an `Update` on an object using `Where*` (i.e: `Where`/ `WhereAll`/ `WhereCache`) the operation is invalidated on the OVS DB server's side. The error message presented is: `syntax error: Parsing ovsdb operation 1 of 1 failed: Member 'where' is present but not allowed here.`

This is the following operation causing this error:

```
o: [{Op:insert Table:Load_Balancer Row:map[name:alex-hi] Rows:[] Columns:[] Mutations:[] Timeout:0 Where:[where column _uuid == {9fc3c02e-7bf8-4d5b-8a14-82257597e221}] Until: Durable:<nil> Comment:<nil> Lock:<nil> UUIDName:}]
```

By nullifying `.Where`, the operation passes...but that results in a `Create`.

Let me know if you need more information.

/assign @amorenoz
