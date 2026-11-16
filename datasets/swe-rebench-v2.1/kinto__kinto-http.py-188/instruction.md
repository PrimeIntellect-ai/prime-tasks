json encoding of querystring parameters fails
For instance:

/v1/buckets/bid/collections/cid/records?in_id=["be503c41-3aa6-42e1-9214-0d00ee0ce9ac","51f65e45-b17c-4dc1-970f-1da8f219824f","b4bb1714-cfe3-4cde-9903-66c47b4ce2f2"]&_sort=-published_date&max_published_date="2018-11-12T15:52:00"&language=fr&_limit=100

Doesn't work while:

/v1/buckets/bid/collections/cid/records?in_id=be503c41-3aa6-42e1-9214-0d00ee0ce9ac,51f65e45-b17c-4dc1-970f-1da8f219824f,b4bb1714-cfe3-4cde-9903-66c47b4ce2f2&_sort=-published_date&max_published_date=%222018-11-12T15:52:00%22&language=fr&_limit=100

Does.
