app.route mixes up parameters passed when multiple regex patterns are used
We recently upgraded from Flask v1.1.2 to Flask v2.2.2 and were surprised when many of our project unit tests started failing because Flask v2.2.2 is not passing the correct parameters to a route function.  This worked correctly in the previous v1.1.2 which we were using but no longer works properly in v2.2.2.

The following python code example of a route which passes 3 parameters with regex expressions will replicate the bug:

```python
ALLOWED_METHODS = ["GET", "HEAD"]
DATE_PATTERN = "((\d{8}T\d{6}([.,]\d{1,3})?)|(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.,]\d{1,3})?))Z"
# Note that 2 date formats are supported using this date pattern
# if you want to see what this regex does, paste it into https://regexper.com/

@app.route('/<regex("\d+"):source_id>/'
        + '<regex("' + DATE_PATTERN + '"):start_time>/'
        + '<regex("' + DATE_PATTERN + '"):end_time>', methods=ALLOWED_METHODS)
def clipslist_id(source_id, start_time, end_time):
    print("clipslist_id parameters source_id {} start_time {} and end time {}".format(source_id, start_time, end_time))
    print("Valid parameters {}".format(end_time > start_time))
    return
```

Call the app.get function and pass in a uri such one of the following (two date formats are supported):

```
/22/2023-02-16T23:36:36.266Z/2023-02-16T23:46:36.266Z
/22/20230217T002724.998Z/20230217T003724.998Z
```

Note that in both of the example uri's above the 3rd datetime parameter value is 10 minutes after the 2nd datetime parameter value
When the uri gets routed to clipslist_id the function receives 3 parameters, but the 3rd parameter is not correct.  Instead of passing through the correct 3rd parameter the route code passes the 2nd parameter twice, once as the 2nd parameter, and again as the 3rd parameter.

The three parameters received by the function should have had the values for: source_id, start_time, and end_time
Instead the three parameters that the function received were: source_id, start_time, start_time
The end_time value was not passed to the function

Environment:
Python 3.8.10 (default, Nov 14 2022, 12:59:47)
Flask 2.2.2

Distributor ID:	Ubuntu
Description:	Ubuntu 20.04.5 LTS
Release:	20.04
Codename:	focal
5.15.0-58-generic
