The plugin fails to parse XML with doctype
The XML I have (from the jhipster project defaults)
```
<?xml version="1.0"?>
<!DOCTYPE module PUBLIC "-//Puppy Crawl//DTD Check Configuration 1.3//EN"
        "https://www.puppycrawl.com/dtds/configuration_1_3.dtd">
<module name="Checker">

    <!-- Configure checker to use UTF-8 encoding -->
    <property name="charset" value="UTF-8"/>
    <!-- Configure checker to run on files with these extensions -->
    <property name="fileExtensions" value=""/>
    <!-- For detailed checkstyle configuration, see https://github.com/spring-io/nohttp/tree/master/nohttp-checkstyle -->
    <module name="io.spring.nohttp.checkstyle.check.NoHttpCheck">
        <property name="whitelist" value="http://maven.apache.org/POM/4.0.0&#10;
            http://www.w3.org/2001/XMLSchema-instance&#10;http://maven.apache.org/maven-v4_0_0.xsd"/>
    </module>
    <!-- Allow suppression with comments
       // CHECKSTYLE:OFF
       ... ignored content ...
       // CHECKSTYLE:ON
    -->
    <module name="SuppressWithPlainTextCommentFilter"/>
</module>
```

The error I get
```
[error] checkstyle.xml: Error: Error parsing XML
[error]     at Object.parse (/home/user/node_modules/@prettier/plugin-xml/src/parse.js:7:11)
[error]     at Object.parse (/home/user/node_modules/prettier/bin-prettier.js:9743:19)
[error]     at coreFormat (/home/user/node_modules/prettier/bin-prettier.js:13258:23)
[error]     at format (/home/user/node_modules/prettier/bin-prettier.js:13516:73)
[error]     at formatWithCursor (/home/user/node_modules/prettier/bin-prettier.js:13532:12)
[error]     at Object.formatWithCursor (/home/user/node_modules/prettier/bin-prettier.js:44213:15)
[error]     at format$1 (/home/user/node_modules/prettier/bin-prettier.js:45598:19)
[error]     at /home/user/node_modules/prettier/bin-prettier.js:45792:16
[error]     at /home/user/node_modules/prettier/bin-prettier.js:45731:14
[error]     at Array.forEach (<anonymous>)
```


NPM modules I have
```
"prettier": "1.19.1",
"@prettier/plugin-xml": "^0.4.0",
```

If I remove the doctype then it works correctly. Not sure if it is related to https://github.com/prettier/plugin-xml/issues/5

### Additional contract requirements

- When formatting this DOCTYPE declaration, output exactly `<!DOCTYPE module PUBLIC "-//Puppy Crawl//DTD Check Configuration 1.3//EN"\n  "https://www.puppycrawl.com/dtds/configuration_1_3.dtd">`.
