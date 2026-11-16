[BUG] - A long running job can not be cancelled when run s.StopJobs()
### Describe the bug

A long running job can not be cancelled when run s.StopJobs(), and always return "timed out waiting for jobs to finish"

### To Reproduce

Steps to reproduce the behavior:

1. Create a Scheduler and add a long running job and set WithStartImmediately
2. start the scheduler
3. wait for a while before the job is completed, run s.StopJobs()
4. timeout error returns

### Version

v2.14.2

### Expected behavior

if the job has a ctx field, Scheduler should cancel it when running StopJobs() instead of waiting for it

### Additional context

<!---Add any other context about the problem here.--->
