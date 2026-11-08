Subvalidations do not seem to be working
Firstly, thanks for this package, it will help me a lot in development.

I have a rule something like

```
     "invites": {
        "pending": {
          "$invite_id": {
            ".validate": "newData.hasChildren(['bookID', 'email', 'ownerID', 'status'])",
            ".write": "auth.uid === newData.child('ownerID').val()",
            "bookID": {
              ".validate": "newData.isString()"
            },
            "email": {
              ".validate": "newData.isString()"
            },
            "ownerID": {
              ".validate": "newData.isString()"
            },
            "status": {
              ".validate": "newData.isString()"
            },
            "$other": {
              ".validate": "false"
            }
          }
        }
```

When using the Firebase simulator, a write of `{ bookID: 'hey', email: 5, ownerID: 'simplelogin:3', status: 'hey' }` (note the `email` field being a non-string) to `invites/pending/invite_id` as the `simplelogin:3` user does not succeed.

However using the Targaryen test suite (using the CLI) a 'cannotWrite' fails (i.e. it *does* succeed, and the test fails).

```
  "tests": {
    "invites/pending/invite_id": {
      "cannotWrite": [
        { "auth": "John Brown", "data": { "ownerID": "simplelogin:3" } },
        { "auth": "John Brown", "data": {
            "ownerID": "simplelogin:3",
            "bookID": "hey",
            "email": 5,
            "status": "sent"
          }
        }
      ]
    }
```

I'm not sure if I'm doing something wrong, whether I should be using Jasmine instead because it's too complicated, or if this is an issue with the test suite.  Let me know, thanks :)

Edit:

I should add that other tests succeed at this location, like cannotWrite for users which aren't `simplelogin:3` and canWrite for users who are `simplelogin:3`.

Also,  the '$other' validation doesn't seem to be recognized by the test suite either - when I add an additional field, the suite expects it to succeed even though it should fail (verified with simulator).
