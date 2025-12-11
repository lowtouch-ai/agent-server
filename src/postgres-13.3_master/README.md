- This image includes a Python script, **activate_postgres.py** automates the creation of database objects like users, databases, schemas by loading the required parameters from a yaml file.

- A yaml file should be inputted for the **activate_postgres.py** script to work. This yaml file 'setup.yaml' needs to be uploaded to the triggering repo and appz will take care of the further steps.

- The user passwords are taken from the environment variables, these environment variables refer the vault secret for the values. So the vault container should be set-up first.


```
POSTGRESQL_USER1PASS=VAULT:PSQL_USER1PASS
POSTGRESQL_USER2PASS=VAULT:PSQL_USER2PASS
POSTGRESQL_USER3PASS=VAULT:PSQL_USER3PASS
```

- A sample setup.yaml file is shown below for reference.

```

   ---
    users:
      - name: appzuser1
        password: POSTGRESQL_USER1PASS
        role: superuser
      - name: appzuser1
        password: POSTGRESQL_USER2PASS
        role: createdb, createrole
      - name: appzuser3
        password: POSTGRESQL_USER2PASS
        role: createrole

    databases:
      - name: appzdb1
        owner: appzuser1
        tablespace:
          - name: appztspace1
            location: /appz/data/tb1
        schemas:
          - name: appzschema1
            authorised_user: appzuser1
            search_path: true
          - name: appzschema2
            authorised_user: appzuser1
            search_path: false
```
- To create DB dump -

  ```
  pg_dump --clean --if-exists -U (rootuser) (DB name) > location 
  eg:- pg_dump --clean --if-exists -U postgres openproject > /tmp/test.sql
  ```
  
- To restore DB - 

  ```
  psql -U (root user) (DB) < dump.sql | tee log.txt 
  eg:- psql -U postgres openproject < /tmp/test.sql | tee file.txt
  ```
