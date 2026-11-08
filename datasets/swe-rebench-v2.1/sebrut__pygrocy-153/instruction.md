Better error messages
In ha with the component I only get these error messages, no matter what the reason for the 400 is.
```
requests.exceptions.HTTPError: 400 Client Error: Bad Request for url: http://192.168.1.78:9192/api/objects/tasks
```

Grocy is however also sending an error_message, like this:
```
"{\"error_message\":\"SQLSTATE[23000]: Integrity constraint violation: 19 UNIQUE constraint failed: tasks.name\"}"

It would be awesome to get these in the error message from the lib too.
```

### Additional contract requirements

- When Grocy answers a request with a 400 response whose body contains an `error_message`, the exception the library raises for that request must make that exact server-provided text available to the caller: it must appear in `str()` of the exception, or be exposed through a `message` attribute of the exception.
- Any Grocy response with a status of 400 or higher must cause an exception to be raised.
