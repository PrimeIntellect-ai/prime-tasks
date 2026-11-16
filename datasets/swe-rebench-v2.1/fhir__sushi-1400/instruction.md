Pulling IG Publisher Scripts from wrong address
sushi/src/utils/Processing.ts currently pulls from http://raw.githubusercontent.com/HL7/ig-publisher-scripts/main/*
This causes an issue behind a proxy because the proxy is only used for https requests.

In my opinion the simplest solution would be to have SUSHI pull from [HIDDEN] instead.

Is there any reason that this should be http?

### Additional contract requirements

- SUSHI must fetch IG Publisher scripts from the HTTPS raw GitHub address rather than its HTTP equivalent.
