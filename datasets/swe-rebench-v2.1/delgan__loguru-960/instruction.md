The log file is abnormal when the log is rotating
Hi, thank you so much for your project, it's really great. However, some problems have been found in the process of using it recently. Can you help to have a look?

I created a new file `logger.py`
```python
from loguru import logger

logger.remove()
logger.add(
    'logs/log.{time:YYYY-MM-DD}.log',
    level='INFO',
    rotation="00:00",
    retention='1 months',
    enqueue=True
)

logger.info('hello world')
logger.info('hello world')
```
I execute it on a time period of zero, for example at 00:10. Got two log files, but the other one is not what I expected. When I set the rotation parameter to 01:00, the normal result of executing the code will only generate the file `log.log`
`python logger.py`
<img width="378" alt="image" src="https://github.com/Delgan/loguru/assets/23091750/c4cd15b9-d9f6-4a87-8727-d94df736b8a6">

This should be a bug that must appear, and it will appear when it is executed at the same hour of the time set by the rotation parameter value.
@Delgan

### Additional contract requirements

- A daily time-based rotation must respect its configured calendar-date boundary when a sink is opened or reopened near midnight; it must not rotate a day early or a day late merely because the UTC date differs.
- With the date-formatted filename and midnight rotation shown above, records emitted before midnight must use that date in the filename, and records emitted after midnight must use the new date.
