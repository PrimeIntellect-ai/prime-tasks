Wrap API objects that are used by the command module
Off the top of my head, this should just be repository, team and issue objects (that are currently represented as `tuples.Repo` and `tuples.Team` and `tuples.Issue`). The reason to create other wrappers is that it's very possible that the platform APIs need to access implementation specific things, so these wrappers must have a `implementation` property that can be accessed wherever necessary (should just be in the platform API classes)

This will also allow for concisely documenting the behavior of the APISpec methods, see #191

### Additional contract requirements

The platform-agnostic wrappers are public classes in the `repobee.apimeta`
module. Each is an immutable namedtuple that exposes an `implementation`
field holding the raw platform-specific object it was created from, or `None`
when no such object is supplied.

- `apimeta.Issue(title, body, number=None, created_at=None, author=None, implementation=None)`
  with fields `(title, body, number, created_at, author, implementation)`.
- `apimeta.Team(members, name=None, id=None, implementation=None)` with fields
  `(name, members, id, implementation)`.
- `apimeta.Repo(name, description, private, team_id=None, url=None, implementation=None)`
  with fields `(name, description, private, team_id, url, implementation)`.
