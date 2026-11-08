Graph: Consistently add user attributes to LDAP add request
In `identity.LDAP.userToAddRequest` attributes are added via a map, and as maps aren't a sorted type, it makes it very hard to test the input of the mock.

Make the attribute addition predictable so that the mock doesn't need to use the Anything instance.

### Additional contract requirements

- Add attributes to the LDAP add request in this order: the configured display-name, username, email, surname, and given-name attributes, followed by `objectClass`, `cn`, `owncloudUUID`, and `userPassword`, omitting attributes that are not present.
