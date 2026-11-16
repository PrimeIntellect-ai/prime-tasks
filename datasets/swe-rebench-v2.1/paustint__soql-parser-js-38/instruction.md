Subquery relationship names should not use SObject
<!--
  Please include the following classification.
  If your classification is not added, you can modify the list below
-->
- [ ] Feature
- [x] Bug Request

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description
the SObject field on the results does not make sense to use for subqueries, as it is really the child relationship name.

There should be a new field on Query to indicate the name, since we really don't know the actual SObject name

### Additional contract requirements

A parsed subquery must expose its child relationship name in the `sObjectRelationshipName` field of its `Query` object. It must not report that relationship name as the subquery's SObject name.
