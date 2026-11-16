I want to get the raw binary data from response.body
I need download an excel file using frisby. Frisby can request the resource but can't return the raw binary data. We can only get the decoded data, like utf-8 data. We can encode the data and then decode it to base64 and then write the data to an excel file in the disk. If we do it like this, we yet can't open the excel file as it's not under good shape.
I tried get another local excel file while using readStream.on('data', function(chunk)) method and chunk is the raw binary data and I can decode/encode it to base64 directly and write to an new excel file successfully and open it normally.
I wonder we can get the response stream directly, I failed to get response stream and compose an excel file out, any help? I have to use 'request' method alternative but have a very bad mood on resolving this issue because of time cost. Hope some guys helping me.

### Additional contract requirements

Frisby supports an opt-in raw-response mode, configured with `frisby.setup({ request: { rawBody: true } })`. In this mode, `response.body` exposes the response payload as binary data and preserves its original bytes, including for non-text resources. The binary data may be represented by an ArrayBuffer, Buffer, or Uint8Array. This mode does not require disabling any separately available parsed response representation.
