Cannot parse ISO 8601 date format (2021-04-14)
If users choose this date format:
![image](https://user-images.githubusercontent.com/38738/114786748-ab2f2100-9d4c-11eb-8ae4-d27ebeb94920.png)

And I try to parse the file using `xlsx2csv` updated to use the latest release (v3.2.3) I get:

```
$ ./xlsx2csv ./Book1.xlsx
2021/04/14 18:20:38 invalid formatting code: unsupported or unescaped characters
```

Is it simple enough to get tealeg/xlsx to recognize this "yyyy-mm-dd" format which is a common format and easy to find in the Excel UI? Our users commonly use this format because it is arguably the most widely supported/recognized format.

### Additional contract requirements

- A cell whose number format is `yyyy-mm-dd` must be recognized as a date format (not rejected as an unsupported formatting code) and must format its date value as an ISO 8601 date in `YYYY-MM-DD` form; for example, the serial value `37947.7500001` formats to `2003-11-22`.
- The capitalized form `YYYY-MM-DD` must also be recognized as an equivalent date format and must produce the same `2003-11-22` output.
