After each code change, the copy operation of the "copy-webpack-plugin" plug-in is executed at the same time as the recompilation operation.
webpack: v4.43.0
webpack-dev-server: v3.11.0
copy-webpack-plugin: v6.0.2
html-webpack-plugin v4.3.0
Windows 10 professional edition 1902 18363.900
node.js: v14.4.0
npm: v6.14.5

Describe the bug:
1、
After each code change, the copy operation of the "copy-webpack-plugin" plug-in is executed at the same time as the recompilation operation.
![image](https://user-images.githubusercontent.com/12012671/84560498-6bd42480-ad77-11ea-99e3-3c619292c512.png)

To Reproduce:
1、The configuration of "copy-webpack-plugin" is:
![image](https://user-images.githubusercontent.com/12012671/84560514-adfd6600-ad77-11ea-91f1-48aaac850431.png)
2、The configuration of "html-webpack-plugin" is:
![image](https://user-images.githubusercontent.com/12012671/84560600-3c71e780-ad78-11ea-9726-5bc75928e36a.png)
3、The configuration of "webpack" is:
![image](https://user-images.githubusercontent.com/12012671/84560630-704d0d00-ad78-11ea-9e39-fb5b5c54d55f.png)

Expected behavior：
1、
After each code change, the recompile operation will not be executed at the same time as the "copy-webpack-plugin" plugin's copy operation.
2、
The "copy-webpack-plugin" plug-in will be re copied only when the copied file changes.


---

This issue was moved from webpack/webpack#11032 by @evilebottnawi. Original issue was by @LP1994.
