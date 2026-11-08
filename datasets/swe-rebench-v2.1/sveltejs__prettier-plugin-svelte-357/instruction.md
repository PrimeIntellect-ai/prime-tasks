Handling of multiple HTML comments
Scenario: I try to write to comments on the top of the svelte file.

Expected behavior: They are preserved.
Actual behavior: `prettier-plugin-svelte` seems to push one off and places it before the template part:

```
diff --git a/ts/editor/image-overlay/WithImageConstrained.svelte b/ts/editor/image-overlay/WithImageConstrained.svelte
index 50abe8bdf..13e8e2a40 100644
--- a/ts/editor/image-overlay/WithImageConstrained.svelte
+++ b/ts/editor/image-overlay/WithImageConstrained.svelte
@@ -1,8 +1,4 @@
 <!--
-Copyright: ...
-License: ...
--->
-<!--
 @component
 My comp
 -->
@@ -202,6 +198,12 @@ My comp
     }
 </script>

+<!--
+Copyright: ...
+License: ...
+-->
+
+
 {#if activeImage}
     <slot {toggleActualSize} {active} />
 {/if}
```

### Additional contract requirements

- When formatting a comment immediately above a `<style>` tag, put a blank line between the comment and the tag.
