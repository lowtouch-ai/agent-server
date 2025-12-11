
Vault is a tool for securely accessing secrets. A secret is anything that you want to tightly control access to, such as API keys, passwords, certificates, and more. 
## Set ENV for auto generate passwords in vault

For enabling the auto password generation, change the ENABLE_AUTO_PASSWORD value as True in env.conf it will be False as default.
```
ENV='-e ENABLE_AUTO_PASSWORD=True'
```
## How to set secrets in vault?
Users are required to create an approle first and note down the **VAULT_ROLE_ID** and **VAULT_SECRET_ID** . You need to export these two values before restarting the linked container with vault.
```
bash /appz/scripts/get_approle.sh <appname>
```
Sample:
```
bash /appz/scripts/get_approle.sh wordpress
```
These are the envs in wordpress-5.4 image, needed to setup in vault.
```
ENV+=' -e MYSQL_PASSWORD='VAULT:MYSQL_PASSWORD_KEY
ENV+=' -e ADMIN_PASSWORD='VAULT:ADMIN_PASSWORD_KEY
ENV+=' -e SITE_PRIVATE_KEY='VAULT:SITE_PRIVATE_KEY
ENV+=' -e SITE_CERT='VAULT:SITE_CERT
```
- If it is a password secret, do 
```
bash /appz/scripts/set_secret.sh <appname>
```
Sample:
Take the env  **ADMIN_PASSWORD=VAULT:ADMIN_PASSWORD_KEY**
```
bash /appz/scripts/set_secret.sh wordpress
Enter Key: ADMIN_PASSWORD_KEY
Enter value: ***********
```
-  If it is a certificate/key secret, do 
Copy the certificate/key file in any location inside vault container and run
```
bash /appz/scripts/set_pk.sh <appname> <key> pkk=<path-to-pf-file>"
```
Sample:
Take the environment variables 
**SITE_PRIVATE_KEY=VAULT:SITE_PRIVATE_KEY**
**SITE_CERT=VAULT:SITE_CERT**
```
bash /appz/scripts/set_pk.sh wordpress  SITE_PRIVATE_KEY pkk=/appz/cache/key.pem
bash /appz/scripts/set_pk.sh wordpress SITE_CERT pkk=/appz/cache/cert.pem
```
Users can list all the secrets in an approle by
```
bash /appz/scripts/list_secret.sh <appname>
```
Sample:
```
bash /appz/scripts/list_secret.sh wordpress
```

