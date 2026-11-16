propagate errors from `beforeAll` and `afterAll` hooks
+ Now error in the `beforeAll` and `afterAll` hooks would be captured and reported as error, but they will not be associated with the reporters in the correct way.
+ Without associating these errors, the Uptime UI will have no information about what happened during the context of a single execution.

We have to figure out a way to solve this problem.
