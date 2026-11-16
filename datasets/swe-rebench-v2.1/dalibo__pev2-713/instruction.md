Missing Sort in a Merge Join
**Describe the bug**

Only one Sort is shown in a Merge with 2 Sorts

**To Reproduce**

https://explain.dalibo.com/plan/9c9cbccbc23febhc#plan

**Expected behavior**

The same plan without VERBOSE is ok : https://explain.dalibo.com/plan/b1dea32h3de72bd5

The same plan **with**  VERBOSE & FORMAT JSON is okay : https://explain.dalibo.com/plan/29c296900beegbg2


**Screenshots**

![Image](https://github.com/user-attachments/assets/2faa6777-a153-4274-b68a-ec10eaa34084)
