Bug: A new line is added between nolint directive and import block
### What version of GCI are you using?

<pre>
$ gci -v
gci version 0.9.0
</pre>

### Reproduce Steps

<pre>
git clone https://github.com/PlanitarInc/gci-bug
cd gci-bug
gci diff --skip-generated -s standard,default .
</pre>


### What did you expect to see?

There should no diff. The `nolint` directive added to the whole import block should stay where it is.


### What did you see instead?

The tool suggests to add a new line between the import block and the `nolint` directive. Doing this will make the directive useless.

<pre>
$ gci diff --skip-generated -s standard,default .
--- main.go
+++ main.go
@@ -1,6 +1,7 @@
 package main

 //nolint:custom1
+
 import (
 	"fmt"
 	"strconv"
</pre>
