using '*' with jsonTypes is causing false positives on empty arrays
In my GET method tests I often use Joi and jsonTypes to iterate through arrays and to enforce certain properties types from responses exist. We recently did a cleardown in our database and ran the tests expecting all tests to fail. Instead we got some false positives on multiple endpoints that were returning an empty array. I wasn't sure whether to write this issue to you guys, Joi, or Jasmine but figured i'd start here.

Here's a snippet from my code minus the endpoint just incase i'm doing something wrong.

P.S When i change '*' to an index like '0' the test does fail.

```javascript
const frisby = require('frisby')
const Joi = frisby.Joi

describe('Joi inside jsonTypes', function() {
  it('should fail this test', function(done) {
    frisby
      .get('insert url that returns empty array here')
      .expect('status', 200)
      .expect('jsonTypes', '*', {
        id: Joi.number().required(),
       description: Joi.string().required()
      })
      .done(done)
  }, 5000)
})
```
![frisby](https://user-images.githubusercontent.com/18755684/35932409-2db68ed6-0bfd-11e8-867d-8368ccbe773c.png)

and as you can see it passes!
