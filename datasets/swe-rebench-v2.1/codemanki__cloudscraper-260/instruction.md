Post request fails after initial cloudflare bypass.
Hi!

I'm using Cloudscraper version `4.14` on Node version `12.10.0`.

I'm attempting to access [this website](https://nakedcph.com), which has a cloudflare protection page with a captcha.

I can bypass the cloudflare and access the site's homepage/any page, however, after bypassing, I am unable to successfully send a post request. The weirdest part about this is that my code works using the Python version of the module recreating the exact same requests.

When sending the post request, the console sometimes prints:

`request received invalid json` when debug is on.

In my second request I need a csrf token that gets returned with the first request's (the bypass request) response. Essentially I am trying to create an account on this website by first retrieving the csrf after the initial bypass (which I can do successfully) and then sending a post request with the account information.

Like I said, I can do this successfully in Python which leads me to believe the issue is related to the module's way of handling post requests, but of course I'm probably wrong. This is my code when sending both requests.

```js
const captchaAPI = require("imagetyperz-api")
const cloudscraper = require("cloudscraper").defaults({ onCaptcha })

cloudscraper.debug = true

let captchaRes
// CALLED IF SCRAPER RUNS INTO CAPTCHA
async function onCaptcha(options, response, body) {
  const captchaData = response.captcha
  captchaRes = await solveCaptcha(
    response.request.uri.href,
    captchaData.siteKey
  )
  captchaData.form["g-recaptcha-response"] = captchaRes
  captchaData.submit()
}

// CALLED WHEN SOLVING A CAPTCHA IS NECESSARY
async function solveCaptcha(uri, sitekey) {
  captchaAPI.set_access_key("KEY")
  const params = {
    page_url: uri,
    sitekey: sitekey
  }
  console.log("Solving captcha...")
  const id = await captchaAPI.submit_recaptcha(params)
  const token = await captchaAPI.retrieve_recaptcha(id)
  return token
}

// GENERATE AN ACCOUNT
async function genAccount(req) {
  const Csrf = req.body.match(/setRequestHeader\('X-AntiCsrfToken', '(.+)'/)[1]
  console.log(`CSRF: ${Csrf}`)
  cloudscraper.defaultParams.headers = {}
  console.log(`CAPTCHA: ${captchaRes}`)
  const headers = {
    authority: "www.nakedcph.com",
    path: "/auth/submit",
    scheme: "https",
    accept: "application/json, text/javascript, */*; q=0.01",
    "accept-encoding": "gzip, deflate, br",
    "accept-language": "en-US,en;q=0.9,pt;q=0.8",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    origin: "https://www.nakedcph.com",
    referer: "https://www.nakedcph.com/auth/view?op=register",
    "sec-fetch-mode": "cors",
    "sec-fetch-site": "same-origin",
    "user-agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/76.0.3809.87 Safari/537.36",
    "X-AntiCsrfToken": Csrf,
    "X-Requested-With": "XMLHttpRequest"
  }
  const gen = await cloudscraper({
    url: "https://nakedcph.com/auth/submit",
    method: "POST",
    resolveWithFullResponse: true,
    // followOriginalHttpMethod: true,
    json: true,
    simple: false,
    headers: headers,
    formData: {
      _AntiCsrfToken: Csrf,
      firstName: "CLOUDSCRAPER TEST",
      email: "cloudscraper+123456@gmail.com",
      password: "MyPassword123",
      "g-recaptcha-response": String(captchaRes),
      action: "register"
    }
  })
  console.log("RESULT:")
  console.log(gen.statusCode)
  console.log(gen.body)
}

const headers = {
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.81 Safari/537.36",
    Accept: "application/json, text/javascript, */*; q=0.01",
    "Accept-Language": "en-US,en;q=0.5",
    "Accept-Encoding": "gzip, deflate, br",
    "X-Requested-With": "XMLHttpRequest"
  }
// FIRST REQUEST GETS SENT HERE
  const req = await cloudscraper({
    url: "https://www.nakedcph.com",
    method: "GET",
    resolveWithFullResponse: true,
    // json: true,
    simple: false,
    headers: headers
  })
  if (req.statusCode === 200) {
// IF FIRST REQUEST IS GOOD AND CLOUDFLARE IS BYPASSED, WE TRY SENDING THE POST
    await genAccount(req)
  }
  console.log(req.statusCode)
```

I get a 200 on the first request, and a 403 on the 2nd. This is what the server returns on the 403:

`{ Response: null, StatusCode: 500, Status: '' }`

Hopefully I'm being really stupid and there is a super simple solution to this. And like I said, my Python version is 100% functional doing the exact same request with the same headers and everything.

Thanks and sorry for any confusions and the long code. I've been looking at this for way longer than I should have and haven't been able to find the solution. Any help is much appreciated.

### Additional contract requirements

When a captcha challenge is detected, the `onCaptcha` handler is invoked with a response whose `captcha` property is an object that exposes everything needed to solve the challenge:

- `captcha.uri` is the full request URI object for the request that triggered the captcha challenge (the same object as `response.request.uri`).
- `captcha.siteKey` is the reCAPTCHA site key extracted from the challenge page, as a string.
- `captcha.form` is an object holding the key/value pairs required to submit the captcha solution.
- `captcha.submit(error?)` is a function that submits the captcha form once a solution has been set. If an `error` argument is supplied, the submission is aborted and that error is reported instead.
- `captcha.url` is a deprecated getter that returns the request URI as a string (`captcha.uri.href`), kept for backward compatibility. Accessing it emits a deprecation warning.

For the reported workflow, after a captcha bypass returns a page containing a CSRF token, a caller can make a subsequent POST with account form fields and that token in the `X-AntiCsrfToken` header. The endpoint receives it as a POST with the submitted fields and CSRF header intact, and the caller can receive the endpoint's successful response.
