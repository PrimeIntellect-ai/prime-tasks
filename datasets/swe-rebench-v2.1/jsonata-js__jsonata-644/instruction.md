fromMillis not handling PN picture string
I'm trying to format a timestamp with the AM/PM marker in uppercase with `$fromMillis()`. Looking at the JSONata doc https://docs.jsonata.org/date-time-functions#frommillis which points to https://www.w3.org/TR/xpath-functions-31/#date-picture-string I can see some [examples](https://www.w3.org/TR/xpath-functions-31/#date-time-examples) with [PN] for upper case (`3:58 PM`  `format-time($t, "[h]:[m01] [PN]", "en", (), ()) ` ) and [Pn] for lower case (`3:58:45 pm` `format-time($t, "[h]:[m01]:[s01] [Pn]", "en", (), ())`.

I've tried out some equivalent picture values on https://try.jsonata.org/ with:
`$fromMillis($millis(), "[h]:[m01] [Pn]")` which also returns `"10:17 am"` (Correct)
`$fromMillis($millis(), "[h]:[m01] [PN]")` which returns `"10:17 am"` (I believe this is incorrect and should be `"10:17 AM"`)

I've been able to work around this with `$uppercase()` so it's a minor issue but I wanted to raise here to confirm whether the behaviour is incorrect for [PN] or if I'm misunderstanding how this should work. Thanks.
