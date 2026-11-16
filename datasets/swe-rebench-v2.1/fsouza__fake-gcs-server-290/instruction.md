python gcs client will throw ValueError because of wrong timestamp format
The python GCS client somehow takes its format very similar to RFC3339 but not exactly the same so it will throw.

The format it uses is actually:

`"2006-01-02T15:04:05.999999Z07:00"`

not

`time.RFC3339`

 would this be fixed?
