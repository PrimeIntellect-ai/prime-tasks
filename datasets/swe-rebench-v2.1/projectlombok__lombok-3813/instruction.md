[BUG] StackOverflowError when using lombok 1.18.36
**Describe the bug**
I upgraded from 1.18.34 (which worked fine) to 1.18.36 and now I get the following error in eclipse (Version: 2024-09 (4.33.0)) with java version 21:

Lombok has logged too many messages; to avoid memory issues, further lombok logs will be squelched for a while. Restart eclipse to start over.

```
java.lang.StackOverflowError
	at java.base/java.util.regex.Pattern$GroupTail.match(Pattern.java:5000)
	at java.base/java.util.regex.Pattern$LazyLoop.match(Pattern.java:5142)
	at java.base/java.util.regex.Pattern$GroupTail.match(Pattern.java:5000)
	at java.base/java.util.regex.Pattern$BranchConn.match(Pattern.java:4878)
	at java.base/java.util.regex.Pattern$CharProperty.match(Pattern.java:4110)
	at java.base/java.util.regex.Pattern$Branch.match(Pattern.java:4914)
	at java.base/java.util.regex.Pattern$GroupHead.match(Pattern.java:4969)
	at java.base/java.util.regex.Pattern$LazyLoop.match(Pattern.java:5146)
	at java.base/java.util.regex.Pattern$GroupTail.match(Pattern.java:5000)
	at java.base/java.util.regex.Pattern$BranchConn.match(Pattern.java:4878)
	at java.base/java.util.regex.Pattern$BmpCharProperty.match(Pattern.java:4134)
	at java.base/java.util.regex.Pattern$Branch.match(Pattern.java:4914)
	at java.base/java.util.regex.Pattern$GroupHead.match(Pattern.java:4969)
	at java.base/java.util.regex.Pattern$LazyLoop.match(Pattern.java:5146)
	at java.base/java.util.regex.Pattern$GroupTail.match(Pattern.java:5000)
	at java.base/java.util.regex.Pattern$BranchConn.match(Pattern.java:4878)
	at java.base/java.util.regex.Pattern$CharProperty.match(Pattern.java:4110)
	at java.base/java.util.regex.Pattern$Branch.match(Pattern.java:4914)
	at java.base/java.util.regex.Pattern$GroupHead.match(Pattern.java:4969)
	at java.base/java.util.regex.Pattern$LazyLoop.match(Pattern.java:5146)
	at java.base/java.util.regex.Pattern$GroupTail.match(Pattern.java:5000)
	at java.base/java.util.regex.Pattern$BranchConn.match(Pattern.java:4878)
	at java.base/java.util.regex.Pattern$CharProperty.match(Pattern.java:4110)
	at java.base/java.util.regex.Pattern$Branch.match(Pattern.java:4914)
	at java.base/
...
...
...
```

**Expected behavior**
No Stackoverflow Error

**Version info (please complete the following information):**
 - Lombok version: 1.18.36
 - Java version: openjdk version "21.0.2" 2024-01-16
 - Eclipse version: Version: 2024-09 (4.33.0)
