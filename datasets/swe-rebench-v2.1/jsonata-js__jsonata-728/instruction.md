Issue with time conversion (string -->ISO) - deviation from intended time when using to/from millis
Working with latest version. When trying to convert a local timeformat (YYYYMMDDHHmmss), I get an issue of misconversion;
For the input string:

```
"20240101123849"
```

I want to recieve:
```
"2024-01-01T12:38:49Z",
```

However, using the code:

```
$fromMillis($toMillis($,"[Y0000][M00][D00][H00][m00][s00]"))
```

results in:
```
 "2024-02-21T14:04:09.000Z"
```

using the "brute force" approach with
```
(
    $substring($,0,4) & "-" &
    $substring($,4,2) & "-" &
    $substring($,6,2) & "T" &
    $substring($,8,2) & ":" &
    $substring($,10,2) & ":" &
    $substring($,12,2) & "Z";
  );
```
results in the right time.

I've noticed that the original seconds segment is translated to the minutes and seconds in the wrong output. changing the hour affects the day/month (depending on value). looks like an issue with the way the string is translated, however chaging the PICTURE parameter didn't seem to solve the isse.
