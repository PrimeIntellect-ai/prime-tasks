Incorrectly identifies `via-(length:...)` as a color
### Describe the bug

Incorrectly identifies `via-(length:--some-variable)` as a color.

### To Reproduce

```
// prints "via-(length:--mobile-header-gradient-height)"
console.log(
    twMerge(
      "via-background via-(length:--mobile-header-gradient-height)",
    ),
  );
```

### Expected behavior

```
// prints "via-background via-(length:--mobile-header-gradient-height)"
console.log(
    twMerge(
      "via-background via-(length:--mobile-header-gradient-height)",
    ),
  );
```

### Environment

<!-- Add any relevant environment info -->

-   tailwind-merge version: 3.0.2

### Additional context

I managed to workaround the issue by adding this to the `classGroups` of my tailwind merge config:
[HIDDEN]

### Additional contract requirements

- Treat a `via-(length:...)` arbitrary-variable utility as a gradient-stop position, not a color, so it does not remove an earlier color `via` utility.
- An unlabelled arbitrary-variable `via` value remains a color and continues to replace an earlier color `via` utility.
