Existence check for parent resource is missing while listing artifcts.
I was able to list artifacts for an `ApiDeployment` and `ApiSpec` that doesn't exist.

```
curl http://x.x.x.x/v1/projects/krpate-test/locations/global/apis/test/deployments
{
 "apiDeployments": [
  {
   "name": "projects/krpate-test/locations/global/apis/test/deployments/prod",
   "displayName": "",
   "description": "",
   "revisionId": "66f817f8",
   "apiSpecRevision": "",
   "endpointUri": "bleh.com",
   "externalChannelUri": "",
   "intendedAudience": "",
   "accessGuidance": "",
   "labels": {},
   "annotations": {},
   "createTime": "2023-01-19T22:15:05.690925Z",
   "revisionCreateTime": "2023-01-19T22:15:47.585520Z",
   "revisionUpdateTime": "2023-01-19T22:15:47.585520Z"
  }
 ],
 "nextPageToken": ""
}

curl http://x.x.x.x/v1/projects/krpate-test/locations/global/apis/test/deployments/invalid/artifacts
{
 "artifacts": [],
 "nextPageToken": ""
}
```

We used to have an existence check for the parent resource, but it looks like it was removed in https://github.com/apigee/registry/pull/818.
