Delete branch if receiving 422 Unprocessable Entity when creating PR
When looking at the branch manually through GitHub web, and attempting to compare to master, we see:

![image](https://user-images.githubusercontent.com/6311784/30001331-4bea0a42-908b-11e7-803c-cfd33a101d1f.png)

If we don't have a way of detecting that this "needs rebasing" then we should delete the branch so it can be fixed on the next run.

### Additional contract requirements

- When creating a PR fails with a 422 Unprocessable Entity response, the branch is deleted using the existing `config.api.deleteBranch(branchName)` API method.
