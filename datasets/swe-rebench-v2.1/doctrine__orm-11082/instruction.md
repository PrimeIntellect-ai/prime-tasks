Collections data loaded twice when using EAGER loading in combination with iterables
### Bug Report

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q        |   A
|------------ | ------
| BC Break    | yes
| Version     | 2.17.0/2.17.1

#### Summary

<!-- Provide a summary describing the problem you are experiencing. -->

With #8391 optimisations where added with relation to eager loading collections. However, the eager load of the collection is not triggered when using an iterable result, causing the collection to be hydrated twice when actually accessed.

#### Current behavior

<!-- What is the current (buggy) behavior? -->

When an uninitialised collection within an entity coming from a iterable result is hit, it will trigger its load. However, this load also triggers the unit of work to process the stored eagerly loaded collection to load, resulting in the collection being loaded twice: it will contain duplicate items.

#### How to reproduce

<!--
Provide steps to reproduce the bug.
If possible, also add a code snippet with relevant configuration, entity mappings, DQL etc.
Adding a failing Unit or Functional Test would help us a lot - you can submit one in a Pull Request separately, referencing this bug report.
-->

See the added test, and proposed fix in #11082.

#### Expected behavior

<!-- What was the expected (correct) behavior? -->

The collection should not contains each item twice. [HIDDEN]

### Additional contract requirements

- When an entity is returned by an iterable result, accessing an eager-loaded collection must yield each related item only once.
