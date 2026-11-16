bug: `rename_all` cannot be used with unit or tuple structs
**Describe the bug**
AFAICT this is the same as #403, but it's still present in 11.0.1 (the fix for that was merged before 11.0.0 afaict).

**To Reproduce**
```
#[derive(Serialize, Deserialize, Clone, Debug, Hash, JsonSchema, TS, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case", deny_unknown_fields)]
pub struct ViewId(pub String);
```

I'm getting it with this struct atm.
