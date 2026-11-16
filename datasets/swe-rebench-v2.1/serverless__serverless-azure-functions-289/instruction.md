Rollback package not cleaned up when deploying directly to blob storage
Currently the mechanism for rolling back a function that deploys the code directly to blob storage (default behavior) is to download the blob to the `.serverless` folder and then redeploy the package. That should be cleaned up.
