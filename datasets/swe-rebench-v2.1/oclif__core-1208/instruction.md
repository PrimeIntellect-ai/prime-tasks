Warning mistakenly displayed when using a flag that starts with a deprecated alias
**Describe the bug**
While working on a Salesforce CLI plugin I ran into the following bug regarding deprecated flag warning messages.

Given a flag, `foo-bar` is added to a command and has an `alias`, `foo` and the flag is configured with `deprecateAliases: true`, when executing the command with `--foo` the deprecated flag warning message is displayed as expected.

However, when executing the command with  `--foo-bar` the deprecated flag warning message is displayed saying:
> Warning: The "--foo" flag has been deprecated. Use "--foo-bar" instead.

**To Reproduce**
Steps to reproduce the behavior:
1. Add a flag to a command with configuration as follows:
```typescript
    'foo-bar': Flags.boolean({
      summary: 'summary',
      deprecateAliases: true,
      aliases: ['foo']
    }),
```
2.  Execute the command with flag `--foo-bar`
```
$ ./bin/dev.js mycommand --foo-bar
```
3. Warning is displayed
> Warning: The "--foo" flag has been deprecated. Use "--foo-bar" instead.

**Expected behavior**
Warning should not be displayed when `--foo-bar` flag is used as the flag is not marked as deprecated, only the alias flag `--foo` should be considered deprecated.

**Environment (please complete the following information):**
 - OS & version: Ubuntu 22.04.5 LTS
 - Shell/terminal & version zsh 5.8.1 (x86_64-ubuntu-linux-gnu)

`package.json` dependencies
```json
  "dependencies": {
    "@jsforce/jsforce-node": "^3.4.1",
    "@oclif/core": "^4.0.19",
    "@salesforce/apex-node": "^8.1.4",
    "@salesforce/core": "^8.4.0",
    "@salesforce/sf-plugins-core": "^11.3.6",
    "@salesforce/ts-types": "^2.0.10"
  },
  "devDependencies": {
    "@oclif/plugin-command-snapshot": "^5.2.8",
    "@salesforce/cli-plugins-testkit": "^5.3.19",
    "@salesforce/dev-scripts": "^10.2.9",
    "@salesforce/ts-sinon": "^1.4.24",
    "@types/node": "^22.4.0",
    "@types/sinon-chai": "^3.2.12",
    "eslint": "^8.56.0",
    "eslint-plugin-sf-plugin": "^1.19.0",
    "oclif": "^4.14.8",
    "prettier": "^3.3.3",
    "pretty-quick": "^4.0.0",
    "sinon-chai": "^4.0.0",
    "ts-node": "^10.9.2",
    "typedoc": "^0.26.5",
    "typescript": "^5.4.5"
  },

```
**Additional context**
[HIDDEN]
