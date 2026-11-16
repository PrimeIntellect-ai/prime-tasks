K8SSAND-1875 ⁃ JVM options for DSE should map to the jvm8 file, not the jvm11 one
For now we run DSE using jdk8 images, but have mappings for the options that put them in the jvm11 file.
We should pin these options to the jvm8 file and later figure out a way to dynamically point to the right file, depending on the jdk in use.

┆Issue is synchronized with this [Jira Task](https://k8ssandra.atlassian.net/browse/K8SSAND-1875) by [Unito](https://www.unito.io)
┆Issue Number: K8SSAND-1875
┆Priority: Medium
┆Link To Issue: https://k8ssandra.atlassian.net/browse/K8SSAND-1875
