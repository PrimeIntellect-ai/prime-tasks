Support OAS3.1 for joining
**Is your feature request related to a problem? Please describe.**

Currently, all features except "join" support OAS3.1.
I am considering changing the openapi version from OAS3.0 to OAS3.1, but join is causing the following error.

```
Only OpenAPI 3 is supported: /home/mibe/git/rcp/sbc-api-doc/openapi/v1/favorite_robots.yaml
```

**Describe the solution you'd like**

When I run join, it only checks for OAS3.0, but please include OAS3.1 as well.

https://github.com/Redocly/redocly-cli/blob/28e7e8308fd0ba6380cf2a2b3a4b5f10115322f3/packages/cli/src/commands/join.ts#L122-L126
