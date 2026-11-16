Support Custom Axios Instance on Client Class
this makes a custom axios instance with retries as in #326 a bit easier at the class level

### Additional contract requirements

A `Client` may be configured with a caller-supplied Axios instance using the `axiosInstance` option. Requests made through that client must use the supplied instance, preserving instance-specific request behavior and configuration (for example, a custom adapter or retry handling).
