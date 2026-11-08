Exception when set DoW as Sunday using QUARTZ definition
In order to verify the problem, replace the day of the week to Sunday on the following test
https://github.com/jmrozanec/cron-utils/blob/0759550fa7a18067a0decd5953acd4165f0bf0ab/src/test/java/com/cronutils/model/definition/CronDefinitionBuilderTest.java#L177
