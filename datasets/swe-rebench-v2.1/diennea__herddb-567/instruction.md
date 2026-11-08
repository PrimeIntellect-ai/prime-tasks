Regression Alter table stamentent in herd v0.14.0
**BUG REPORT**

What did you do?

I created table using "CREATE TABLE" statement:

``CREATE TABLE herd.IP (idip INT NOT NULL PRIMARY KEY,address VARCHAR(15) NOT NULL,heloname VARCHAR(255) NOT NULL,idpool INT NOT NULL,status INT NOT NULL, bind NCLOB)
``

After, i tried to execute "ATER TABLE" statement:
``ALTER TABLE herd.IP ADD COLUMN binds NCLOB NULL;
``

But the command does not worked:
![image](https://user-images.githubusercontent.com/43852233/75438056-98466b00-5957-11ea-851d-801059c50605.png)

I tried the same commads in herd version v0.13.0 and i have not found any problem:
![image](https://user-images.githubusercontent.com/43852233/75438318-055a0080-5958-11ea-955d-3a4525216554.png)


To solve my problem i ran the same statement writing IP in lowercase:

`
ALTER TABLE herd.ip ADD COLUMN binds NCLOB NULL
`

I expected having positive result using herd.IP instead of herd.ip
