Initial timestamp
Hi @goldibex thanks for writing and maintaning this lib, it is awesome.

I have a small issue that I was wondering if you might be able to help me solve.

I have a validation rule
```
type InitialTimestamp extends Number {
  validate() { initial(this, now) }
}
// Returns true if the value is intialized to init, or if it retains it's prior value, otherwise.
initial(value, init) { value == (prior(value) == null ? init : prior(value)) }

```
```
type UserProfile {
  email: String
  signupDate: InitialTimestamp
}
```
The data im using for the write test is like so:
```
userProfile =
  email: 'testUser@test123.com'
  splitType: 'auto'
  signupDate: { ".sv": "timestamp" }

expect(uid:userUID).can.write({userProfile}).to.path userProfilePath + "/#{userUID}"
```

When inforcing this inside of targaryen it seems like there is a timing issue because it rejects it.

```
 be able to write {"email":"testUser@test123.com","splitType":"auto","signupDate":1463817931069} to /user/profiles/2d7fda85-6ef7-495f-a70b-2e05ccda6e9e, but the rules denied the write.
/user/profiles/2d7fda85-6ef7-495f-a70b-2e05ccda6e9e:.write: "auth != null && auth.uid == $uid"
    => true
/user/profiles/2d7fda85-6ef7-495f-a70b-2e05ccda6e9e:.validate: "newData.hasChildren(['email', 'signupDate'])"
    => true
/user/profiles/2d7fda85-6ef7-495f-a70b-2e05ccda6e9e/email:.validate: "newData.isString()"
    => true
/user/profiles/2d7fda85-6ef7-495f-a70b-2e05ccda6e9e/signupDate:.validate: "newData.isNumber() && newData.val() == (data.val() == null ? now : data.val())"
    => false
Validation failed.
Write was denied.
```

If I change the rule to (less than current time on server):

```
initial(value, init) { value <= (prior(value) == null ? init : prior(value)) }
```

It passes. So I can see in the source that targaryen converts ```{ ".sv": "timestamp" }``` to ```Date.now()``` but I cannot find where it enforces that rule and if it is generating another time at a later point and trying to compare them.

Cheers for any help, Jake

Edit:
It must be comparing these two dates
https://github.com/goldibex/targaryen/blob/6f39c7ee95070e6fcbb1008065876a1e399e2b8c/lib/rule-data-snapshot.js#L37

https://github.com/goldibex/targaryen/blob/6f39c7ee95070e6fcbb1008065876a1e399e2b8c/lib/ruleset.js#L175
