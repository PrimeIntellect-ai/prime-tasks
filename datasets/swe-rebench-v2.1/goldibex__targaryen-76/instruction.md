Nested objects within auth not working.
I've created a simple test that fails in targaryen, but passes on firebase simulator.

###### Test:

```json
{
  "root": {
    "chats": {
      "chat-01": {
        "orgID": "org-01"
      }
    }
  },

  "users": {
    "user01": {
      "uid": "user-01",
      "orgs": {
        "org-01": true
      }
    }
  },

  "tests": {
    "chats/chat-01": {
      "canRead": [ "user01" ]
    }
  }
}
```

###### Rules:

```json
{
  "rules": {
    "chats": {
      "$chatID": {
        ".read": "root.child('chats').child($chatID).child('orgID').val() != null && auth.orgs != null && auth.orgs[root.child('chats').child($chatID).child('orgID').val()] == true"
      }
    }
  }
}
```

For easier reading, here's the rule pretty-printed:

```
root.child('chats').child($chatID).child('orgID').val() != null
&&
auth.orgs != null
&&
auth.orgs[ root.child('chats').child($chatID).child('orgID').val() ] == true
```
