#!/usr/bin/env bash

# Exit on any error
set -e

# === 1. Vault Integration (Copied from dump_rfp.sh) ===
if env | grep "VAULT:" > /dev/null 2>&1
then
   c=1
   mc_wait=180
   while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health | grep "200" > /dev/null 2>&1; do
   echo "waiting for $VAULT_ADDR..."
   sleep 1
   c=`expr $c + 1`
   if [ $c -gt $mc_wait ]; then
      echo "FATAL: vault timeout... exiting"
      exit 1
   fi; done
   VAULT_GET_ADDR=$(echo $VAULT_ADDR | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi

# === 2. Configuration ===
MINIO_URL="http://${MINIO_HOST}"

# Root credentials (to perform admin tasks)
ROOT_USER=${MINIO_ROOT_USER}
ROOT_PASS=${MINIO_ROOT_PASSWORD}

# New Project Specific Credentials (from Vault)
PROJECT_USER=${CF_MINIO_USER}
PROJECT_PASS=${CF_MINIO_PASSWORD}
BUCKET_NAME="clipfoundry"

# Check for MinIO Client (mc)
if ! command -v mc &> /dev/null; then
    echo "MinIO Client (mc) not found. Downloading..."
    
    # Detect architecture (defaults to amd64, switches to arm64 if detected)
    ARCH="amd64"
    if [ "$(uname -m)" = "aarch64" ]; then
        ARCH="arm64"
    fi
    echo "Detected architecture: $ARCH"

    curl https://dl.min.io/client/mc/release/linux-${ARCH}/mc \
      --create-dirs \
      -o /usr/local/bin/mc
    chmod +x /usr/local/bin/mc
fi

echo "Configuring MinIO for project: $BUCKET_NAME"

# === 3. Execution ===

# 3a. Alias the MinIO server as 'local-admin' using Root creds
echo "Connecting to MinIO as Root..."
mc alias set local-admin "$MINIO_URL" "$ROOT_USER" "$ROOT_PASS"

# 3b. Create the User
if mc admin user info local-admin "$PROJECT_USER" >/dev/null 2>&1; then
    echo "User $PROJECT_USER exists. Updating password..."
else
    echo "Creating user $PROJECT_USER..."
fi
mc admin user add local-admin "$PROJECT_USER" "$PROJECT_PASS"

# 3c. Create the Bucket (The "Root Folder")
if mc ls local-admin/"$BUCKET_NAME" >/dev/null 2>&1; then
    echo "Bucket '$BUCKET_NAME' already exists."
else
    echo "Creating bucket '$BUCKET_NAME'..."
    mc mb local-admin/"$BUCKET_NAME"
fi

# 3d. Define Policy (Read/Write Access ONLY to /rfp)
# This policy allows s3 operations on the specific bucket, 
# plus basic console capabilities so they can login via UI.
echo "Creating policy '${BUCKET_NAME}-access'..."
cat > /tmp/rfp-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF

# Use 'set' (create/update) instead of 'create' to handle re-runs gracefully
# If 'admin policy set' command is not available in your version of mc, it will fall back to create.
if mc admin policy add local-admin "${BUCKET_NAME}-access" /tmp/rfp-policy.json >/dev/null 2>&1; then
   echo "Policy created/updated using 'add'."
elif mc admin policy set local-admin "${BUCKET_NAME}-access" /tmp/rfp-policy.json >/dev/null 2>&1; then
   echo "Policy created/updated using 'set'."
else
   # Fallback for very old versions
   mc admin policy create local-admin "${BUCKET_NAME}-access" /tmp/rfp-policy.json
fi

# 3e. Attach Policy to User
echo "Attaching policy to user $PROJECT_USER..."
mc admin policy attach local-admin "${BUCKET_NAME}-access" --user "$PROJECT_USER"

echo "MinIO setup complete."
echo "User: $PROJECT_USER"
echo "Bucket: $BUCKET_NAME"
echo "Access: Read/Write restricted to '$BUCKET_NAME' bucket."