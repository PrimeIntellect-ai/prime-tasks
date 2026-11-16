Template literals with callbacks
I had to monkey patch Request to use template literals with callbacks

```
[HIDDEN]
```

This allows me to do this:

```
let hw='hello world';
let request=new mssql.Request(pool);
request.query(request.template`SELECT ${hw}`,(err,result)=>{
    if(err){done(err); return;}
    console.log(result.recordset);
});
```

It would be nice if something like this would be included so that those of us trying to avoid promises can use template literals.

### Additional contract requirements

Each interpolation in a tagged template must be represented by its own SQL parameter, with the corresponding value available to the request when that SQL is executed. SQL returned by `Request.template` must be usable with the callback form of `Request.query`, with query completion reported through the callback.
