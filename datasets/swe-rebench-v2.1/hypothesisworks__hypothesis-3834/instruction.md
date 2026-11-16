Too-slow health check doesn't say what was too slow
From https://travis-ci.org/LeastAuthority/txkube/builds/194934837

```
Traceback (most recent call last):
  File "/home/travis/virtualenv/python2.7.9/lib/python2.7/site-packages/txkube/test/test_model.py", line 94, in test_roundtrip
    def test_roundtrip(self, obj):
  File "/home/travis/virtualenv/python2.7.9/lib/python2.7/site-packages/hypothesis/core.py", line 438, in wrapped_test
    HealthCheck.too_slow,
  File "/home/travis/virtualenv/python2.7.9/lib/python2.7/site-packages/hypothesis/core.py", line 306, in fail_health_check
    raise FailedHealthCheck(message)
hypothesis.errors.FailedHealthCheck: Data generation is extremely slow: Only produced 9 valid examples in 1.13 seconds (0 invalid ones and 1 exceeded maximum size). Try decreasing size of the data you're generating (with e.g.average_size or max_leaves parameters).
See https://hypothesis.readthedocs.io/en/latest/healthchecks.html for more information about this. If you want to disable just this health check, add HealthCheck.too_slow to the suppress_health_check settings for this test.
```

Fortunately there's only a single strategy used by the test that failed here so (by reading the source) it's easy to find out what it was.  If there had been multiple strategies, it would have been more of a pain to track down.

### Additional contract requirements

- When a `@given` test fails the too-slow health check, the failure message must name the argument (the keyword name it was given under) whose data generation was slow, so the user can see which strategy to change.
