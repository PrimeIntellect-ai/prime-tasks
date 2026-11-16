auth uids with periods break validation rules
".validate" rules are not respected when the auth uid has a period in it. For instance:

```javascript
const targaryen = require('targaryen');
// Note that "firstSignIn" must be a number
const rules = {
  rules: {
    ".write": true,
    ".read": true,
    users: {
      '$uid': {
        activity: {
          firstSignIn: {
            '.validate': 'newData.isNumber()'
          }
        }
      }
    }
  }
};
const user = { uid: 'foo.bar' };
const data = { users: { } };
const path = `/users/${user.uid}/activity/firstSignIn`;
const database = targaryen.database(rules, data).as(user).with({debug: true});
const result = database.write(path, 'notAnumber,shouldFail');
console.log(result.validated) // -> true
```

However if you change the above user to be "foobar", result.validated will correctly return "false".

I encountered this as I was creating dummy users using Math.random() for the uid, which is easy enough to work around, but it was a headache to track down why this is happening.
