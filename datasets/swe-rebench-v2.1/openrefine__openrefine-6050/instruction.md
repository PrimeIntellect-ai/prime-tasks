case-sensitive sort does not produce expected result
<!-- Describe the bug - Please add a clear and concise description of the bug above this line. You can delete this line if you want. It will be hidden in the final bug report -->

### To Reproduce
Steps to reproduce the behavior:

1. Create a project with the supplied "temp.csv"
![image](https://github.com/OpenRefine/OpenRefine/assets/42559726/119803ef-f1a1-4554-b72a-2717e26d84d3)

2. Configure a sort on the single column as follows
![image](https://github.com/OpenRefine/OpenRefine/assets/42559726/9f56aff4-45fa-4af0-a54b-e8178c424c01)

3. Apply the sort by "Reorder rows permanently"
![image](https://github.com/OpenRefine/OpenRefine/assets/42559726/8cee7a26-63e9-4630-aafc-c9cb7f02e4c6)


### Current Results
<!-- What results occurred or were shown. -->
Sort only moves the character "c"

### Expected Behavior
<!-- A clear and concise description of what you expected to happen or to show. -->
Here an example within Excel on what the sort should be showing
![image](https://github.com/OpenRefine/OpenRefine/assets/42559726/1182ec7c-0a00-435f-af72-26a0e61032dd)

### Versions<!--  (please complete the following information)-->
 - Operating System: Windows 10
 - Browser Version:  Chromium 116.0.5845.180
 - JRE or JDK Version: using the "openrefine-win-with-java-3.7.4.zip" release
 - OpenRefine: openrefine-win-with-java-3.7.4

### Datasets
[temp.csv](https://github.com/OpenRefine/OpenRefine/files/12572271/temp.csv)

### Additional context
<!-- Add any other context about the problem here. -->
Looking at the oldest version of JDK that OpenRefine supports: https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/text/Collator.html#TERTIARY

https://github.com/OpenRefine/OpenRefine/blob/2b07cfa5ced9bcfdc6d485fe1849af1c79ac320a/main/src/com/google/refine/sorting/StringCriterion.java#L57C50-L57C50

[HIDDEN]
