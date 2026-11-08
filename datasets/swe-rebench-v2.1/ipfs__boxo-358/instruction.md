Trustless Gateway mode rejects CAR requests allowed under IPIP-402
While browsing gateway code I was bringing into boost, I noticed this function, that gets called when DeserializedResponses is false:

https://github.com/ipfs/boxo/blob/main/gateway/handler.go#L334

This appears to reject all requests for trustless gateway that contain paths. As I understand it, if the response format is CAR, then these requests should not get rejected under IPIP-402.
