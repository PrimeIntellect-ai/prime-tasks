"promises" plug-in not functioning when using vcapServices option to initialize Cloudant
Please [read these guidelines](http://ibm.biz/cdt-issue-guide) before opening an issue.

<!-- Issues will be CLOSED IMMEDIATELY if the following template is not completed. -->

## Bug Description
When initializing Cloudant using the vcapServices option, the "promises" plug-in does not seem to function.  When initializing cloudant using url:<Username:Password.bluemix.cloudant.com>, the plugin DOES work.  In both cases, the Cloudant database successfully connects.
### 1. Steps to reproduce and the simplest code sample possible to demonstrate the issue
The following code DOES work:
```javascript
let cloud_DB = new Cloudant({url:cloudand_url, plugins: 'promises' }, (err, cloudant, reply) => {
appEnv.services }, (err, cloudant, reply) => {
  if (err) {
    throw (err)
    console.log("Error creating cloudant " + err);
  }
    console.log("made DB");
});

cloud_DB.db.use('database_name').info().then((body) => {
  console.log(`got info <from a promise>: ${body}`);
})
```
the following code DOES NOT work:
```javascript
let cloud_DB = new Cloudant({vcapInstanceName:'Cloudant-d2', vcapServices: appEnv.services, plugins: 'promises' }, (err, cloudant, reply) => {
  if (err) {
    throw (err)
    console.log("Error creating cloudant " + err);
  }
    console.log("made DB");
});

cloud_DB.db.use('database_name').info().then((body) => {
  console.log(`got info <from a promise>: ${body}`);
})
```
It is fair to point out that I am passing **appEvn.services** to vcapServices.  This appEvn uses cfenv to get the vcap services or a local copy, if the code is local.
### 2. What you expected to happen
In both cases, I would expect to see in the console:
```
made DB
got info <from a promise>: [object object]
```
### 3. What actually happened
In the first example, I see what I expect.

In the second example, I see ``made DB`` but then receive a
```TypeError: cloud_DB.db.use(...).info(...).then is not a function ```

**note** that if I make the same call without using promises, it works in both cases.  Example:
```Javascript
cloud_DB.db.use('database_name').info((err, body) => {
    if(err) console.log("DB info Error " + err);
    if(body){
      console.log("DB info " + body);
    }
});
```
## Environment details

- @cloudant/cloudant version
    > 2.4.0
- Node.js version
    > 9.8.0
