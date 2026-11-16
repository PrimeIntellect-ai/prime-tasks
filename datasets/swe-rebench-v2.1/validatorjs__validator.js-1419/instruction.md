isBase64("") returns false
The string "" is valid base64 (see first example https://tools.ietf.org/html/rfc4648#section-10) but `isBase64("")` returns `false`. This is also errorneous in the tests (see https://github.com/validatorjs/validator.js/blob/master/test/validators.js line 4755).

_Originally posted by @AberDerBart in https://github.com/validatorjs/validator.js/issues/1239#issuecomment-672764860_
