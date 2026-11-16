email not working with attributes query anymore
Providing the attributes filter in the 1.3.0 version doesn't return the emails anymore.

GET `?attributes=userName,emails` will only return id and userName.
