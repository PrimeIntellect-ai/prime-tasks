No match on `.google.com` cookie domain against www.google.com
Hi,

Is this behaviour expected?

https://github.com/bertrandom/chrome-cookies-secure/pull/66#issuecomment-2689240890

- Cookie domain is `.google.com` (extracted from cookie)
- Domain passed in is `www.google.com`
- A match is not made

This used to work back in `tough-cookie@2.3.4`

https://github.com/salesforce/tough-cookie/blob/e4dfb0aec5d25e9e982805417a5d936071badc17/lib/cookie.js#L301

Quote from issue in `chrome-cookies-secure`

-------
> <img alt="image" width="470" src="https://private-user-images.githubusercontent.com/31162373/417805573-ea8ea035-32cf-4628-a26d-9fff354d56b8.png?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NDA2OTU2NDcsIm5iZiI6MTc0MDY5NTM0NywicGF0aCI6Ii8zMTE2MjM3My80MTc4MDU1NzMtZWE4ZWEwMzUtMzJjZi00NjI4LWEyNmQtOWZmZjM1NGQ1NmI4LnBuZz9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNTAyMjclMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjUwMjI3VDIyMjkwN1omWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPWEyYTk1MDY5NTQzNGE0ODkwMzlmMjc0NzgxZGQ1YWRkYTMxMmM3YTgwZmQ1NzUwZmIyNGMxNTM0ZjBjOTBmMzUmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.0tRgzwtTOQG91fldsBEwHTqVVsnGGy4TARjxUE931JY"> <img alt="image" width="258" src="https://private-user-images.githubusercontent.com/31162373/417805483-ecdcceb7-3444-4b45-8979-e29241729f97.png?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NDA2OTU2NDcsIm5iZiI6MTc0MDY5NTM0NywicGF0aCI6Ii8zMTE2MjM3My80MTc4MDU0ODMtZWNkY2NlYjctMzQ0NC00YjQ1LTg5NzktZTI5MjQxNzI5Zjk3LnBuZz9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNTAyMjclMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjUwMjI3VDIyMjkwN1omWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPTMyM2Q3ZmI1MTkxNDlhZGQzY2QxNDQ5OWMwMTNjOGM1Mzk4MTgxNjc2OGI1MmU0ZWJmMjU5MWY2ODI0MDFhY2ImWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.BxbGcS3p1SeuP0Mw11NQ1phYppIxyASO1GghyftRm4Q">
> ^Fails inside `domainMatch.ts` for https://www.google.com
>
> https://github.com/salesforce/tough-cookie/blob/master/lib/cookie/domainMatch.ts#L95
>
> For https://google.com this always passes
>
> https://github.com/salesforce/tough-cookie/blob/master/lib/cookie/domainMatch.ts#L88
