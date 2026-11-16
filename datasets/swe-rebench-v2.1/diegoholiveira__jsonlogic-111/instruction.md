Cannot specify a default value for a variable when accessing it on an array
When accessing a variable on an array, you cannot specify a default value for the variable. Is there a problem here?
rule: `{ "map":[{"var": "arr"},{"var":["xxx", "default"]}]}`
data: `{"arr": [{"xxx": "111","yyy": "222"},{"xxx": "333","yyy": "444"}]}`
result data: `[default default]`
