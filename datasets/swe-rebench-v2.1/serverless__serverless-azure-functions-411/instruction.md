Listing Deployments: TypeError: Cannot convert undefined or null to object error
# This is a Bug Report

## Description

When attempting to deploy to Azure I'm getting a TypeError when the plugin is checking previous deployment templates.

```
TypeError: Cannot convert undefined or null to object
      at Function.keys (<anonymous>)
      [HIDDEN]
      at ArmService.areDeploymentsEqual (/Users/brucestorrie/drds/azuretest/drdsfuncs/node_modules/serverless-azure-functions/lib/services/armService.js:276:80)
      at ArmService.<anonymous> (/Users/brucestorrie/drds/azuretest/drdsfuncs/node_modules/serverless-azure-functions/lib/services/armService.js:193:34)
      at step (/Users/brucestorrie/drds/azuretest/drdsfuncs/node_modules/serverless-azure-functions/lib/services/armService.js:56:23)

```

## Additional Data

I've debugged the issue and identified that it's because the previous deployment template did not contain any parameters but there is a check within the code to compare templates which isn't catering for that scenario.

### Additional contract requirements

- When comparing deployments, a previous deployment with no parameters must not cause a TypeError.
