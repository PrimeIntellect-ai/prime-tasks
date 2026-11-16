Update sync project master controller
Update sync project controller to support multiple project owners during project creation.
The endpoint to create a project by SA can pass a list of the human user owners:
```
POST http://localhost:8080/api/v1/projects


{"name":"test","users":["user1@kubermatic.com", "user2@kubermatic.com", "user3@kubermatic.com"]}
```
The sync project controller expects only one owner. Make all necessary changes to support multiple project owners.

### Additional contract requirements

When a project has multiple owner references, the controller creates an owner binding for each owner reference that resolves to an existing User object. An owner reference that does not resolve to an existing User object is skipped: no binding is created for it and no error is returned.
