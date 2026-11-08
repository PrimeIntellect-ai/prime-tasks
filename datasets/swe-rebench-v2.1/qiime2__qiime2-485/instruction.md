Allow Metadata constructor(s) to optionally strip whitespace
**Improvement Description**
A kwarg in the various Metadata constructors to strip whitespace in all columns could be really convenient for transformers et al.

**Current Behavior**
Whitespace is not stripped.

**Proposed Behavior**
If some kwarg (say, `strip_whitespace`) was True, the MD constructor would strip whitespace.

**Questions**
1. This could also just be the default behavior, right? Am I missing something here?

### Additional contract requirements

Metadata construction strips leading and trailing whitespace from textual metadata column values by default; callers do not need to provide a constructor option to enable it. The normalized values are the values exposed by the constructed metadata and metadata column. This default behavior is the resolution of whether stripping should instead be selectable.
