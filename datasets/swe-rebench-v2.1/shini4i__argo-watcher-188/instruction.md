incorrect alias detection when there is a whitespace after comma
During our testing, we discovered that using a similar annotation approach as the one used in the ArgoCD Image Updater results in improper alias handling in our project. Specifically, it fails to identify the relevant Helm annotations.

Working version: `app=example/example,app2=example2/example2`
Not working version: `app=example/example, app2=example2/example2` (whitespace after comma)

[HIDDEN]

### Additional contract requirements

- For managed-image annotations, extraction must also return `{"alias1":"image1","alias2":"image2"}` for each of `alias1=image1, alias2=image2`, `alias1=image1 ,alias2=image2`, and `alias1=image1 , alias2=image2`.
