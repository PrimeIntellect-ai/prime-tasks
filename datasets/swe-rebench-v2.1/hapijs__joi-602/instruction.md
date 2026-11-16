Error: stripUnknown should be one of required, optional, forbidden, ignore
when i use validate like this
```
  Joi.validate({
    nameBase: '123'
  }, Joi.object().keys({
    nameBase: nameBase.required()
  }), {
    presence: "forbidden",
    stripUnknown: false
  }, function(err, r){
    return console.log('arguments', err, r);
  });
```
then Error  occupy
Error: stripUnknown should be one of required, optional, forbidden, ignore
    at Object.exports.assert (/Users/Pamakids-Dev/tudou/tudou2/node_modules/joi/node_modules/hoek/lib/index.js:678:11)
    at Object.internals.checkOptions (/Users/Pamakids-Dev/tudou/tudou2/node_modules/joi/lib/any.js:59:18)
    at internals.Any._validateWithOptions (/Users/Pamakids-Dev/tudou/tudou2/node_modules/joi/lib/any.js:593:19)
    at root.validate (/Users/Pamakids-Dev/tudou/tudou2/node_modules/joi/lib/index.js:102:23)
    at Object.<anonymous> (/Users/Pamakids-Dev/tudou/tudou2/cloud/lib/joi:184:12)
    at Object.<anonymous> (/Users/Pamakids-Dev/tudou/tudou2/cloud/lib/joi:216:4)
    at Module._compile (module.js:456:26)
    at requireFromFile (/usr/local/lib/node_modules/avoscloud-code/lib/cloud_code.js:349:7)
