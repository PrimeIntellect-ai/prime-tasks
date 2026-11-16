Node runtime should be set to node
# This is a Bug Report

## Description

Generated local.settings.json uses `nodejs` as the `FUNCTIONS_WORKER_RUNTIME` instead of the valid value of `node`.

Similar or dependent issues:

Might be related to: #437

/cc jclaessens97 who raised this at https://github.com/Azure/azure-functions-core-tools/issues/2002
