"filtertype: kibana" does not work with Kibana indexes migrated from 5.x to 6.x
### Expected Behavior
`filtertype: kibana` should match `.kibana-6` index with `.kibana` alias.

### Actual Behavior
`filtertype: kibana` does not match `.kibana-6` index with `.kibana` alias.

### Steps to Reproduce the Problem
  1. Run steps 2 and 4 from [Migrating Kibana index to 6.0][1]
  1. Run an action with `filtertype: kibana` (E.g. `curator_cli  show_indices --filter_list '{"filtertype":"kibana"}'`)
  1. `.kibana-6` should be excluded

### Specifications

  - Version: Curator 5.4.0, ES+Kibana 6.2.2
  - Platform: [Docker][2]

## Context (Environment)
We migrated our Kibana index according to the [Migrating Kibana index to 6.0][1] guide. Using `filtertype: kibana` no longer works after the migration. This is likely because the actual index was renamed to `.kibana-6` and `.kibana` is now an alias, not an index.

## Detailed Description
The filter should either include indexes with a suffix after the initial `.kibana`, or it should also match any index pointed to by the `.kibana` alias.

As a workaround we're using:
```
- filtertype: pattern
  kind: regex
  value: '^\.kibana.*$'
```

[1]: https://www.elastic.co/guide/en/kibana/current/migrating-6.0-index.html
[2]: https://hub.docker.com/r/bobrik/curator/
