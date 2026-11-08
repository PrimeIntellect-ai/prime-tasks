Incorrectly deploys to "West US" when provider.location specifies "West US 2"
Repro steps:
```
sls create -t azure-nodejs -p myNewApp
# Notice that the `provider.location` setting is West US 2
sls deploy
```
The region group is `sls-wus-dev-myNewApp-rg` and the region for the resources is actually `West US`
Resource group name not created with stage from CLI
Similar to #281

Repro steps:
```
sls create -t azure-nodejs -p myNewApp
sls deploy
# Note that the resource group name is sls-wus-dev-myNewApp-rg
sls deploy --stage test
# Resource group remains the same
```
I would expect the resource group name to be sls-wus-test-myNewApp-rg
