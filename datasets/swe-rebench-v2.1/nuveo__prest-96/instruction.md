"invalid where clause" when using file with extension in the where
- pREST version (or commit ref): 0a1c7bcdb3b2e2bd4dc82d1e881432b56b8bab25
- pREST endpoint: /database/public/tablename
- PostgreSQL version: 9.6.1.0
- Operating system: macOS Sierra
- Go version: 1.7
- Log gist:

## Description

When I search for filenames that are registered in a field of a table the pREST gets confused because of the dot and the extension in the filename and return "invalid where clause".

Example of how to reproduce:
```
curl -i -X GET http://localhost:3000/database/public/tablename?local_file=teste.txt
```

I believe the error is happening because of the way the new where operators are coded.
A dot can occur in any string so this seems to be a bug.
