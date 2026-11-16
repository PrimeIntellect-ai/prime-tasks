Camel case the commands in listing
I get that this is very subjective, but this is from the Hugo build:

```bash
▶ mage
  check            Run tests and linters
  checkvendor      Verify that vendored packages match git HEAD
  docker           Build hugo Docker container
  fmt              Run gofmt linter
  hugo             Build hugo binary
  hugonogitinfo    Build hugo without git info
  hugorace         Build hugo binary with race detector enabled
  install          Install hugo binary
  lint             Run golint linter
  test             Run tests
  test386          Run tests in 32-bit mode
  testcoverhtml    Generate test coverage report
  testrace         Run tests with race detector
  vendor           Install govendor and sync Hugo's vendored dependencies
  vet              Run go vet linter
```

Which is mostly beautiful. But the all lower-case command names looks "wrong" in my eyes. I would much prefer that it followed the original case of the method, but with a lowercase first letter, so `hugoRace`, `testCoverHTML`etc. I would still expect the all lowercase variant to work.
