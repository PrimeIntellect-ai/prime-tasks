[BUG] route53 tagging for hostedzones & list_tags_for_resources does not work properly
There are two bugs for route53.

To recreate, add `assert len(response["ResourceTagSets"]) == 2` in test_route53.py -> test_list_tags_for_resources() above `for set in response["ResourceTagSets"]:` on line 588.

list_tags_for_resources() doesn't actually return anything and it's stems from 3 bugs.

1. [HIDDEN] Thus, characters like "/" are encoded when tags are added. This impacts hostedzones which have slashes in the ID.  **list_tags_for_resources** [HIDDEN], so the key is never found and returns no results.
2. The list of ids isn't capture correctly, [HIDDEN]
3. The template for list_tags_for_resources doesn't work as expected and needs refactoring.

The test-case mentioned doesn't test what you expect and thus passes incorrectly.

### Additional contract requirements

- Tag operations must resolve URL-encoded resource IDs to the same resource, including hosted-zone IDs containing `/`, so tags added to that resource can be retrieved.
- `list_tags_for_resources` must return one tag set for each requested resource ID, containing that resource’s tags only; a resource with no tags must have an empty `Tags` list.
