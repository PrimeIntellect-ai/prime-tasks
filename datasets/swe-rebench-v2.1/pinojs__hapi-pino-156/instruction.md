Request completed message is not super useful
The default message for the request completed log is `request completed`.
Which is not really useful. And definitely not in logging solutions like Google Cloud log where it uses this as the message to show.
<img width="512" alt="image" src="https://user-images.githubusercontent.com/2361826/157905593-c4b7913b-995b-4c0d-87eb-4d62ab4e6ec0.png">

The workaround is to add the needed fields to the summary of the log line but I think it might be more useful to log a summary of the request. e.g. `[response] get /version 200 (29ms)` => `[event type] method url statusCode (responseTime)`
