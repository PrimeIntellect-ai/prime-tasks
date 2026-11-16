Maven Dependencies do not take precedence over "auto determined" licence
**prologue**
we have a project that is using several components from the Jersey framework
* com.sun.jersey:jersey-core
* com.sun.jersey:jersey-client
* com.sun.jersey.contribs:jersey-apache-client4

in maven these libs are labled with several licences (CDDL 1.1, GPL 1.1....)
see e.g.:
* https://mvnrepository.com/artifact/com.sun.jersey.contribs/jersey-apache-client4
* https://mvnrepository.com/artifact/com.sun.jersey.contribs/jersey-apache-client4
* https://mvnrepository.com/artifact/org.glassfish.jersey.core/jersey-client

.... and actually all these lables are incorrect as the jersey project itself states that all components are licenced under EPL 2 / GPL 2)
see: https://jersey.github.io/license.html

In order to make the report correct again I now added a maven licence mapping via the administration ui of the plugin
![image](https://user-images.githubusercontent.com/4927859/60875154-951c3480-a239-11e9-9c3f-0d7cbb07012d.png)


**issue**
* run a scan on such a project
* **expectation** : these 3 components of jersey are reported as EPL 2 (as hopefully my explicit maven mapping takes precedence over the automatically determined license)
* **actual** : these 3 components of jersey are reported as GPL 2
![image](https://user-images.githubusercontent.com/4927859/60875280-ce54a480-a239-11e9-9112-766602a6c6b5.png)


**context**
* sonarqube Community EditionVersion 7.7 (build 23042)
* plugin version v3 beta 3
