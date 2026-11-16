Imported CANCELLED tasks for themes toggle to DONE instead of TODO
**Context:** This is about checking the data in the Tasks code that is used when a user clicks on any of the 'Add all Status types supported by....' buttons


I noticed that the default CANCELLED status looks like this:



![Image](https://user-images.githubusercontent.com/4840096/215337371-8e1dcfc1-d367-4397-88ab-7686116be7f0.png)


But the Minimal Theme one does this:



![Image](https://user-images.githubusercontent.com/4840096/215337394-67bee0f8-6138-4661-94c0-210081198795.png)

So one goes to space, and the other to x.

They should be consistent, and there should be tests to detect this.
