Add SqlQuery#one, SqlQuery#findOne
I want to add a method that guarantees that only one query is fetched when fetching query results.
I think that it is good to raise an exception when you get 2 or more, or to judge by Optional.

This is often useful for enterprise use cases.

```java
Map<String, Object> one(CaseFormat caseFormat);
Map<String, Object> one();
<T> T one(Class<T> type);
Optional<Map<String, Object>> findOne(CaseFormat caseFormat);
Optional<Map<String, Object>> findOne();
<T> Optional<T> findOne(Class<T> type);
```
