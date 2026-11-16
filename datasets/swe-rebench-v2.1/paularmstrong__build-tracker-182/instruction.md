Sometimes the markdown table does not show hash changes when the web UI does
# Problem

Sometimes, the _unexpected hash change_ does not show up in the Markdown table, but it does show up in the web UI.

**Steps to Reproduce:**

If one of the delta sizes are zero, but not all, and the filename's hash changes.

**Expected Result**

They are expected to have the same behavior

**Actual Result**

The web UI shows a hash icon, but the markdown table will not

### Additional contract requirements

- `ArtifactDelta` (src/comparator/src/ArtifactDelta.ts) exposes a public boolean property `hashChangeUnexpected` that is `true` when the artifact's hash changed, there are no failing budgets, and every size delta is zero; otherwise it is `false`.
- The `DeltaCell` and `TotalDeltaCell` data structures (src/comparator/src/index.ts) expose a public boolean property `hashChangeUnexpected` that indicates whether the artifact's hash change was unexpected.
