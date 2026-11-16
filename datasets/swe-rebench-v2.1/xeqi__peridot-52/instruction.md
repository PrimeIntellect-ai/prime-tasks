Bug: cookies not matched when mixing urls with explicit and implicit ports
**version**

peridot/peridot 0.5.1

**problem**

When mixing urls with explicits and implicits ports (e.g. `http://foo.com` vs `http://foo.com:80`) cookies don't get matched, in a browser (Chrome) this does happen.

**repro**

See test below

**expected behavior**

I'm not 100% sure. In Chrome the cookies are matched correctly. If http without port always means port 80 (I think it does) and https without port always means port 443 (I think it does), this matching should work.

Below is a failing test, that should succeed IMO.

```clojure
(require '[ring.middleware.cookies :as cookies])

(deftest default-ports
  (let [app (cookies/wrap-cookies (fn [request] {:cookies {"counter" {:value 1}}
                                                :status 200 :body (get (:cookies request)
                                                                       "counter"
                                                                       "0")}))]
    (-> (session app)
        (request "http://hello.com")
        (doto
            (#(is (= (get (:headers (:request %)) "cookie")
                     nil)
                  "cookies are not initialized")))

        (request "http://hello.com")
        (doto
            (#(is (= (get (:headers (:request %)) "cookie")
                     "counter=1")
                  "cookies are recognized")))

        (request "http://hello.com:80")
        (doto
            (#(is (= (get (:headers (:request %)) "cookie")
                     "counter=1")
                  "cookies are also recognized when redundant port 80 is added")))

        (request "http://hello.com:80")
        (doto
            (#(is (= (get (:headers (:request %)) "cookie")
                     "counter=1")
                  "cookies are recognized the second time"))))



    (-> (session app)
        (request "https://hello.com")
        (doto
            (#(is (= (get (:headers (:request %)) "cookie")
                     nil)
                  "cookies are not initialized")))

        (request "https://hello.com")
        (doto
            (#(is (= (get (:headers (:request %)) "cookie")
                     "counter=1")
                  "cookies are recognized")))

        (request "https://hello.com:443")
        (doto
            (#(is (= (get (:headers (:request %)) "cookie")
                     "counter=1")
                  "cookies are also recognized when redundant port 443 is added")))

        (request "https://hello.com:443")
        (doto
            (#(is (= (get (:headers (:request %)) "cookie")
                     "counter=1")
                  "cookies are recognized the second time"))))))
```
