Cucumber StepDefs -  Please ensure only one glue class configures the spring context
##### **Overview of the issue**

JHipster creates Cucumber test for User which is great but a second test cannot be created because of a change to how Cucumber works.

https://github.com/cucumber/cucumber-jvm/issues/1420 describes the problem and a solution.

> Spring is setup such that only one class can provide the context configuration. Past implementations of cucumber picked an arbitrary class in an undefined manner. There was some logic to prevent you from shooting yourself in the foot.

The error:
```
[ERROR] initializationError(com.example.foo.cucumber.CucumberTest)  Time elapsed: 0.008 s  <<< ERROR!
cucumber.runtime.CucumberException: Glue class class com.example.foo.cucumber.stepdefs.UserStepDefs and class com.example.foo.cucumber.stepdefs.UserStepDefs2 both attempt to configure the spring context. Please ensure only one glue class configures the spring context
```

##### **Motivation for or Use Case**

I want to create Cucumber tests.

##### **Reproduce the error**

Create a working folder:
```
mkdir tmp
cd tmp
```
Create basic JDL file, `jdl.jh`, file:
```
application {
  config {
    baseName foo
    packageName com.example.foo
    testFrameworks [cucumber]
  }
  entities *
}
```

Generate the application from the JDL file:
```
jhipster import-jdl jdl.jh
```

Test with no errors:
```
mvnw test
```

Create a second test:
`src/test/java/com/example/foo/cucumber/stepdefs/UserStepDefs2.java`
```
package com.example.foo.cucumber.stepdefs;

import com.example.foo.web.rest.UserResource;
import cucumber.api.java.Before;
import cucumber.api.java.en.Then;
import cucumber.api.java.en.When;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

public class UserStepDefs2 extends StepDefs {

    @Autowired
    private UserResource userResource;

    private MockMvc restUserMockMvc;

    @Before
    public void setup() {
        this.restUserMockMvc = MockMvcBuilders.standaloneSetup(userResource).build();
    }

}
```

Test again and get the following error:
```
[INFO] Running com.example.foo.cucumber.CucumberTest
[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0, Time elapsed: 0.622 s <<< FAILURE! - in com.example.foo.cucumber.CucumberTest
[ERROR] initializationError(com.example.foo.cucumber.CucumberTest)  Time elapsed: 0.007 s  <<< ERROR!
cucumber.runtime.CucumberException: Glue class class com.example.foo.cucumber.stepdefs.UserStepDefs and class com.example.foo.cucumber.stepdefs.UserStepDefs2 both attempt to configure the spring context. Please ensure only one glue class configures the spring context
```

##### **Related issues**

https://github.com/cucumber/cucumber-jvm/issues/1420

##### **Suggest a Fix**

[HIDDEN]
Now `mvnw test` passes.

##### **JHipster configuration**

##### **JHipster Version(s)**

```
foo@0.0.0 /Users/jeffjohnson/Projects/adt/jhipster-test/tmp
└── generator-jhipster@5.7.2

```


##### **JHipster configuration, a `.yo-rc.json` file generated in the root folder**


<details>
<summary>.yo-rc.json file</summary>
<pre>
{
  "generator-jhipster": {
    "databaseType": "sql",
    "devDatabaseType": "h2Disk",
    "enableHibernateCache": true,
    "enableSwaggerCodegen": false,
    "enableTranslation": true,
    "jhiPrefix": "jhi",
    "languages": [
      "en",
      "fr"
    ],
    "messageBroker": false,
    "nativeLanguage": "en",
    "packageName": "com.example.foo",
    "packageFolder": "com/example/foo",
    "prodDatabaseType": "mysql",
    "searchEngine": false,
    "serviceDiscoveryType": false,
    "skipClient": false,
    "skipServer": false,
    "testFrameworks": [
      "cucumber"
    ],
    "websocket": false,
    "baseName": "foo",
    "jhipsterVersion": "5.7.2",
    "buildTool": "maven",
    "skipUserManagement": false,
    "clientPackageManager": "npm",
    "applicationType": "monolith",
    "authenticationType": "jwt",
    "cacheProvider": "ehcache",
    "clientFramework": "angularX",
    "serverPort": "8080",
    "useSass": true,
    "jwtSecretKey": "bXktc2VjcmV0LXRva2VuLXRvLWNoYW5nZS1pbi1wcm9kdWN0aW9uLWFuZC10by1rZWVwLWluLWEtc2VjdXJlLXBsYWNl",
    "otherModules": []
  },
  "entities": []
}
</pre>
</details>


##### **JDL for the Entity configuration(s) `entityName.json` files generated in the `.jhipster` directory**

<details>
<summary>JDL entity definitions</summary>

<pre>

</pre>
</details>


##### **Environment and Tools**

java version "1.8.0_191"
Java(TM) SE Runtime Environment (build 1.8.0_191-b12)
Java HotSpot(TM) 64-Bit Server VM (build 25.191-b12, mixed mode)

git version 2.19.1

node: v11.6.0

npm: 6.5.0

yeoman: 2.0.5

Docker version 18.09.0, build 4d60db4

docker-compose version 1.21.2, build a133471
