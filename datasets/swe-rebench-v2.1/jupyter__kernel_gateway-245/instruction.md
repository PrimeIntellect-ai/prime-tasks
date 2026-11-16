allow_headers option overwritten
    python -m kernel_gateway --KernelGatewayApp.allow_origin='*' --KernelGatewayApp.allow_headers='X-XSRFToken'

Should return headers
    Access-Control-Allow-Headers: X-XSRFToken

But instead for some API calls it returns:
    Access-Control-Allow-Headers: 'accept, content-type, authorization'

It seems that this is overwritten in line 452 of notebook/base/handlers.py
