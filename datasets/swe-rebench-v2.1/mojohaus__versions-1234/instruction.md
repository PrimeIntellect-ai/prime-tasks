set-property doesn't work as expected if the property is not present in the module
Considering the pom:

```
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>default-group</groupId>
    <artifactId>default-artifact</artifactId>
    <version>1.0</version>
    <packaging>pom</packaging>

    <profiles>
        <profile>
            <id>test-profile</id>
            <properties>
                <dummy-api-version>test-value</dummy-api-version>
            </properties>
            <dependencies>
                <dependency>
                    <groupId>localhost</groupId>
                    <artifactId>dummy-api</artifactId>
                    <version>${dummy-api-version}</version>
                </dependency>
            </dependencies>
        </profile>
    </profiles>
</project>

```
running

`mvn versions:set-property -Dproperty=dummy-api-version -DnewVersion=1.2.3 -DgenerateBackupPoms=false -DprofileId=test-profile`

I'm expecting that the `dummy-api-version` property will be `1.2.3` but it doesn't

to make this works it is necessary to add the same property on the module

```
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>default-group</groupId>
    <artifactId>default-artifact</artifactId>
    <version>1.0</version>
    <packaging>pom</packaging>
    <properties>
        <dummy-api-version>test-value</dummy-api-version>
    </properties>

    <profiles>
        <profile>
            <id>test-profile</id>
            <properties>
                <dummy-api-version>test-value</dummy-api-version>
            </properties>
            <dependencies>
                <dependency>
                    <groupId>localhost</groupId>
                    <artifactId>dummy-api</artifactId>
                    <version>${dummy-api-version}</version>
                </dependency>
            </dependencies>
        </profile>
    </profiles>
</project>
```

even if it changes the value in the profile, it should works even if the property is declared only in the profile
