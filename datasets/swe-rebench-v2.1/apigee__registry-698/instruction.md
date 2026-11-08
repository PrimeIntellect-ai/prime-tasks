Registry API: DeleteApiSpecRevision can delete the only remaining revision of a spec
[AIP-162](https://google.aip.dev/162#deleting-revisions) states the following. We don't currently support this expected behavior.

> The method must not cause the resource to be deleted. Because a resource should not exist with zero revisions, the method must fail with FAILED_PRECONDITION if the user attempts to delete the only revision.

We have a [test](https://github.com/apigee/registry/blob/9c0e693d871ddb18e31137a59949bbcebf3fb1f5/server/actions_spec_revisions_test.go#L237) for this case that is currently skipped.
