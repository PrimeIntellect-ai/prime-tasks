IG Publisher fails due to missing parameters
Apparently the IG Publisher instituted a new requirement that the ImplementationGuide resource contain parameters for `releaselabel` and `copyrightyear`, which is kind of funny since parameters use a `required` valueset and neither of those codes are in it.  Oh well.

```
onGenerate.infoFile:
     [xslt] Processing /Users/cmoesel/dev/fhir/sushi/build/template/onGenerate-ig-working.xml to /Users/cmoesel/dev/fhir/sushi/build/temp/pages/_data/info.json
     [xslt] Loading stylesheet /Users/cmoesel/dev/fhir/sushi/build/template/scripts/onGenerate.genJson.xslt
IG must include a definition parameter with a code of 'copyrightyear'.  Value can be '2020+' or some similar value.
     [xslt] /Users/cmoesel/dev/fhir/sushi/build/template/scripts/onGenerate.genJson.xslt:11: Fatal Error! Processing terminated by xsl:message at line 11 in onGenerate.genJson.xslt
     [xslt] Failed to process /Users/cmoesel/dev/fhir/sushi/build/template/onGenerate-ig-working.xml
Publishing Content Failed: Fatal error during transformation using /Users/cmoesel/dev/fhir/sushi/build/template/scripts/onGenerate.genJson.xslt: Processing terminated by xsl:message at line 11 in onGenerate.genJson.xslt; SystemID: file:/Users/cmoesel/dev/fhir/sushi/build/template/scripts/onGenerate.genJson.xslt; Line#: 11; Column#: -1 (01:52.0302)
                                                                                 (01:52.0302)
Use -? to get command line help                                                  (01:52.0302)
                                                                                 (01:52.0303)
Stack Dump (for debugging):                                                      (01:52.0303)
/Users/cmoesel/dev/fhir/sushi/build/template/scripts/ant.xml:78: Fatal error during transformation using /Users/cmoesel/dev/fhir/sushi/build/template/scripts/onGenerate.genJson.xslt: Processing terminated by xsl:message at line 11 in onGenerate.genJson.xslt; SystemID: file:/Users/cmoesel/dev/fhir/sushi/build/template/scripts/onGenerate.genJson.xslt; Line#: 11; Column#: -1
	at org.apache.tools.ant.taskdefs.XSLTProcess.handleTransformationError(XSLTProcess.java:1435)
	at org.apache.tools.ant.taskdefs.XSLTProcess.process(XSLTProcess.java:880)
	at org.apache.tools.ant.taskdefs.XSLTProcess.execute(XSLTProcess.java:408)
	at org.apache.tools.ant.UnknownElement.execute(UnknownElement.java:292)
	at sun.reflect.GeneratedMethodAccessor4.invoke(Unknown Source)
	at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.lang.reflect.Method.invoke(Method.java:498)
	at org.apache.tools.ant.dispatch.DispatchUtils.execute(DispatchUtils.java:99)
	at org.apache.tools.ant.Task.perform(Task.java:350)
	at org.apache.tools.ant.Target.execute(Target.java:449)
	at org.apache.tools.ant.Target.performTasks(Target.java:470)
	at org.apache.tools.ant.Project.executeSortedTargets(Project.java:1388)
	at org.apache.tools.ant.Project.executeTarget(Project.java:1361)
	at org.hl7.fhir.igtools.templates.Template.runScriptTarget(Template.java:184)
	at org.hl7.fhir.igtools.templates.Template.beforeGenerateEvent(Template.java:341)
	at org.hl7.fhir.igtools.publisher.Publisher.templateBeforeGenerate(Publisher.java:2852)
	at org.hl7.fhir.igtools.publisher.Publisher.generate(Publisher.java:4255)
	at org.hl7.fhir.igtools.publisher.Publisher.createIg(Publisher.java:785)
	at org.hl7.fhir.igtools.publisher.Publisher.execute(Publisher.java:663)
	at org.hl7.fhir.igtools.publisher.Publisher.main(Publisher.java:6893)
```

### Additional contract requirements

- The parameters are entries in the ImplementationGuide resource's `definition.parameter` array, each identified by its `code`.
- The `copyrightyear` parameter's value must be a copyright year, such as `2020+` or a similar value (for example a year range like `2020-2024`).
