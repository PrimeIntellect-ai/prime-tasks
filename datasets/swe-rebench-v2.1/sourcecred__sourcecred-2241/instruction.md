Grain distributions sometimes do not go out on schedule
We've had a number of automated Grain distributions fail to distribute any Grain. After reviewing the code, I'm fairly confident the culprit is the following logic:
https://github.com/sourcecred/sourcecred/blob/c5688c45b310635c1af0287c847d1e49a8d50626/src/ledger/applyDistributions.js#L70-L74

As you can see, we ignore the latest Cred interval, on the assumption that the latest interval is incomplete (i.e. for the current week). However, the intervals are populated based on the timestamps of real contributions. Therefore, if we run the grain distribution shortly after the interval start (like we do in GitHub actions), then it's possible that the latest interval will actually be complete.

To fix this, we should change the logic so it takes the current timestamp into account, rather than blindly assuming that the latest interval is not yet complete.
