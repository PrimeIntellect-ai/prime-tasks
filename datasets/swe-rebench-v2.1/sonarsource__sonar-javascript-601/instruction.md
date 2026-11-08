GetterSetterCheck should not fail on duplicate getter
Migrated from [SONARJS-904](https://jira.sonarsource.com/browse/SONARJS-904)
GetterSetterCheck (RSPEC-2376) should not fail on:
```
class C {
  get p1() { return 42; }
  get p1() { return 42; }
}
```
