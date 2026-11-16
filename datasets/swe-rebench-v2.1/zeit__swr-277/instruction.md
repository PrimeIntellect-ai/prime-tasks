Setting max retryCount on error
Is there a way to add a max retryCount on error without overriding the entire onErrorRetry? I think it'd be nice to be able to keep the very reasonable default behaviour of exponential backoff and stopping on ```!isDocumentVisible()```, but be able to tweak and limit max tries via config.

What do you think?

### Additional contract requirements

- The configuration option for the maximum number of retries must be named `errorRetryCount`.
