Celery timezone use default UTC timezone ignoring settings.
## Checklist
Celery 4.2.0

* [ ] I have included the output of ``celery -A proj report`` in the issue.
      (if you are not able to do this, then at least specify the Celery
       version affected).
* [x] I have verified that the issue exists against the `master` branch of Celery.

## Steps to reproduce
Use any TZ settings in celery settings or Django


```
    app.conf.timezone   = 'Europe/London'
    app.conf.enable_utc   = True
```

Celery will ignore those settings, and set time equal to London -1 hour (just like winter time)

## Expected behavior
Celery should use TZ as it was set in settings.

## Actual behavior
Celery use UTC default instead.

Related:
#2649
#4006

Steps to possible fix:

Firstly, this probably should be the datetime.now instance, not datetime.utcnow(), because why would we decide to UTC already an UTC?

    def to_utc(dt):
        """Convert naive :class:`~datetime.datetime` to UTC."""
        return make_aware(dt, timezone.utc)It now allows me to set London time everywhere:

```
<=Celery App Base=> timezone_func conf.timezone: Europe/London
<=Celery App Base=> timezone_func timezone.get_timezone(conf.timezone): Europe/London
<=Celery Schedules=> now -> self.nowfun() 2018-06-22 14:11:03.625825+01:00
<=Utils Time=> to_utc -> What is dt_utc: 2018-06-22 14:11:03.626616
<=Utils Time=> remaining -> now 2018-06-22 14:11:03.629900+01:00
<=Celery Schedules=> now -> self.nowfun() 2018-06-22 14:11:03.630299+01:00

<=Utils Time=> make_aware -> _localize(dt, is_dst=None) 2018-06-22 14:11:03.630514+00:00
<=Utils Time=> to_utc -> make_aware(dt_utc, timezone.utc): 2018-06-22 14:11:03.630514+00:00
<=Utils Time=> make_aware -> What is dt: 2018-06-22 14:11:03.630514
```

But still task recieved in older time:

```
Received | 2018-06-22 13:05:02.712443 UTC
-- | --
Sent | 2018-06-22 13:05:02.707066 UTC
Started | 2018-06-22 13:05:02.716835 UTC
Succeeded | 2018-06-22 13:05:03.029372 UTC
Retries | 0
Timestamp | 2018-06-22 13:05:03.029372 UTC
```

I'm still struggling with actual task time, which is use UTC time, but inspecting task obj content doesn't show me anything:

```
[2018-06-22 14:38:03,737: ERROR/MainProcess] Received task: message,
	on_ack=<promise@0x7f4147022ee8 --> <bound method Consumer.call_soon of <Consumer: w_perforce@HOST (running)>>>,
	on_reject=<promise@0x7f4147022dc8 --> <bound method Consumer.call_soon of <Consumer: w_perforce@HOST (running)>>>,
	app=<Celery octo at 0x7f41496cea20>,
	hostname=w_perforce@HOST,
	eventer=<celery.events.dispatcher.EventDispatcher object at 0x7f414700fa20>,
	task=<@task: works.tasks.task_p4_info of octo at 0x7f41496cea20>,
	connection_errors=(<class 'amqp.exceptions.ConnectionError'>, <class 'OSError'>, <class 'OSError'>, <class 'OSError'>),
	body=b'\x80\x02]q\x00}q\x01(X\x06\x00\x00\x00branchq\x02X\x08\x00\x00\x00tkn_mainq\x03X\t\x00\x00\x00user_nameq\x04X\t\x00\x00\x00DEV_ADMINq\x05X\x03\x00\x00\x00runq\x06X\x07\x00\x00\x00p4_infoq\x07ua}q\x08}q\t(X\x05\x00\x00\x00chainq\nNX\t\x00\x00\x00callbacksq\x0bNX\x08\x00\x00\x00errbacksq\x0cNX\x05\x00\x00\x00chordq\rNu\x87q\x0e.',
	headers={'parent_id': None, 'retries': 0, 'id': '77c56aa8-eee1-404f-942e-3c850dc960ea', 'expires': None, 'reply_to': '5db87f93-e390-3679-b2ab-e7a0aaf48510', 'delivery_info': {'exchange': '', 'priority': None, 'redelivered': False, 'routing_key': 'perforce'}, 'argsrepr': "[{'branch': 'tkn_main', 'user_name': 'DEV_ADMIN', 'run': 'p4_info'}]", 'correlation_id': '77c56aa8-eee1-404f-942e-3c850dc960ea', 'kwargsrepr': '{}', 'root_id': '77c56aa8-eee1-404f-942e-3c850dc960ea', 'timelimit': [None, None], 'lang': 'py', 'task': 'works.tasks.task_p4_info', 'shadow': None, 'origin': 'gen31414@HOST', 'eta': None, 'group': None},
	decoded=False,
	utc=False
```

So, the questions is -
Where do Celery's task take this time?

### Additional contract requirements

The timezone requirement applies to the result metadata recorded for a finished task: its `date_done` field must be an ISO-8601 timestamp produced from the application's current time (`app.now()`) and expressed in the application's configured timezone (the timezone from settings), instead of always in UTC.

Public names:
- `celery.backends.base.Backend.__init__(self, app)`: constructs a result backend bound to the given Celery app.
- `celery.backends.base.Backend._get_result_meta(self, result, state, traceback, request, format_date=True, encode=False)`: returns a mapping containing at least the keys `status`, `result` and `date_done`. When the state is a ready state, `date_done` is an ISO-8601 string derived from `app.now()` in the configured timezone.
