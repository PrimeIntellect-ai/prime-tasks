Invalid nft tokenURI breaks UI
Our UI expects a json encoded tokenURI.  But if someone is not having that, our market fails.

Example:  https://market.oceanprotocol.com/asset/did:op:4e95bb06d1342e027fcf3dea2a3030034b66fff4fa77c64369aeb99621e6b2f3

![image](https://user-images.githubusercontent.com/7489447/200671718-42df70ec-8377-4cd4-8d3f-8a7734630da6.png)

Traceback:
- decoding their nft contract (https://mumbai.polygonscan.com/address/0x6010F7fb5180b89A172b4146dAd12a998222957D#readContract) we got:
```
[ tokenURI method Response ]
    string :  https://www.dataunion.app/wp-content/uploads/elementor/thumbs/logo2-pq2gnen6pz25kw859sdyuyyh23xml7r7wpzn9jqtq8.png
```


vs a market published nft (https://mumbai.polygonscan.com/address/0x2D2951DEFf34F869d7710e4fbAF7dc066B21F74C#readContract)
```
[ tokenURI method Response ]
    string :  data:application/json;base64,eyJuYW1lIjoiT2NlYW4gRGF0YSBORlQiLCJzeW1ib2wiOiJPQ0VBTi1ORlQiLCJkZXNjcmlwdGlvbiI6IlRoaXMgTkZUIHJlcHJlc2VudHMgYW4gYXNzZXQgaW4gdGhlIE9jZWFuIFByb3RvY29sIHY0IGVjb3N5c3RlbS5cblxuVmlldyBvbiBPY2VhbiBNYXJrZXQ6IGh0dHBzOi8vbWFya2V0Lm9jZWFucHJvdG9jb2wuY29tL2Fzc2V0L2RpZDpvcDozNjMyZTg1ODQ4MzdmMmVhYzA0ZDg1NDY2YzBjZWJkOGI4Y2IyNjczYjQ3MmE4MmEzMTAxNzVkYTk3MzAwNDJhIiwiZXh0ZXJuYWxfdXJsIjoiaHR0cHM6Ly9tYXJrZXQub2NlYW5wcm90b2NvbC5jb20vYXNzZXQvZGlkOm9wOjM2MzJlODU4NDgzN2YyZWFjMDRkODU0NjZjMGNlYmQ4YjhjYjI2NzNiNDcyYTgyYTMxMDE3NWRhOTczMDA0MmEiLCJiYWNrZ3JvdW5kX2NvbG9yIjoiMTQxNDE0IiwiaW1hZ2VfZGF0YSI6ImRhdGE6aW1hZ2Uvc3ZnK3htbCwlM0Nzdmcgdmlld0JveD0nMCAwIDk5IDk5JyBmaWxsPSd1bmRlZmluZWQnIHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyclM0UlM0NwYXRoIGZpbGw9JyUyM2ZmNDA5Mjc3JyBkPSdNMCw5OUwwLDIwQzgsMTkgMTYsMTkgMjUsMTlDMzMsMTggNDAsMTcgNDksMTlDNTcsMjAgNjUsMjQgNzQsMjZDODIsMjcgOTAsMjcgOTksMjdMOTksOTlaJy8lM0UlM0NwYXRoIGZpbGw9JyUyM2ZmNDA5MmJiJyBkPSdNMCw5OUwwLDUwQzcsNTIgMTUsNTQgMjQsNTRDMzIsNTMgNDEsNTEgNTAsNTBDNTgsNDggNjUsNDggNzQsNDlDODIsNDkgOTAsNTIgOTksNTVMOTksOTlaJyUzRSUzQy9wYXRoJTNFJTNDcGF0aCBmaWxsPSclMjNmZjQwOTJmZicgZD0nTTAsOTlMMCw3NkM4LDc4IDE2LDgxIDI1LDgwQzMzLDc4IDQxLDczIDQ5LDcxQzU2LDY4IDY0LDY4IDczLDcwQzgxLDcxIDkwLDc0IDk5LDc3TDk5LDk5WiclM0UlM0MvcGF0aCUzRSUzQy9zdmclM0UifQ==
 ```

 which decodes to :
 ```
 {"name":"Ocean Data NFT","symbol":"OCEAN-NFT","description":"This NFT represents an asset in the Ocean Protocol v4 ecosystem.\n\nView on Ocean Market: https://market.oceanprotocol.com/asset/did:op:3632e8584837f2eac04d85466c0cebd8b8cb2673b472a82a310175da9730042a","external_url":"https://market.oceanprotocol.com/asset/did:op:3632e8584837f2eac04d85466c0cebd8b8cb2673b472a82a310175da9730042a","background_color":"141414","image_data":"data:image/svg+xml,%3Csvg viewBox='0 0 99 99' fill='undefined' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath fill='%23ff409277' d='M0,99L0,20C8,19 16,19 25,19C33,18 40,17 49,19C57,20 65,24 74,26C82,27 90,27 99,27L99,99Z'/%3E%3Cpath fill='%23ff4092bb' d='M0,99L0,50C7,52 15,54 24,54C32,53 41,51 50,50C58,48 65,48 74,49C82,49 90,52 99,55L99,99Z'%3E%3C/path%3E%3Cpath fill='%23ff4092ff' d='M0,99L0,76C8,78 16,81 25,80C33,78 41,73 49,71C56,68 64,68 73,70C81,71 90,74 99,77L99,99Z'%3E%3C/path%3E%3C/svg%3E"}
 ```

 So, we should always asses if tokenURI is a json encoded string or not

### Additional contract requirements

- The public function `decodeTokenURI(tokenURI: string)` in module `src/@utils/nft.ts` returns the NFT metadata for the given tokenURI. When the tokenURI is a JSON-encoded data URI it returns the decoded metadata object; when the tokenURI is not JSON-encoded it returns metadata that exposes the tokenURI as the NFT image.
- When an NFT has a non-JSON tokenURI, the market asset view must remain usable and display that tokenURI as its image.
