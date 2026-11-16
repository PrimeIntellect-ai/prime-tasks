Vary with dynamic config
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the regression has not already been reported


### Last working version

8.x.x

### Stopped working in version

9.x.x

### Node.js version

any

### Operating system

Linux

### Operating system version (i.e. 20.04, 11.3, 10)

any

### 💥 Regression Report

this testcase has two different origins (example.com and sample.com):
https://github.com/fastify/fastify-cors/blob/3cf8f61d9358adb743d0a14bf575ffe3193ef4ea/test/cors.test.js#L126-L221

But does not add the Vary: origin header.

### Steps to Reproduce

add expectation that the vary header exists back to that test (and the other tests with config delegation changed in #288)

### Expected Behavior

_No response_
