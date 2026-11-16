Improve debug level logging
We currently don't capture a lot of useful information when logging is set to debug. This can make identifying support issues tough

The configuration that we collect at the top of the log is very useful, but once we get to actually recording the requests, we don't have much visibility. As seen at the bottom of the logs, all we say is when a request starts and ends, and we are missing some valuable information like what time the request started and ended, as well as some of the payload/request information (total duration, maybe complete_spans count?)


For example, here's a script of what debug logs looks like:

```
Defaults : app_server =
Python   : application_root = /var/www/a
Defaults : collect_remote_ip = True
Null     : core_agent_config_file = None
Defaults : core_agent_dir = /tmp/scout_apm_core
Defaults : core_agent_download = True
Defaults : core_agent_launch = True
Null     : core_agent_log_file = None
Defaults : core_agent_log_level = info
Defaults : core_agent_permissions = 700
Defaults : core_agent_socket_path = tcp://127.0.0.1:6590
Defaults : core_agent_version = v1.3.0
Defaults : disabled_instruments = []
Defaults : download_url = https://s3-us-west-1.amazonaws.com/scout-public-downloads/apm_core_agent/release
Defaults : framework =
Defaults : framework_version =
Defaults : hostname = None
Null     : ignore = None
Null     : log_level = None
Python   : monitor = True
Python   : name = asdf
Defaults : revision_sha =
Defaults : scm_subdirectory =
Defaults : shutdown_message_enabled = True
Defaults : shutdown_timeout_seconds = 2.0
Instrumenting elasticsearch.
Couldn't import elasticsearch.Elasticsearch - probably not installed.
Instrumenting Jinja2.
Instrumenting pymongo.
Couldn't import pymongo.Collection - probably not installed.
Instrumenting redis.
Instrumenting urllib3.
APM Launching on PID: 40353
Core Agent manifest json: {'version': '1.3.0', 'core_agent_version': '1.3.0', 'core_agent_binary': 'core-agent', 'core_agent_binary_sha256': '51d66d40fe1c3198f82310b21b2023asdfasdfasdfasdfasdfsadfsadfsdaf}
Configuration Loaded:
Defaults : app_server =
Python   : application_root = /var/www/a
Defaults : collect_remote_ip = True
Null     : core_agent_config_file = None
Defaults : core_agent_dir = /tmp/scout_apm_core
Defaults : core_agent_download = True
Defaults : core_agent_launch = True
Null     : core_agent_log_file = None
Defaults : core_agent_log_level = info
Defaults : core_agent_permissions = 700
Defaults : core_agent_socket_path = tcp://127.0.0.1:6590
Defaults : core_agent_version = v1.3.0
Defaults : disabled_instruments = []
Defaults : download_url = https://s3-us-west-1.amazonaws.com/scout-public-downloads/apm_core_agent/release
Defaults : framework =
Defaults : framework_version =
Defaults : hostname = None
Null     : ignore = None
Null     : log_level = None
Python   : monitor = True
Python   : name = a
Defaults : revision_sha =
Defaults : scm_subdirectory =
Defaults : shutdown_message_enabled = True
Defaults : shutdown_timeout_seconds = 2.0
Instrumenting elasticsearch.
Couldn't import elasticsearch.Elasticsearch - probably not installed.
Instrumenting Jinja2.
Instrumenting pymongo.
Couldn't import pymongo.Collection - probably not installed.
Instrumenting redis.
Instrumenting urllib3.
APM Launching on PID: 40355
Core Agent manifest json: {'version': '1.3.0', 'core_agent_version': '1.3.0', 'core_agent_binary': 'core-agent', 'core_agent_binary_sha256': '51d66d40fe1c3198f82310b21b202315cfc326207d26ffbasdfasdffdsdf'}
CoreAgentSocketThread attempt 1, connecting to tcp://127.0.0.1:6590, PID: 40354, Thread: <CoreAgentSocketThread(Thread-1, started daemon sdfgsdfg)>
CoreAgentSocketThread connected
Registering with app=a key_prefix=aaa key_format_validated=True host=None
CoreAgentSocketThread attempt 1, connecting to tcp://127.0.0.1:6590, PID: 40353, Thread: <CoreAgentSocketThread(Thread-1, started daemon sdfgsdfg)>
CoreAgentSocketThread connected
Registering with app=a key_prefix=aaa key_format_validated=True host=None
CoreAgentSocketThread attempt 1, connecting to tcp://127.0.0.1:6590, PID: 40355, Thread: <CoreAgentSocketThread(Thread-1, started daemon asdf)>
CoreAgentSocketThread connected
Registering with app=a key_prefix=aaa key_format_validated=True host=None
CoreAgentSocketThread stopping.
CoreAgentSocketThread stopped.
CoreAgentSocketThread stopping.
Installed DB connection created signal handler
CoreAgentSocketThread stopped.
Monkey patched Templates
Installed DB connection created signal handler
Monkey patched Templates
CoreAgentSocketThread stopping.
CoreAgentSocketThread stopped.
Installed DB connection created signal handler
Monkey patched Templates
Starting request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaaaa
Stopping request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaaaa
Starting request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaaaa
Stopping request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaaaa
Starting request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaabb
Stopping request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaabb
Starting request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaabb
Stopping request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaabb
Starting request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaaacc
Stopping request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaacc
Starting request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaacc
Stopping request: req-81f9727b-15d1-47fb-9ed0-ab7bf1aaacc
```

### Additional contract requirements

- The request summary must be logged at DEBUG level from `scout_apm.core.tracked_request` using this message format: `Request {request_id} start_time={start_time} end_time={end_time} duration={duration} active_spans={active_spans} complete_spans={complete_spans} tags={tags} hit_max={hit_max} is_real_request={is_real_request}`. Use the request ID, the string representations of the start and end times, the elapsed duration in seconds, the counts of active spans, complete spans, and tags, and the values of `hit_max` and `is_real_request`.
