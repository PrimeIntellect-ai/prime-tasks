Excessive Empty lines in logs/Console when executing Tests
### Background
In previous version of Gauge `v1.0.6` with Gauge-Java `v0.7.2`, gauge would output to the console one line at a time. It would also add **P** for Pass for each step executed on the same line. This would save space and make the logs relatively readable.

### Expected behavior
Proper logs without excessive new lines and without empty lines.

### Actual behavior
There is an excessive amount of new lines with a lot of them being empty. The "P" is also now one P per line. This makes the Logs really large and very difficult to navigate and find issues. We are running 1000+ test cases with more then 10 steps for most of those scenarios. If we run the entire suite, it becomes too inefficient to use the log. This behaviour is even worse when running in parallel mode. I am unsure if this is an issue with Gauge or Gauge-Java. I use Gauge with Java and Maven.

### Steps to reproduce
1. Create a Gauge Java Project > `gauge init java_maven`
2. Create some random steps for each scenario. Add 10 steps to the scenario
3. Run the Test using Maven > `mvn gauge:execute` or `mvn clean test`
4. Run the Test using Maven > `mvn gauge:execute -DinParallel=true -Dnodes=2` or `mvn clean test  -DinParallel=true -Dnodes=2`
5. Attached Sample project and logs attached.

### Attachments
[defects-example.zip](https://github.com/getgauge/gauge-java/files/4600466/defects-example.zip)
[output.log](https://github.com/getgauge/gauge-java/files/4600415/output.log)
[output-parallel.log](https://github.com/getgauge/gauge-java/files/4600417/output-parallel.log)


### Gauge version
```
Gauge version: 1.0.8
Commit Hash: 28617ea

Plugins
-------
flash (0.0.2)
go (0.1.4)
html-report (4.0.10)
java (0.7.7)
json-report (0.3.3)
screenshot (0.0.1)
spectacle (0.1.4)
xml-report (0.2.3)
```
