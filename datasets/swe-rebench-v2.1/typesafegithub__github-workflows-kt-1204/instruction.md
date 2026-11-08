Implement fallback for using typings for older major version
Let's say the action doesn't provide typings, and we maintain typings for v2 and v3. When v4 comes, in practice it's often the case that we can reuse the typings from v3. If some inputs are missing, we could default to string.

### Additional contract requirements

When typings for a newer major version are unavailable and typings from an older major version in the catalog are reused, any input declared by the action but not covered by those typings must be treated as a string when generating its binding. If typings are available for multiple older major versions, use the closest older major version. The catalog advertises which versions have typings in a `metadata.yml` file stored next to the action's version directories in the typings catalog, under the key `versionsWithTypings`, which is a list of version names such as `v2`.
