MSSQL database user
<!--
Thank you for helping to improve Crossplane!

Please be sure to search for open issues before raising a new one. We use issues
for bug reports and feature requests. Please find us at https://slack.crossplane.io
for questions, support, and discussion.
-->

### What happened?
Attempting to create MSSQL User. User fails to create with `managed/user.mssql.sql.crossplane.io  cannot create user: mssql: You can only create a user with a password in a contained database.`


### How can we reproduce it?
Using the following:
```
apiVersion: mssql.sql.crossplane.io/v1alpha1
kind: User
metadata:
  name: user-name
spec:
  deletionPolicy: Delete
  forProvider:
    databaseRef:
      name: database-name
    passwordSecretRef:
      name: password-secret
      namespace: namespace
      key: password
  providerConfigRef:
    name: provider-config
```

### What environment did it happen in?
Crossplane version: 1.12.2

<!--
Include at least the version or commit of Crossplane you were running. Consider
also including your:

* Cloud provider or hardware configuration Cloud
* Kubernetes version (use `kubectl version`) v1.27.1
* Kubernetes distribution (e.g. Tectonic, GKE, OpenShift) AWS EKS
* OS (e.g. from /etc/os-release)
* Kernel (e.g. `uname -a`)
-->

### Additional contract requirements

A password-backed MSSQL User for a non-contained database must be creatable by creating the SQL Server login in a separately configurable login database and creating the database user in the User's target database. Configure the login database with the `LoginDatabase` field. If `LoginDatabase` is not specified, use the target database for login creation.
