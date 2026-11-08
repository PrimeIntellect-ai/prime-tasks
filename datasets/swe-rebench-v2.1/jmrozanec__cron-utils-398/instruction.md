Incorrect next execution time for spring cron expression with day of week
version 9.0.1
With the cron expression like 0 0 9 * * MON
Where it is assumed to be fired on 9 o'clock of monday ,but executionTime.nextExecution(now) always return 9 o'clock of the next day,whether the next day is monday or not.

CronDefinition cronDefinition = CronDefinitionBuilder.instanceDefinitionFor(SPRING);
CronParser parser = new CronParser(cronDefinition);
ExecutionTime executionTime = ExecutionTime.forCron(parser.parse("0 0 9 * * MON"));
ZonedDateTime now = ZonedDateTime.now();
ZonedDateTime nextExecution = executionTime.nextExecution(now).get();
