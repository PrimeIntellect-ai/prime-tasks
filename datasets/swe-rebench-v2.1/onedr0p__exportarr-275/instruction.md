SABNZBD: Api query adds a URI to the query which gives 404 error
# Details

**What steps did you take and what happened:**

Deployed SABNZBD Exportarr with URL: "http://sabnzbd:8080"

**What did you expect to happen:**

I expected Expertarr to query api at "http://sabnzbd:8080/api?mode=server_stats"

**Anything else you would like to add:**

The Exportarr logs show that it hit {"url": "http://sabnzbd:8080/sabnzbd/api?mode=server_stats"} **Added a URI of sabnzbd

**Additional Information:**

Thus I am receiving this in Exportarr:

2024-02-06T18:18:34.011Z	INFO	Sending HTTP request	{"url": "http://sabnzbd:8080/sabnzbd/api?mode=server_stats"}

2024-02-06T18:18:34.011Z	INFO	Sending HTTP request	{"url": "http://sabnzbd:8080/sabnzbd/api?mode=queue"}

2024-02-06T18:18:34.016Z	ERROR	Failed to get queue stats	{"collector": "sabnzbd", "error": "Failed to get queue stats: Failed to execute HTTP Request(http://sabnzbd:8080/sabnzbd/api?mode=queue): Get \"http://sabnzbd:8080/sabnzbd/api?apikey=daae7ce1995c412ba10abd3b41692a75&mode=queue&output=json\": Received Client Error Status Code: 404"}

2024-02-06T18:18:34.018Z	ERROR	Failed to get server stats	{"collector": "sabnzbd", "error": "Failed to get server stats: Failed to execute HTTP Request(http://sabnzbd:8080/sabnzbd/api?mode=server_stats): Get \"http://sabnzbd:8080/sabnzbd/api?apikey=daae7ce1995c412ba10abd3b41692a75&mode=server_stats&output=json\": Received Client Error Status Code: 404"}

2024-02-06T18:18:34.018Z	ERROR	Failed to get stats	{"collector": "sabnzbd", "error": "failed to get queue stats: Failed to get queue stats: Failed to execute HTTP Request(http://sabnzbd:8080/sabnzbd/api?mode=queue): Get \"http://sabnzbd:8080/sabnzbd/api?apikey=daae7ce1995c412ba10abd3b41692a75&mode=queue&output=json\": Received Client Error Status Code: 404"}
