Trailing whitespaces
First of all, love the project. I'm using scalafmt to format scalacode and all the debates regarding lint and codestyle and nitpicks in PRs disappeared when enabling it. Really looking forward to this taking off!

Now to the issue. It seems that arrow functions are, at least in some cases, leaving a trailing whitespace when reformatted.

I've attached two examples off git diffs where it leaves a trailing comma for me.
![image](https://cloud.githubusercontent.com/assets/4514159/21851188/d50adc5a-d805-11e6-82b8-c6a033ec68a1.png)
![image](https://cloud.githubusercontent.com/assets/4514159/21851197/ddae94b4-d805-11e6-9d32-f1c269df3667.png)

If additional information is needed I'll try my best to get some more context.
