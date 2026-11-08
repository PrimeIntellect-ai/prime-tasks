Corrupted scheduler database
Hello,

I'm using celery in a django project in production env and sometimes, after a release PersistentScheduler become corrupted and i can't figure why.

The last release it happen i updated celery from 4.1.0 to 4.1.1 and updated my CELERY_BEAT_SCHEDULE settings (adding two new beats). Maybe a clue ?
Celery is running as a systemd service.

The error:
```[2018-05-26 09:01:01,377: ERROR/Beat] Process Beat
Traceback (most recent call last):
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/kombu/utils/objects.py", line 42, in __get__
    return obj.__dict__[self.__name__]
KeyError: 'scheduler'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/lib/python3.6/shelve.py", line 111, in __getitem__
    value = self.cache[key]
KeyError: 'entries'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/celery/beat.py", line 481, in _create_schedule
    self._store[str('entries')]
  File "/usr/lib/python3.6/shelve.py", line 113, in __getitem__
    f = BytesIO(self.dict[key.encode(self.keyencoding)])
KeyError: b'entries'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/billiard/process.py", line 327, in _bootstrap
    self.run()
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/celery/beat.py", line 630, in run
    self.service.start(embedded_process=True)
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/celery/beat.py", line 545, in start
    humanize_seconds(self.scheduler.max_interval))
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/kombu/utils/objects.py", line 44, in __get__
    value = obj.__dict__[self.__name__] = self.__get(obj)
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/celery/beat.py", line 589, in scheduler
    return self.get_scheduler()
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/celery/beat.py", line 584, in get_scheduler
    lazy=lazy,
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/celery/beat.py", line 424, in __init__
    Scheduler.__init__(self, *args, **kwargs)
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/celery/beat.py", line 202, in __init__
    self.setup_schedule()
  File "/usr/lib/sillonlorrain-media/lib/python3.6/site-packages/celery/beat.py", line 452, in setup_schedule
    self._create_schedule()
  [HIDDEN]
  File "/usr/lib/python3.6/shelve.py", line 125, in __setitem__
    self.dict[key.encode(self.keyencoding)] = f.getvalue()
_dbm.error: cannot add item to database
```

## Checklist
This report is from my dev env but prod is the same except broker and cache access.
```
CELERY_ACCEPT_CONTENT: ['msgpack']
CELERY_BEAT_SCHEDULE: {
    'clear-sessions': {   'schedule': <crontab: 0 0 * * * (m/h/d/dM/MY)>,
                          'task': 'sessions.tasks.clear_sessions'},
    'flush-logs': {   'schedule': <crontab: 0 0 * * * (m/h/d/dM/MY)>,
                      'task': 'clients.tasks.flush_logs'},
    'harvest-presta': {   'schedule': <crontab: 0 0 * * * (m/h/d/dM/MY)>,
                                     'task': 'feed_importers.presta.tasks.harvest_presta'},
    'harvest-presta2': {   'schedule': <crontab: 0 1 * * * (m/h/d/dM/MY)>,
                          'task': 'feed_importers.presta2.tasks.harvest_presta2'},
    'harvest-presta3': {   'schedule': <crontab: 0 5,6,7,8,9,10,11 * * * (m/h/d/dM/MY)>,
                           'task': 'feed_importers.presta3.tasks.harvest_presta3'},
    'harvest-presta4': {   'schedule': <crontab: 30 7 * * * (m/h/d/dM/MY)>,
                       'task': 'feed_importers.presta4.tasks.harvest_presta4'},
    'import-users': {   'schedule': <crontab: 0 3 * * * (m/h/d/dM/MY)>,
                        'task': 'clients.tasks.import_media_users'},
    'update_bookings': {   'schedule': <crontab: 0 */1 * * * (m/h/d/dM/MY)>,
                           'task': 'loans.tasks.update_bookings'},
    'update_ended_book_loans': {   'schedule': <crontab: */5 * * * * (m/h/d/dM/MY)>,
                                   'task': 'loans.tasks.update_ended_book_loans'},
    'update_orders': {   'schedule': <crontab: 0 18 * * * (m/h/d/dM/MY)>,
                         'task': 'loans.tasks.update_orders'}}
CELERY_BROKER_URL: 'amqp://media:********@rabbitmq:5672/mediavhost'
CELERY_BROKER_USE_SSL: False
CELERY_RESULT_BACKEND: 'cache+memcached://memcached:11211/'
CELERY_RESULT_EXCHANGE: 'media_results'
CELERY_RESULT_EXPIRES: 86400
CELERY_RESULT_PERSISTENT: True
CELERY_RESULT_SERIALIZER: 'msgpack'
CELERY_TASK_DEFAULT_QUEUE: 'media_celery'
CELERY_TASK_ROUTES: {
    'media.tasks.delete_list_by_id_presta': {'queue': 'indexation'},
    'media.tasks.update_books_by_ean_13': {'queue': 'indexation'},
    'media.tasks.update_list_by_slug': {'queue': 'indexation'},
    'media.tasks.update_object_list_highlight': {'queue': 'indexation'},
    'search.tasks.delete_object': {'queue': 'indexation'},
    'search.tasks.delete_object_list': {'queue': 'indexation'},
    'search.tasks.update_linked_medias': {'queue': 'indexation'},
    'search.tasks.update_object': {'queue': 'indexation'},
    'search.tasks.update_object_list': {'queue': 'indexation'}}
CELERY_TASK_SERIALIZER: 'msgpack'
CELERY_TIMEZONE: 'Europe/Paris'

```
## Steps to reproduce
Sorry i dunno.

## Expected behavior
I investiguated source code and there is a process to destroy and recreate corrupted scheduler database but it does not catch my exception.

So if we can't find my mistake, i think i'll fork to add a catch.

My actual "fix process" is to delete celerybeat-schedule file and restart my systemd service.

## Actual behavior
After release this error occur, not often but implies beats are not working unitl i delete the scheduler database by hand.

Thank you for your time !

### Additional contract requirements

- If a `dbm.error` occurs while initializing the persistent scheduler’s entries, treat the store as corrupted, recover by recreating it, and allow the scheduler to continue operating.
