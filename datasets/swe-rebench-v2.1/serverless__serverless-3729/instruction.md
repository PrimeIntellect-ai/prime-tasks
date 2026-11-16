Feature request: Throw error if an individual package is empty
Version: 1.14.0

Really like the feature with individual packaging, it saves a lot of space and publishing time.
There is one subtle problem, having wrong `include/exclude` settings with no match leads to `22 bytes` package without any error.

serverless.yml:
```
package:
  individually: true
  exclude:
    - ./**

functions:
  my-lambda:
    name: ${self:service}-${env:stage}-my-lambda
    handler: server/project/dist/handler.lambda
    package:
      include:
        - server/project/dist/handler
```
Here is the wrong path to `server/project/dist/handler`, which does not exist, and the result zip file is wrong and even cannot be unzipped:
<img width="477" alt="screen shot 2017-05-27 at 11 55 29 am" src="https://cloud.githubusercontent.com/assets/6156012/26520084/881863ba-42d4-11e7-813b-daaca78335ae.png">

If the path set to correct `server/project/dist/handler.js` then everything works fine.

-----
It would be nice to have at least a warning, and in my case throwing exception and stopping the whole process as it is very important and hard to notice with a lot of functions.

May be something like a flag:

```
package:
  individually: true
  prohibitEmpty: true
```

If it is important for other guys too may be it will be good to add the exception by default without any flag.

### Additional contract requirements

When a function is packaged individually and its include/exclude patterns select no files, packaging must fail with an error rather than produce an empty package.
