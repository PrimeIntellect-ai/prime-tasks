Allow single-line formatting for class attribute with multiple values
**Describe the bug**
The linter rule requires multi-line formatting for elements with only a single attribute, specifically when it comes to the class attribute that can contain multiple classes

**To Reproduce**
Steps to reproduce the behavior:

1. What is the exact code you are analyzing?
```
<UDashboardPanelContent class="p-2 gap-6">
....
</UDashboardPanelContent>
```

2. What is the output you are getting?
```
  Element <UDashboardPanelContent> should have its attributes on separate lines 🚨
```

**Expected behavior**
I expected the linter to allow single-line formatting when there is a class attribute with multiple classes

**Used version number of vue-mess-detector:**
^0.62.0

**Used version number of node & yarn:**
pnpm@9.12.1
