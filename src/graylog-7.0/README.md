## Image details:
  * Template Name   : graylog
  * GRAYLOG Version : 5.0
  

GRAYLOG_PASSWORD_SECRET – This field is used to encrypt Graylog passwords - pwgen -N 1 -s 96
GRAYLOG_ROOT_PASSWORD_SHA2 – This is a SHA2 hash of the password for the admin user (the hash is for the password “admin”). You can generate your own password hash with the following command:

echo -n "Enter Password: " && head -1 </dev/stdin | tr -d '\n' | sha256sum | cut -d" " -f1


