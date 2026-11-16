% escaping makes loading URLs through fetch not work
http://X/fortio/fetch/Y/fortio1/fortio/?labels=Fortio&url=localhost%3A8080/echo&qps=100&t=3s&n=&c=8&p=50%2C+75%2C+90%2C+99%2C+99.9&r=0.0001&H=User-Agent%3A+istio%2Ffortio-0.8.0-pre&H=&H=&runner=http&save=on&load=Start

->

Fortio localhost%3A8080/echo

Aborting because unable to create client 0 for http://localhost%253A8080/echo


going to debug shows the issue:

GET /debug?labels=Fortio&url=localhost%253A8080/echo&qps=100&t=3s&n=&c=8&p=50%252C+75%252C+90%252C+99%252C+99.9&r=0.0001&H=User-Agent%253A+istio%252Ffortio-0.8.0-pre&H=&H=&runner=http&save=on&load=Start HTTP/1.1

%253A instead of %3A
