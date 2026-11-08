Allow comparison between scopes
Mastodon documentation states that a requested scope may be a subset of a previously allowed scope. For example, an application might be created with the scope `read`, but a specific access token later requested by the app for a specific user might be restricted to `read:accounts`.

It would be useful to be able to compare different of our `Scope` objects (e.g. find out if requesting a `read:accounts` access token will even be successful given what scope set our application was created with in the first place). To be able to do that, I'd like to add the following functions to our `Scope` class:

- `contains(scopeName: Scope.Name)`, returning true if the scope contains the individual scopeName
- `isSubsetOf(otherScope: Scope)`, returning true if otherScope has at least all of our permissions
- `Scope.fromString(scopeString: String)`, allowing the creation of a Scope object from the string representation returned by Mastodon
