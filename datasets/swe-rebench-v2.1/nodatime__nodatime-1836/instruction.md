Non-allocative way of having TotalSeconds between two LocalTime inputs
Hello!
For some reason the project I work on have called something

```
public double GetTotalSeconds(LocalTime time1, LocalTime time2)
{
    return (time1 - time2).ToDuration().TotalSeconds;
}
```
which results in 80B allocation per call.
We call this on 3 different time fields and this has to be repeated for a large number of times which results in large amount of allocation.

Im not sure how useful it is for others but if possible I would like to see if we can have something like https://github.com/nodatime/nodatime/issues/1450 and implement this without having a Period object created. ie. Get the same thing done by Period.Between return directly:
[HIDDEN]

This should yield a benchmark like below (shortrun job):
| Method                 | Mean       | Error      | StdDev    | Median     | Gen0   | Allocated |
|----------------------- |-----------:|-----------:|----------:|-----------:|-------:|----------:|
| TotalSecondsLocalTimePeriod  | 23.1932 ns | 12.0196 ns | 0.6588 ns | 22.8489 ns | 0.0064 |      80 B |
| TotalSecondsLocalTime |  0.0349 ns |  0.8089 ns | 0.0443 ns |  0.0200 ns |      - |         - |

If you are happy on this proposal, I can help to create a PR for it (first time :)).
Thanks in advance.
(...and question I have in mind..:
- I saw there is an uncheck on Period.Between()'s implementation - but curious under what case that would be required since it is always doing a subtraction?
- Why not implement #1450 as extension on LocalTime itself but in the Period class?)

### Additional contract requirements

- Add a public static method `Period.NanosecondsBetween(LocalTime start, LocalTime end)` in the `NodaTime` namespace, returning a `long`.
- Return the signed number of nanoseconds from `start` to `end`; the result is negative when `end` precedes `start`. The result must follow unchecked overflow semantics.
- The calculation must not allocate or create a `Period` object.
