import os
import logging
from airflow.www.security import AirflowSecurityManager
from flask_appbuilder.security.manager import AUTH_OAUTH

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# Log to confirm file is loaded
logger.info("===== webserver_config.py is being loaded =====")

# Enable OAuth authentication
AUTH_TYPE = AUTH_OAUTH
AUTH_USER_REGISTRATION = True
AUTH_ROLES_SYNC_AT_LOGIN = True

# Debug the settings
logger.debug(f"AUTH_USER_REGISTRATION: {AUTH_USER_REGISTRATION}")
logger.debug(f"AUTH_ROLES_SYNC_AT_LOGIN: {AUTH_ROLES_SYNC_AT_LOGIN}")

# Map Keycloak roles to Airflow's default roles
AUTH_ROLES_MAPPING = {
    "Admin": ["Admin"],
    "Op": ["Op"],
    "User": ["User"],
    "Viewer": ["Viewer"],
    "Public": ["Public"],
}

KEYCLOAK_URL = os.getenv("KEYCLOAK_URL")
KEYCLOAK_CLIENT_ID = os.getenv("KEYCLOAK_CLIENT_ID")
KEYCLOAK_CLIENT_SECRET = os.getenv("KEYCLOAK_CLIENT_SECRET")
OAUTH_CALLBACK_URL = os.getenv("AIRFLOW__KEYCLOAK__OAUTH_CALLBACK_URL")
KEYCLOAK_DISPLAY_NAME = os.getenv("KEYCLOAK_DISPLAY_NAME")

# Keycloak OAuth configuration
OAUTH_PROVIDERS = [
    {
        "name": KEYCLOAK_DISPLAY_NAME,
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": KEYCLOAK_CLIENT_ID,
            "client_secret": KEYCLOAK_CLIENT_SECRET,
            "server_metadata_url": f"{KEYCLOAK_URL}/.well-known/openid-configuration",
            "client_kwargs": {
                "scope": "openid profile email roles",
            },
            "access_token_url": f"{KEYCLOAK_URL}/protocol/openid-connect/token",
            "authorize_url": f"{KEYCLOAK_URL}/protocol/openid-connect/auth",
            "userinfo_endpoint": f"{KEYCLOAK_URL}/protocol/openid-connect/userinfo",
            "jwks_uri": f"{KEYCLOAK_URL}/protocol/openid-connect/certs",
            "redirect_uri": OAUTH_CALLBACK_URL,
        },
    }
]

# Custom security manager
class CustomSecurityManager(AirflowSecurityManager):
    def __init__(self, appbuilder):
        super().__init__(appbuilder)
        logger.debug("CustomSecurityManager initialized")

    def oauth_user_info(self, provider, response):
        logger.debug(f"oauth_user_info called with provider: {provider}, response: {response}")
        if provider == KEYCLOAK_DISPLAY_NAME:
            try:
                remote = self.appbuilder.sm.oauth_remotes[provider]
                token = response.get("access_token")
                if not token:
                    raise ValueError("No access_token found in response")

                # Load server metadata
                metadata = remote.load_server_metadata()
                logger.debug(f"Server metadata: {metadata}")

                # Get the userinfo endpoint from metadata
                userinfo_endpoint = metadata.get("userinfo_endpoint")
                if not userinfo_endpoint:
                    raise ValueError("userinfo_endpoint not found in metadata")
                logger.debug(f"Using userinfo_endpoint: {userinfo_endpoint}")

                # Fetch user info with explicit Authorization header
                headers = {"Authorization": f"Bearer {token}"}
                userinfo_response = remote.get(userinfo_endpoint, headers=headers)
                userinfo_response.raise_for_status()
                userinfo = userinfo_response.json()
                logger.debug(f"Full user info from Keycloak: {userinfo}")

                # Log the username being processed
                username = userinfo.get("preferred_username")
                logger.debug(f"Processing user: {username}")

                # Extract roles
                realm_access = userinfo.get("realm_access", {})
                logger.debug(f"Realm access data: {realm_access}")
                roles = realm_access.get("roles", ["Public"])
                if not roles:
                    roles = ["Public"]
                logger.debug(f"Extracted roles from userinfo: {roles}")

                # Map Keycloak roles to Airflow roles
                mapped_roles = []
                for role in roles:
                    airflow_roles = AUTH_ROLES_MAPPING.get(role, ["Public"])
                    mapped_roles.extend(airflow_roles)
                logger.debug(f"Mapped Airflow roles: {mapped_roles}")

                return {
                    "username": username,
                    "email": userinfo.get("email"),
                    "first_name": userinfo.get("given_name", ""),
                    "last_name": userinfo.get("family_name", ""),
                    "role_keys": mapped_roles,
                }
            except Exception as e:
                logger.error(f"Error fetching user info: {e}")
                raise
        return {}

# Set the custom security manager
SECURITY_MANAGER_CLASS = CustomSecurityManager

# Log OAuth providers for debugging
logger.debug(f"OAuth Providers configured: {OAUTH_PROVIDERS}")

