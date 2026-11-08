SUSHI fails to load current version of IGs that use "main" branch
If a SUSHI project specifies a dependency with version `current`, and that dependency uses `main` as its default branch in GitHub, SUSHI will fail to load it and log an error like this:
> Failed to load ihe.iti.basicaudit#current: Request failed with status code 404

This is because SUSHI is looking for the `package.tgz` in the root location on the build server (e.g., https://build.fhir.org/ig/IHE/ITI.BasicAudit/package.tgz).  This works when the default branch is `master`, but not when it is `main`.  When it is `main`, the package only exists in the branch-specific location (e.g., http://build.fhir.org/ig/IHE/ITI.BasicAudit/branches/main/package.tgz).

SUSHI should be updated to always look in the branch-specific location.  This should be safe, because:
* Both `master` and `main` are available at their respective branch-specific locations
* SUSHI was recently updated to filter out all non-`master`/non-`main` branches
