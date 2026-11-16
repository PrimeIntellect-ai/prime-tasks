Date input default value cannot be at the extremes of the allowed range
I'm trying to use a `Kino.Input.date` in a livebook such that I want to limit the date range using `:min` and `:max`.

For example:

```ex
Kino.Input.date("From", min: ~D[2023-08-01], max: Date.utc_today())
```

Renders a widget with allowed dates 2023-08-01 all the way to 2023-09-01 (today) -- **both ends inclusive**.

---

I would like to set a default value with `:default`:

```ex
Kino.Input.date("From", default: ~D[2023-08-01], min: ~D[2023-08-01], max: Date.utc_today())
```

but I'm getting a validation error:


```
** (ArgumentError) expected :default to be bigger than :min, got: ~D[2023-08-01]
    (kino 0.10.0) lib/kino/input.ex:399: Kino.Input.date/2
```

Same on the `:max` end of the allowed range:

```ex
Kino.Input.date("From", default: Date.utc_today(), min: ~D[2023-08-01], max: Date.utc_today())
```

```
** (ArgumentError) expected :default to be smaller than :max, got: ~D[2023-09-01]
    (kino 0.10.0) lib/kino/input.ex:404: Kino.Input.date/2
```

The relevant code is:

https://github.com/livebook-dev/kino/blob/c0167dd44714fb81744b166b22decb07db7c3bce/lib/kino/input.ex#L396-L404

I think we have an off-by-one error. To match the behavior of the allowed range when using the widget we should test [HIDDEN].

### Additional contract requirements

- For `Kino.Input.date`, a default equal to either configured bound must be accepted; a default below `:min` or above `:max` must be rejected.
