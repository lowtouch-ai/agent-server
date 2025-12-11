# Deploying Vault, Mariadb and Wordpress in Docker

## 1. Clone AppZ-Image Repository  

* 1a. Clone the repo by entering the command

  ```
  $ mkdir wordpress && cd wordpress  
  $ git clone https://github.com/Cloudbourne/AppZ-Images.git
  ```

  Note: You will be prompted to enter your git username and git password( here its git token)

## 2. Build base image ubuntu-18.04 and vault-1.2 
* 2a. Building Ubuntu-18.04 image

``` 
$ cd AppZ-Images/ubuntu-18.04 
$ ../build.sh
```
Wait for it to build the image.

* 2b. Building Vault-1.2 and running the image

```
$ cd ../vault-1.2
$ ../build.sh
$ ../restart.sh
```
* 2c. Adding Vault_Approle , vault_secret_id and vault_role_id

```
$ ../bash.sh
# cd /appz/scripts/
# bash get_approle.sh wordpress
```

output will be:

```
No value found at auth/approle/role/wordpress/role-id
2023-01-10 09:04:41,332 INFO wordpress approle does not exist. creating it...
2023-01-10 09:04:41,332 INFO writing policy to /appz/cache/app_policy.hcl
path "auth/approle/login" {
 capabilities = [ "create", "read" ]
}


path "secret/wordpress/*" {
 capabilities = [ "read", "list" ]
}
Success! Uploaded policy: wordpress_policy
2023-01-10 09:04:41,332 INFO creating/update approle wordpress with policy /appz/cache/app_policy.hcl
Success! Data written to: auth/approle/role/wordpress
2023-01-10 09:04:41,332 INFO creation/update approle wordpress success ...
2023-01-10 09:04:41,332 INFO cleaning up policy file /appz/cache/app_policy.hcl
-----------------------------------------------
VAULT_ROLE_ID=********-****-****-****-********
VAULT_SECRET_ID=********-****-****-****-********
-----------------------------------------------
Success! Revoked token (if it existed)
```

* 2d. Copy the Vault_role_id and vault_secret_id and export these ENVs from outside the docker container

```
# exit
$ export VAULT_APPROLE=wordpress
$ export VAULT_ROLE_ID=********-****-****-****-********
$ export VAULT_SECRET_ID=********-****-****-****-********
```

## Build Mariadb-10.4 and Wordpress-6.1

* 3a. Build mariadb

```
$ cd ../mariadb-10.4
$ ../build.sh
$ ../restart.sh
```
* 3b. Export wordpress ENVs

```
$ cd ../wordpress-6.1
$ export SITE_URL="https://serverpublicip"     
$ export APPZ_FILESYNC_HOSTNAME=wordpress-0

```
Note: Replace serverpublicip with your server IP
ie https://192.02.50.122

* 3c. Build and run wordpress

```
$ ../build.sh
$ ../restart.sh
```

Note: for default password, generate a hash password using [Hash Password Generator](https://www.useotools.com/wordpress-password-hash-generator) 
copy the hash password into env.conf

* 3d. Edit the value of $ADMIN_PASSWORD_HASH with the generated hash password inside env.conf
```
$ vim env.conf               
ENV+=' -e ADMIN_PASSWORD_HASH=$P$Bn4vkdNFggWCufl8iJiVbwceNuB1xf0'
```
Note: if vim is not installed, install vim by ```apt-get install vim```

* 3e. Verify all three containers are running

```
$ docker ps -a
CONTAINER ID   IMAGE                 COMMAND                  CREATED          STATUS                    PORTS                                                                                                                     NAMES
99ed231f1be0   appz/vault:1.2        "/usr/bin/supervisor…"   44 minutes ago   Up 44 minutes (healthy)   80/tcp, 192.168.50.196:8200->8200/tcp                                                                                     vault
e637de1aca92   appz/mariadb:10.4        "/usr/bin/supervisor…"   4 hours ago      Up 4 hours (healthy)    3306/tcp, 33060/tcp, 0.0.0.0:9104->9104/tcp, :::9104->9104/tcp                                                            mariadb
ff224301eeba   appz/wordpress:6.1    "supervisord -c /etc…"   4 hours ago    Up 4 hours (healthly)    192.168.50.196:443->443/tcp, 80/tcp, 192.168.50.196:12000->12000/tcp                                                      wordpress
```

## Login the wordpress webpage

Try accessing the URL -https://serverip:443
default username: cloudbourne 
default password: (hash-generated password)



