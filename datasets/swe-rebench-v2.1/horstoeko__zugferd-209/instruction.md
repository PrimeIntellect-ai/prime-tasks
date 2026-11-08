[BUG] function toDateTime returns DateTime|null but DateTime::createFromFormat could return DateTime|false ...
Hello Daniel,
there is a little bug today into parsing XML with your great lib ...

```
  <ram:IssueDateTime>
    <udt:DateTimeString format="102">
      20241011
    </udt:DateTimeString>
  </ram:IssueDateTime>
```

Then in that race condition i have that error

```
Return value of horstoeko\zugferd\ZugferdObjectHelper::toDateTime() must be an instance of DateTime or null, bool returned
```

cheers
(Éric from France)
