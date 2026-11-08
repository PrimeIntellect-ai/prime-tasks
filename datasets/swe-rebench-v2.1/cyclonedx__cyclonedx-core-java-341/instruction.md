LicensesChoice returns only one license
Version `8.0.0` does not return multiple licenses.
In Version `7.3.2` there were multiple versions.

Example `jakarta.servlet-api` defines two licenses in the [pom.xml](https://repo1.maven.org/maven2/jakarta/servlet/jakarta.servlet-api/6.0.0/jakarta.servlet-api-6.0.0.pom).

When I use the `cyclonedx-maven-plugin` to generate a bom.json the output is correct.
```
      "licenses" : [
        {
          "license" : {
            "id" : "EPL-2.0"
          }
        },
        {
          "license" : {
            "id" : "GPL-2.0-with-classpath-exception"
          }
        }
      ]
```
But the `LicenseChoice` does not have anymore both licenses.

Is this a bug? Or why was this changed?
