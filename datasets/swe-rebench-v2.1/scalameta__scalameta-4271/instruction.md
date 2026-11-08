Abstract givens in trait cannot be anonymous error with scala 3.7.1 and scalafmt 3.9.7
Hello

and thank you very much for your nice work.

The following trait is ok for scala 3.7.1 but causes scalafmt to complain:
`error: [dialect scala3] abstract givens cannot be anonymous`

```
  trait AbstractGivenTest {
    given ExecutionContext
  }
```

Best regards,
  Sven
