Metadata for smallint column is incorrect
Similar to #1255 , 3.x metadata parsing [doesn't consider `smallint`](https://github.com/gocql/gocql/blob/b454769479c6201d26d2a2d7a29ac9a0e6fbc9fc/helpers.go#L76-L125). I'll send a PR today/tomorrow for a fix.

### What version of Cassandra are you using?

3.11.6

### What version of Gocql are you using?

cd4b606dd2fb8920e814a86b2901d062daf388a8
