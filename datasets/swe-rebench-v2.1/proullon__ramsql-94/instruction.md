I can't add in false values in an insert statement
I use this with sqlx primarily the "NamedExec" func. I can't insert false values into the db. It throws a syntax error.

I can enter in a true value. The "empty" value for a boolean is false. When a struct has an empty bool I can't add that value to the db.

#92
