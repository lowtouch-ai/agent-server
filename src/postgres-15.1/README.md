- This image includes a Python script, **activate_postgres.py** automates the creation of database objects like users, databases, schemas by loading the required parameters from a yaml file.

- A yaml file should be inputted for the **activate_postgres.py** script to work.

- The user passwords are taken from the environment variables, these environment variables refer the vault secret for the values. So the vault container should be set-up first.

```
POSTGRES_USER1PASS=VAULT:PSQL_USER1PASS
```

- A sample yaml file is shown below for reference.

```
   
   ---
    users:
      - name: appzuser1
        password: POSTGRES_USER1PASS
        role: superuser
    
    databases:
      - name: appzdb1
        owner: appzuser1
        tablespace:
          - name: appztspace1
            location: /tmp/appz/tb1
        schemas:
          - name: appzschema1
            authorised_user: appzuser1
            search_path: true
```
