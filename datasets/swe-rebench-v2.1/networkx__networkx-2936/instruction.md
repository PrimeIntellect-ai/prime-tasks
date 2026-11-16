Write pajek error
When rewriting a network who has been read from pajek there is an error:
'float' object has no attribute 'strip'
apparently coordinates (x,y) don't get translated back to string
(Networkx 2.1)
