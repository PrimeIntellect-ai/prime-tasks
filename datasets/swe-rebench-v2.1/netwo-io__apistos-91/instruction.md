The end position of the URL path is missing "/"
I define the route in the following way.

`web::scope("/ticket").service(resource("/").route(put().to(update_ticket)))`

apistos: `/ticket`
actix-web: `/ticket/`
