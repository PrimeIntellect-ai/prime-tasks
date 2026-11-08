Explicit error message asking for an updated tslint version
### 🚀 Feature Request

Following #106: if a project has explicitly set their `tslint` dependency too low, they might still get the `unknown option '--print-config'` complaint.

#### Existing Behavior

Output from `npx tslint-to-eslint-config`:

```
❌ Could not start tslint-to-eslint: ❌
Command failed: tslint --print-config "./tslint.json"
error: unknown option `--print-config'
```

#### Change Proposal

If the error from TSLint is this very specific one, change it to:

```
❌ Could not start tslint-to-eslint: ❌
TSLint v5.18 required. Please update your version.
```
