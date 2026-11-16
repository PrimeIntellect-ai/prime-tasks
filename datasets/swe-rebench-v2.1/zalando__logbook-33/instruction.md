Add classifier to JSON formatted messages

    {
        "type": "request",
        "correlationId": "..."
    }

Possible values: `request` and `response`
Should be the very first property in the object to make it easier to read in scalyr
