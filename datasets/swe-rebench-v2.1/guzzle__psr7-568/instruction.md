Content-Type assumption not done if the file don't have extension
**PHP version**: x.y.z (hint: `php --version`)

**Description**
There is an issue within psr7 in the MultipartStream class inside createElement method (https://github.com/guzzle/psr7/blob/815698d9f11c908bc59471d11f642264b533346a/src/MultipartStream.php#L141C1-L141C1).
There is an assumption a content-type is returned no matter what...

**How to reproduce**
Try to upload a multipart file without extension

**Possible Solution**
Add a default content-type for files without extensions l'île proposes in PR  #566

**Additional context**
<!-- Optional: any other context about the problem: log messages, screenshots, etc. -->
