When keeper fails to merge a PR it would be nice to know why
We had a recent situation where lighthouse was failing to merge a PR on a new repo (due to github config) but it would be nice to surface the error message somewhere so the user can take action.

The error inside keeper was:

```{"base-sha":"cb2bcdde269d75c1e37046226a66e43f9d5a4039","branch":"master","component":"keeper","controller":"sync","error":"Merge commits are not allowed on this repository.","file":"/workspace/source/pkg/keeper/keeper.go:976","func":"github.com/jenkins-x/lighthouse/pkg/keeper.(*DefaultController).mergePRs","level":"error","merge-targets":[24],"msg":"Merge failed.","org":"jenkins-x","pr":24,"repo":"jx-api","sha":"59090827b78bba840f60cf0491c5fae8cd34c36c","time":"2020-06-23T15:55:59Z"}
{"action":"MERGE","base-sha":"cb2bcdde269d75c1e37046226a66e43f9d5a4039","branch":"master","component":"keeper","controller":"sync","file":"/workspace/source/pkg/keeper/keeper.go:1314","func":"github.com/jenkins-x/lighthouse/pkg/keeper.(*DefaultController).syncSubpool","level":"info","msg":"Subpool synced.","org":"jenkins-x","repo":"jx-api","targets":[24],"time":"2020-06-23T15:55:59Z"}
```

Could this be added as a status message, or a comment on the PR?
