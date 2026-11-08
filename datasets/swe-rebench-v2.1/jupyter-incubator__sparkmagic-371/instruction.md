Add ability to specify headers to Livy
I got the following error when try to connect to livy server on HDP 2.5:

HttpClientException: Invalid status code '400' from http://host:8998/sessions with error payload: <html>
<head>
<meta http-equiv="Content-Type" content="text/html;charset=ISO-8859-1"/>
<title>Error 400 </title>
</head>
<body>

<h2>HTTP ERROR: 400</h2>

<p>Problem accessing /sessions. Reason:
<pre>    Missing Required Header for CSRF protection.</pre></p>

<hr /><i><small>Powered by Jetty://</small></i>
</body>
</html>

### Additional contract requirements

- Configuration must expose `custom_headers()` in `sparkmagic.utils.configuration`, returning the configured custom header mapping (empty by default). It must be overridable through `configuration.override_all` using the key `custom_headers`.
- `LivyReliableHttpClient.get_headers(self)` must return the combined default and custom headers used by the Livy HTTP client, including `"Content-Type": "application/json"` and any configured custom headers.
- `ReliableHttpClient.get_headers(self)` must return the header dictionary that was supplied when the client was created.
- The configured headers must be the HTTP header mapping the Livy client sends with each request.
