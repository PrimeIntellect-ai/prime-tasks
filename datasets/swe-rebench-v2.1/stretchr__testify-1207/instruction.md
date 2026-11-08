Release 1.7.3 call AssertExpectations without On cause panic
If I call call method `AssertExpectations` without having call the method `On` it panics

panic: runtime error: invalid memory address or nil pointer dereference

I usually have a test structure like the one below: not always I will call `mock.On` to prepare the mock - depends on the case and the preconditions. But I always check if the expectations are correct.

[HIDDEN] In fact this release break all of my test suites.

I note that there is a `Test` method that can initialize it, but I never use it. And the documentation says the test field is optional. Call `Test` seems vague and redundant (what is test? it tests my mock? it set a field to be used?), since I still need to call `AssertExpectations`.

What is the solution? rewrite my test suites or may I submit a patch to initialize the mock? or perhaps I should create a constructor for my mocks that calls mock.Test and prepare it ?

```golang
func TestXxx(t *testing.T) {
  testcases := []struct {
    label string
    prepare func(*myMockObject)
    ...
  }{ ... }

  for _, tc := range testcases {
    tc := tc
    t.Run(tc.label, func(t *testing.T) {
         m := &myMockObject{}
         defer m.AssertExpectations(t)

         tc.prepare(m)

         // rest of the test
    }
  }
}
```

### Additional contract requirements

- Calling `AssertExpectations` on a zero-valued mock without first calling `On` must not panic or require calling `Test`.
