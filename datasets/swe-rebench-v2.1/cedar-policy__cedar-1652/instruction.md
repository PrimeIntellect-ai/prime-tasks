Schema Validation for Storing Actions in Entities
### Category

Cedar validation features

### Describe the feature you'd like to request

Our application has a User entity and a Role entity. The Role entity contains a list of actions that users with that role are allowed to take. For instance, here is what the role entity looks like:
```
{
    "uid": {
        "type": "Role",
        "id": "admin"
    },
    "attrs": {
        "actions": [
             Action::"listSessions",
             Action::"deleteSession"
        ]
    }
}
```

and the Users have a role attribute like so:
```
{
    "uid": {
        "type": "User",
        "id": "user1"
    },
    "parents": [],
    "attrs": {
         "role": {
              "type": "Role",
              "id": "admin"
          }
     }
}
```

Our policies check if the action is allowed in the role like so:
```
permit (
    principal,
    action,
    resource
) when {
    action in principal.role.actions
};
```

The problem is that it isn't possible to validate the presence of the action list inside the role. Writing a Schema like
```
Role": {
    "shape": {
     "type": "Record",
      "attributes": {
        "actions": {
          "type": "Set",
          "element": {
            "type": "Entity",
            "name": "Action"
          }
        }
      }
    }
  },
```
produces an error `Undeclared entity types: {"Action"}`

It would be great if we could get an extension for the validator to allow us to list actions inside entities.

Thank you!

### Describe alternatives you've considered

We originally had the permissions for each user listed as Cedar policies, but having the permissions inside the Role entity allows us to quickly return what permissions a role has, as well as have a configuration file that defines every permission for each role.

### Additional context

_No response_

### Is this something that you'd be interested in working on?

- [ ] 👋 I may be able to implement this feature request
- [ ] ⚠️ This feature might incur a breaking change

### Additional contract requirements

- A schema may declare an entity attribute of type `Set<Action>`, and a policy may test membership of an action in that attribute, for example `action in principal.role.actions`, without the schema being rejected for an undeclared entity type.
- An action UID stored as a value in an entity attribute must refer to an action declared in the schema: entities whose attributes contain declared actions are accepted, and entities whose attributes contain undeclared action UIDs are rejected.
- An action UID given as a value in a request context must refer to an action declared in the schema: a request whose context contains a declared action is accepted, and a request whose context contains an undeclared action UID is rejected.
