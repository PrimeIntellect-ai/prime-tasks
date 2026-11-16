Enhancement: Create OutcomeResult class
Outcome results with `course.get_outcome_results()` are [returned as JSON](https://github.com/ucfopen/canvasapi/blob/3f1a71e23c86a49dbaa6e84f6c0e81c297b86e36/canvasapi/course.py#L1787-L1803). It's also not returned in a `PaginatedList`, so the call needs to either manually check for more results or the user has to call for larger batches.

Returning in a PaginatedList and creating an OutcomeResult class will allow for easier manipulation of results.

```javascript
// A student's result for an outcome
{
  // A unique identifier for this result
  "id": 42,
  // The student's score
  "score": 6,
  // The datetime the resulting OutcomeResult was submitted at, or absent that,
  // when it was assessed.
  "submitted_or_assessed_at": "2013-02-01T00:00:00-06:00",
  // Unique identifiers of objects associated with this result
  "links": {"user":"3","learning_outcome":"97","alignment":"53"},
  // score's percent of maximum points possible for outcome, scaled to reflect any
  // custom mastery levels that differ from the learning outcome
  "percent": 0.65
}
```

An additional improvement would be to convert the `links` property to an `OutcomeLink` instance.

### Additional contract requirements

An `OutcomeResult` preserves the associated identifiers supplied in its `links` data, including the user, learning outcome, and alignment identifiers.
