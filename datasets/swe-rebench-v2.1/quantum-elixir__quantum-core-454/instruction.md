hidden duplicate job (or partial update) when calling add_job with named job (same name)
given this Scheduler

```
defmodule YourApp.Scheduler do
  use Quantum.Scheduler,
    otp_app: :your_app

  import Crontab.CronExpression

  def first_version() do
    new_job()
    |> Quantum.Job.set_name(:test)
    |> Quantum.Job.set_schedule(~e[*/5 * * * * *]e)
    |> Quantum.Job.set_task(fn ->
      IO.puts("#{Timex.now()} - first hello")
    end)
    |> add_job()
  end

  def second_version() do
    new_job()
    |> Quantum.Job.set_name(:test)
    |> Quantum.Job.set_schedule(~e[*/10 * * * * *]e)
    |> Quantum.Job.set_task(fn ->
      IO.puts("#{Timex.now()} - second hello")
    end)
    |> add_job()
  end

end
```

start by creating a job (iex prompts reorganized):

```
➤ iex -S mix
Erlang/OTP 21 [erts-10.1.1] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [hipe]

Compiling 1 file (.ex)
Interactive Elixir (1.7.4) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> Logger.configure(level: :info)
:ok
iex(2)> import YourApp.Scheduler
YourApp.Scheduler
iex(3)> jobs()
[]
iex(4)> first_version()
:ok
2019-01-15 20:54:03.618109Z - first hello
2019-01-15 20:54:03.618139Z - first hello
2019-01-15 20:54:03.618127Z - first hello
2019-01-15 20:54:03.618139Z - first hello
2019-01-15 20:54:05.001217Z - first hello
2019-01-15 20:54:10.001246Z - first hello
iex(5)> jobs()
[
  test: %Quantum.Job{
    name: :test,
    overlap: true,
    run_strategy: %Quantum.RunStrategy.Random{nodes: :cluster},
    schedule: ~e[*/5 * * * * * *]e,
    state: :active,
    task: #Function<0.60421259/0 in YourApp.Scheduler.first_version/0>,
    timezone: :utc
  }
]
2019-01-15 20:54:15.001190Z - first hello
2019-01-15 20:54:20.001329Z - first hello
```

and then add a different job with the same name:

```
iex(6)> second_version()
:ok
2019-01-15 20:54:25.001364Z - first hello
2019-01-15 20:54:30.001232Z - first hello
2019-01-15 20:54:30.001357Z - second hello
2019-01-15 20:54:35.001256Z - first hello
2019-01-15 20:54:40.001469Z - first hello
2019-01-15 20:54:40.001632Z - second hello
2019-01-15 20:54:45.001235Z - first hello
iex(7)> jobs()
[
  test: %Quantum.Job{
    name: :test,
    overlap: true,
    run_strategy: %Quantum.RunStrategy.Random{nodes: :cluster},
    schedule: ~e[*/10 * * * * * *]e,
    state: :active,
    task: #Function<1.60421259/0 in YourApp.Scheduler.second_version/0>,
    timezone: :utc
  }
]
2019-01-15 20:54:50.001341Z - first hello
2019-01-15 20:54:50.001427Z - second hello
```

and then the second version again:

```
iex(8)> second_version()
:ok
2019-01-15 20:54:55.001055Z - first hello
2019-01-15 20:55:00.001276Z - first hello
2019-01-15 20:55:00.001342Z - second hello
2019-01-15 20:55:00.001369Z - second hello
iex(9)> jobs()
[
  test: %Quantum.Job{
    name: :test,
    overlap: true,
    run_strategy: %Quantum.RunStrategy.Random{nodes: :cluster},
    schedule: ~e[*/10 * * * * * *]e,
    state: :active,
    task: #Function<1.60421259/0 in YourApp.Scheduler.second_version/0>,
    timezone: :utc
  }
]
2019-01-15 20:55:05.001078Z - first hello
2019-01-15 20:55:10.001225Z - first hello
2019-01-15 20:55:10.001294Z - second hello
2019-01-15 20:55:10.001324Z - second hello
2019-01-15 20:55:15.001341Z - first hello
2019-01-15 20:55:20.001707Z - first hello
2019-01-15 20:55:20.001809Z - second hello
2019-01-15 20:55:20.001859Z - second hello
```

and finally deactivate and reactivate the job by name:

```
iex(10)> deactivate_job(:test)
:ok
iex(11)> activate_job(:test)
2019-01-15 20:55:33.518137Z - second hello
2019-01-15 20:55:40.001193Z - second hello
2019-01-15 20:55:50.001085Z - second hello
```

=> When adding a job with the same name as a previous job, both version will be running but only the second one with be visible when listing jobs with `jobs/0` (the same happens when adding the same job twice)

=> `deactivate_job/1` followed by `activate_job/1` fixes it, i.e. the zombies are gone

PS also when adding a job, it might be run multiple times before the first schedules, e.g.
```
2019-01-15 20:54:03.618109Z - first hello
2019-01-15 20:54:03.618139Z - first hello
2019-01-15 20:54:03.618127Z - first hello
2019-01-15 20:54:03.618139Z - first hello
```

### Additional contract requirements

When `add_job/2` is called with a job whose name is already registered, the previously registered job must be replaced instead of duplicated: the previous version must no longer run and the new version must be the one returned by `jobs/0`.

The replacement is observable on the `Quantum.JobBroadcaster` event stream, which must publish:

- `{:delete, old_job}` followed by `{:add, new_job}` when an active job is replaced by an active job;
- `{:delete, old_job}` and no `{:add, _}` when an active job is replaced by an inactive job;
- `{:add, new_job}` and no `{:delete, _}` when an inactive job is replaced by an active job;
- no event when an inactive job is replaced by an inactive job.

`old_job` is the previously registered `Quantum.Job` struct and `new_job` is the replacement.
