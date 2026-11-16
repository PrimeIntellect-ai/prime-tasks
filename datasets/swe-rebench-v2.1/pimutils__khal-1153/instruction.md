Configuration file created by programing giving a critical error saying default is not valid
After creating the configuration file using the built in configuration tool I get the error
``````
critical: in section [default] cal_local is not valid for 'default_calendar', must be one of ['default']
If your configuration file used to work, please have a look at the Changelog to see what changed.
``````
this is my configuration file
```
[calendars]

[[cal_local]]
path = ~/.calendars/*
type = discover

[locale]
timeformat = %I:%M %p
dateformat = %m/%d/%Y
longdateformat = %m/%d/%Y
datetimeformat = %m/%d/%Y %I:%M %p
longdatetimeformat = %m/%d/%Y %I:%M %p

[default]
default_calendar = cal_local
```
I have set up vdirsyncer correctly (unless I did it incorrectly for khal). Any suggestions for fixing my configuration file?

### Additional contract requirements

When the configuration wizard creates a configuration for a `discover` collection, the `default_calendar` it writes must identify a calendar name recognized by the generated configuration, not merely the declared collection name.
