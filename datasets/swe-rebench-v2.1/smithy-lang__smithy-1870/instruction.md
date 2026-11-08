Unused offset within smithy.model.pattern.SmithyPattern.Segment.Parse
Hi, I think there's a small bug with the Segment Parser.

It appears that the `offset` variable is currently unused within the `smithy.model.pattern.SmithyPattern.Segment.Parse` function.
https://github.com/awslabs/smithy/blob/2e1cdc4af7e7cdab3138f5f3912a3af930b569a2/smithy-model/src/main/java/software/amazon/smithy/model/pattern/SmithyPattern.java#L276

All callers of this function also appear to be calling this `parse` function incorrectly and are exhibiting correct parsing behaviour because the `offset` variable is unused.

The call to `Segment.parse` at https://github.com/awslabs/smithy/blob/2e1cdc4af7e7cdab3138f5f3912a3af930b569a2/smithy-model/src/main/java/software/amazon/smithy/model/pattern/UriPattern.java#L80
[HIDDEN]

The call to `Segment.parse` at https://github.com/awslabs/smithy/blob/2e1cdc4af7e7cdab3138f5f3912a3af930b569a2/smithy-model/src/test/java/software/amazon/smithy/model/pattern/SmithyPatternTest.java#L39
[HIDDEN]

The call to `Segment.parse` at https://github.com/awslabs/smithy/blob/2e1cdc4af7e7cdab3138f5f3912a3af930b569a2/smithy-model/src/main/java/software/amazon/smithy/model/traits/EndpointTrait.java#L66
[HIDDEN]

A new test should be added to verify that the offset is used correctly.

Alternatively, the `offset` parameter could be removed but this would be a breaking API change so less desirable, up to you though.

I'm happy to submit a PR to correct the issue if the above is correct.

### Additional contract requirements

- `Segment.parse(String content, int offset)` must use `offset` as the zero-based character index where the segment begins in the containing pattern. When an invalid segment is reported, its location must be an index in the full pattern, not an index relative to the segment. Callers must supply the segment's starting index, counting any preceding delimiters.
