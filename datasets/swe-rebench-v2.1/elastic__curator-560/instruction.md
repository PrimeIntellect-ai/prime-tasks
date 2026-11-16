Create snapshot repository from curator
Curator API allows us to take and restore snapshots, but before we do it, we have to create an snapshot repository.

I just saw that you can use the es_repo_mgr script to create it, but this method is not available in the api, only for the cli version.

Is there any plans to add this feature to the API? Or is this not here by design?

Thank you!

### Additional contract requirements

The snapshot repository creation operation is available through the public API as `curator.api.create_repository`. Callers can provide the repository name and repository configuration, and those values are used when requesting creation from Elasticsearch.
