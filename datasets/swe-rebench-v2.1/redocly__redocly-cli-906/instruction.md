Change four types names for consistency
## Issue

Type name consistency is important because custom plugins and assertions use type names to target logical evaluations.

I noticed some type names that feel inconsistent with OAS compared to how we name other types.

Samples that seemed consistent (✅ ) and inconsistent (⚠️ ).

- Info Object and we name our type `Info`. :white_check_mark:
- Schema Object and we name our type `Schema`. :white_check_mark:
- Parameter Object and we name our type `Parameter`. :white_check_mark:  etc...
- Paths Object and we name our type `PathsMap`. :warning:
- Responses Object and we name our type `ResponsesMap`. :warning:
- OAuth2 Flows Object and we name our type `SecuritySchemeFlows`. :warning:


## Solution

Rename the following from `X` to `Y`:

- [ ] `PathsMap` to `Paths` (because there is a `Paths Object` explicitly defined in OAS)
- [ ] `ResponsesMap` to `Responses` (because there is a `Responses Object` explicitly defined in OAS)
- [ ] `SecuritySchemeFlows` to `OAuth2Flows`
- [ ] `EncodingsMap` to `EncodingMap` (because there is no word "encodings" in English)

We leave these alone because they aren't defined as objects in OAS:
- `ServerVariablesMap`
- `WebhooksMap`
- `MediaTypesMap`
- `CallbacksMap`
- `HeadersMap`
- `LinksMap`
- `ExamplesMap`

**Background**
I hand-wrote out the types on note cards as part of an exercise called ["The Suck"](https://scottscheper.com/letter/40/). It wasn't fun, but because writing is so slow it gives you time to think about what you're writing at deeper than usual levels. I was also writing out excerpts of the OAS and this resulted in identifying the inconsistency in naming which led to this issue.
