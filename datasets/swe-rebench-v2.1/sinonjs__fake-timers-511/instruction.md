ClockTime constructor name is different, breaking mongoose Date checks
<!--
Are you wondering how to do something with FakeTimers, or something else that is purely
usage related? Please post it to StackOverflow using the `sinon` and `lolex` labels.
This makes it possible for the bigger community to help answer your questions.

The issue tracker is solely meant for posting bugs, feature requests and non-usage related issues.
-->

> We understand you have a problem and are in a hurry, but please provide us with some info to make it much more likely for your issue to be understood, worked on and resolved quickly.

-   FakeTimers version : 13.0.2
-   Environment : node 20.18 (macOS)
-   Other libraries you are using: sinon 19.0.2, mongoose 8.7.1

**What did you expect to happen?**
We're using Sinon together with mongoose. When using mongoose's `toJSON` and `toObject` to turn mongoose documents into plain objects while faking timers I'd expect fields with Date objects to remain Date objects (or at least look like them). This is the case in fake-timers 11.2.2.

**What actually happens**
While faking timers, when calling `toJSON` or `toObject` on a mongoose document, it turns any Date fields into a number (unix timestamp). This seems to happen because [mongoose determines whether an object is a Date or not using the constructor name](https://github.com/Automattic/mongoose/blob/0752c5daea10df87183a27ed7a1e2c3be33ef52a/lib/helpers/clone.js#L77-L89).

**How to reproduce**
```js
import mongoose from 'mongoose';
import sinon from 'sinon';

const DocModel = mongoose.model('doc',  new mongoose.Schema({ someDate: { type: Date } }));

const doc = new DocModel({ someDate: new Date() })

const plainDocBefore = doc.toObject()
console.log(plainDocBefore.someDate) // plainDocBefore.someDate is a Date object

sinon.useFakeTimers({ now: new Date(), toFake: ['Date', 'hrtime'] });

const plainDocAfter = doc.toObject()
console.log(plainDocAfter.someDate) // plainDocAfter.someDate is a unix timestamp (number)
```

Hope this is the right place to report this.
