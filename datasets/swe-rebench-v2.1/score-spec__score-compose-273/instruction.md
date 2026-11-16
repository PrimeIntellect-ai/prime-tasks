[feature request] Add a `description` field for the provisioners
To improve how PEs document their provisioners and expose them to their Devs, it would be better to have a `description` field in the provisioners files.

Today, if we add this field in the provisioners files, we get this error:
```
Error: failed to save provisioner 1: invalid provisioners file: 0: cmd://python3#dotenv: failed to parse: yaml: unmarshal errors:
  line 9: field description not found in type cmdprov.Provisioner
```

Rough list of things to do to implement this:
- Support this field in the `cmdprov.Provisioner` and `templateprov.Provisioner` and other places where needed
- Update all the current default provisioners with their description
- Update `score-compose provisioners list` to display by default this new `description` field

This field should be optional, to avoid any breaking changes with existing/current provisioners.

Note: here is an example of how this could be used: https://github.com/score-spec/community-provisioners/pull/8

### Additional contract requirements

- The `score-compose provisioners list` command must display the description field by default in both output formats. In the default table output the column header is `Description` (rendered uppercase as `DESCRIPTION`), and in the JSON output the field is named `Description`.
