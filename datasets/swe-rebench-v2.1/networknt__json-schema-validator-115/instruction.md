LocalDateTime validation error
validation error on java.time.LocalDateTime:

for example:
    "lastUpdated": "2018-11-15T21:08:59",

validation error:
{"statusCode":400,"code":"ERR11004","message":"VALIDATOR_SCHEMA","description":"Schema Validation Error - $.lastUpdated: does not match the date-time pattern ^\\d{4}-(?:0[0-9]{1}|1[0-2]{1})-(0?[1-9]|[12][0-9]|3[01])[tT ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?([zZ]|[+-]\\d{2}:\\d{2})$","severity":"ERROR"}

change it to:     "lastUpdated": "2018-11-15T21:08:59Z" will pass the validation.

But when we load from attachment the value change back: "lastUpdated": "2018-11-15T21:08:59"
