Add the ability to programmatically update batchSize and waitTimeSeconds
Users should be able to update these as required, this would allow them to adjust how the Consumer works on the fly and as both of these are sent with requests to AWS, the options should just be used in the next call that uses them.
