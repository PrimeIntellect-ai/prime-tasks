Auth Emulator batchGet should return nextPageToken if page is full
## Expected Behavior

If there are enough users to fill a whole page size (whatever that is), a `nextPageToken` should be returned even if the next page would be empty. (I've tested in production and this is the behavior indeed.)

## Actual Behavior

The Auth Emulator returns no page token if number of users is same as page size. This causes tests failures like https://github.com/firebase/firebase-admin-node/pull/1204/checks?check_run_id=2189478758.

We had to disable that tests for now (https://github.com/firebase/firebase-admin-node/pull/1205) and that should be reverted after the fix land in a release.
