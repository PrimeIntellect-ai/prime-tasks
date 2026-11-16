Add matcher for query arguments in ACL rules
## Bug Report

### Description

I am attempting to restrict access to resource which due to the nature of application requires me to match an GET argument. Now the first ACL ruleset I sketched was following:

```
    - domain: app.example.com
      subject: "group:Admins"
      resources:
      - "^/path/to/\\?key=sensitive-page"

    - domain: app.example.com
      policy: deny
      resources:
      - "^/path/to/\\?key=sensitive-page"

    - domain: app.example.com
      policy: bypass
```

Now the problem is that user can manipulate the order of GET arguments so first two rules are not matched, and `key=sensitive-page` resource would be matched by the last ACL rule.

### Expected Behaviour

I think the only realistic option here is to allow Authelia to parse and sanitize the GET arguments and have separate section for matching GET arguments a'a like this:

```
    - domain: app.example.com
      subject: "group:Admins"
      arguments:
         key: "^sensitive-page"
```

Expecting Authelia admin to come up with all the various ways URL can be constructed is not realistic.

### Additional contract requirements

- Access control rules support a `query` option that matches request query parameters. In the configuration schema,
  `schema.ACLRule` has a `Query [][]schema.ACLQueryRule` field, and `schema.ACLQueryRule` has the fields
  `Operator string`, `Key string`, and `Value any`.
- The supported query operators are `present`, `absent`, `equal`, `not equal`, `pattern`, and `not pattern`.
- Query criteria are a list of OR-groups, where each OR-group is a list of criteria combined with logical AND. A
  rule's query criteria match a request when at least one OR-group matches, and an OR-group matches when all of its
  criteria match.
- `present` matches when the named query parameter is present with any value, and `absent` matches when it is not
  present. `equal` and `not equal` compare the parameter value to the configured string value. `pattern` and
  `not pattern` match the parameter value against a regular expression; the configured value for these operators is a
  compiled regular expression (`*regexp.Regexp`).
- A query rule that is malformed (for example an unsupported operator, a missing key, a missing value for `equal`, or
  an invalid regular expression for `pattern`) is rejected during configuration validation.
