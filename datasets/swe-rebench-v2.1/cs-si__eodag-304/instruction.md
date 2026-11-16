PEPS no longer supports S3
Attempting to use EODAG to download S3 data of any type from PEPs results in no search results returned as PEPS no longer supports S3 data. Confirmed directly by the PEPS help desk on 14.06.2021.

"Comme l’indique l’actualité du 15 février sur notre flux RSS (https://peps-mission.cnes.fr/fr/peps-info-suppression-des-donnees-sentinel-3), PEPS ne diffuse plus de données S3."

Therefore
`dag.available_providers("S3_OLCI_L2LRR")`

Should not return PEPS as a source.
