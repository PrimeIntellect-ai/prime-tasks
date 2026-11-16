Feature idea: assert Eventbridge/events Detail field is a dict
This one trips me up the entire time

Eventbridge/events Detail field is required by AWS to be a JSON object (Python dict)

I accidentally send it JSON lists all the time

Production Eventbridge just silently ignores them, leading to mucho head scratching and frustration

Moto events seems to silently allow list sending also

It would be great if moto events could raise a warning/exception on encountering a Detail in list form!

Just a thought

### Additional contract requirements

- When `put_events` receives an entry whose `Detail` is valid JSON but not a JSON object (for example a JSON list), it emits a warning rather than raising an exception. The warning message contains the text `EventDetail should be of type dict`.
