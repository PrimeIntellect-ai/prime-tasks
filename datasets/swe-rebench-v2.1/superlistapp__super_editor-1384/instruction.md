[attributed_text] - Make it easy to query all desired attributions
I'd like to easily query all the user tags or hash tags in an `AttributedText`.

Today this looks like:

```dart
final hashTags = text.getAttributionSpansInRange(
  attributionFilter: (attribution) => attribution is HashTagAttribution,
  range: SpanRange(start: 0, end: node.text.text.length),
);
```

A method could be added to make it look like this:

```dart
final hashTags = text.getAllAttributionSpans((a) => a is HashTagAttribution);
```

### Additional contract requirements

Expose the whole-text query as `getAttributionSpansByFilter(AttributionFilter filter)`. It accepts an attribution predicate and returns every span for an attribution selected by that predicate, without requiring the caller to construct a range. Return no spans when no attribution matches.
