Timestamp.getMillis() returns wrong value when Timestamp was constructed via forCalendar()
The instant returned by `Timestamp.getMillis()` is incorrect when constructed via `Timestamp.forCalendar()` with a Calendar that is offset from UTC.  For example, the following code:

```java
Date now = new Date();
Calendar cal = Calendar.getInstance();
cal.setTimeZone(TimeZone.getTimeZone("GMT+02:00"));
cal.setTime(now);
Timestamp ts = Timestamp.forCalendar(cal);
System.out.println(now.getTime());
System.out.println(ts.getMillis());
```

incorrectly produces:
```
1549646861615
1549639661615
```

These epoch values should be identical.
