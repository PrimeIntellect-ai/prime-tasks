Generic error when using the latest version
I have been using serverless-offline for many months on my current project. My AWS setup has a react frontend with https enabled. Everything still worked today, but then I did a full re-build by deleting node_modules. Suddenly I was getting this error on the command line:
```
sessionID: SIJ0soLd7YGQdew5I3h5BHnzlyOVIccd
Debug: internal, implementation, error
    TypeError: Uncaught error: Cannot read property 'done' of undefined
    at createLambdaContext (/home/max/Documents/code/ark/trinity/nextjs/node_modules/serverless-offline/src/index.js:671:44)
    at process.nextTick (/home/max/Documents/code/ark/trinity/nextjs/node_modules/serverless-http/lib/dispatch.js:7:9)
    at _combinedTickCallback (internal/process/next_tick.js:132:7)
    at process._tickDomainCallback (internal/process/next_tick.js:219:9)
```

Looking at the source code at that line, it seems like maybe the request is empty. The error is a generic error about promises, I think. After some trial and error I found that downgrading the version of serverless-offline fixes the problem.

My old package.json:
```
"serverless-offline": "^4.0.0",
```
Downgrade to 4.10.0 and it will work again:
```
"serverless-offline": "=4.10.0",
```

<details>
  <summary>Full logs from building to the error:</summary>
   <div>

(09:11:57)[max@think nextjs]$ yarn; node-prune; yarn build; yarn devel
yarn install v1.12.3
[1/4] Resolving packages...
[2/4] Fetching packages...
info fsevents@1.2.9: The platform "linux" is incompatible with this module.
info "fsevents@1.2.9" is an optional dependency and failed compatibility check. Excluding it from installation.
[3/4] Linking dependencies...
warning "@material-ui/styles > jss-plugin-vendor-prefixer@10.0.0-alpha.7" has incorrect peer dependency "jss@10.0.0-alpha.3".
warning "@zeit/next-css > css-loader@1.0.0" has unmet peer dependency "webpack@^4.0.0".
warning "@zeit/next-css > mini-css-extract-plugin@0.4.3" has unmet peer dependency "webpack@^4.4.0".
warning "@zeit/next-sass > sass-loader@6.0.6" has unmet peer dependency "webpack@^2.0.0 || >= 3.0.0-rc.0 || ^3.0.0".
warning "next-images > file-loader@3.0.1" has unmet peer dependency "webpack@^4.0.0".
warning "next-images > url-loader@1.1.2" has unmet peer dependency "webpack@^3.0.0 || ^4.0.0".
warning " > react-dropzone@10.1.4" has incorrect peer dependency "react@>= 16.8".
[4/4] Building fresh packages...
success Saved lockfile.
Done in 9.39s.

         files total 40,930
       files removed 12,174
        size removed 63 MB
            duration 326ms

yarn run v1.12.3
$ rm -rf .next && next build
Creating an optimized production build ...

> Using external babel configuration
> Location: "/home/max/Documents/code/ark/trinity/nextjs/.babelrc"
Compiled successfully.

 ┌ /
 ├ /_app
 ├ /_document
 ├ /_error
 ├ /about
 ├ /additem
 ├ /archive
 ├ /cart
 ├ /help
 ├ /history
 ├ /item
 ├ /login
 ├ /manage
 ├ /profile
 └ /shop

Done in 52.04s.
yarn run v1.12.3
$ yarn prod --stage development
$ NODE_ENV=production yarn offline --port=3000 --host=0.0.0.0 --stage development
$ sls offline start --port=3000 --host=0.0.0.0 --stage development
Serverless: Starting Offline: development/us-east-1.

Serverless: Routes for imageWatermark:
Serverless: (none)

Serverless: Routes for getCounts:
Serverless: POST /counts

Serverless: Routes for getCartGuest:
Serverless: POST /get_cart_guest

Serverless: Routes for getCartAuth:
Serverless: POST /get_cart_auth
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for checkUserDb:
Serverless: POST /checkUserDb
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for imageCleanup:
Serverless: (none)

Serverless: Routes for addItem:
Serverless: POST /additem
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for emailOrderStatus:
Serverless: (none)

Serverless: Routes for sendEmail:
Serverless: (none)

Serverless: Routes for deleteItem:
Serverless: DELETE /item
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for saveOrderStatus:
Serverless: POST /save_order_status
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for getUser:
Serverless: POST /get_user
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for pastOrders:
Serverless: POST /past_orders
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for allItems:
Serverless: POST /all_records
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for restore:
Serverless: POST /restore
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for itemQuery:
Serverless: POST /query

Serverless: Routes for itemLoad:
Serverless: POST /item_data
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for itemSave:
Serverless: POST /item
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for cartGuest:
Serverless: POST /cart_guest

Serverless: Routes for cartAuth:
Serverless: POST /cart_auth
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for buyGuest:
Serverless: POST /buy_guest

Serverless: Routes for buyAuth:
Serverless: POST /buy_auth
Serverless: WARNING: Serverless Offline does not support the AWS_IAM authorization type

Serverless: Routes for react:
Serverless: ANY /
Serverless: ANY /{proxy*}

Serverless: Offline listening on http://0.0.0.0:3000

Serverless: ANY / (λ: react)
sessionID: SIJ0soLd7YGQdew5I3h5BHnzlyOVIccd
Debug: internal, implementation, error
    TypeError: Uncaught error: Cannot read property 'done' of undefined
    at createLambdaContext (/home/max/Documents/code/ark/trinity/nextjs/node_modules/serverless-offline/src/index.js:671:44)
    at process.nextTick (/home/max/Documents/code/ark/trinity/nextjs/node_modules/serverless-http/lib/dispatch.js:7:9)
    at _combinedTickCallback (internal/process/next_tick.js:132:7)
    at process._tickDomainCallback (internal/process/next_tick.js:219:9)

</div>
</details>

### Additional contract requirements

- When an HTTP handler returns a Promise that resolves asynchronously, the offline request must complete without the reported uncaught error and deliver the handler’s resolved response.
