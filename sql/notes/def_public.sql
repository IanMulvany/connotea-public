mysql> update user_bookmark set def_public = 1 where private = 0 and private_gang is null and (private_until is null or private_until < NOW()) and quarantined is null;
Query OK, 0 rows affected (11.93 sec)
Rows matched: 343831  Changed: 0  Warnings: 0

mysql> update user_bookmark set def_public = 0 where not (private = 0 and private_gang is null and (private_until is null or private_until < NOW()) and quarantined is null);



