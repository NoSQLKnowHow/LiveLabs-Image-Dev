import os
from jupyter_server.auth import passwd
from dotenv import load_dotenv

load_dotenv(dotenv_path="/home/.vncpwd.env")


# vncpwd = "${vncpwd}"

vncpwd = os.getenv("vncpwd")
if not vncpwd:
    raise RuntimeError("Missing vncpwd in /home/.vncpwd.env; refusing to start Jupyter without password auth.")

hash = passwd(vncpwd)

# Configuration file for jupyter-notebook.

c = get_config()

# Set the port to 8888
c.ServerApp.port = 8888

# Allow root to run JupyterLab
c.ServerApp.allow_root = True

# Listen on all IP addresses
c.ServerApp.ip = "0.0.0.0"

# Disable authentication token and use a password
c.ServerApp.open_browser = False

# Optional: Set a specific working directory
c.ServerApp.notebook_dir = "/home"

# Setting hashed_password for IdentityProvider
c.IdentityProvider.hashed_password = hash
c.IdentityProvider.token = ""
c.IdentityProvider.password_required = True
# Persist cookie signing secret on the mounted /home volume so login cookies remain valid across restarts.
c.ServerApp.cookie_secret_file = "/home/.jupyter_cookie_secret"
# Some browser/proxy paths can intermittently drop XSRF headers on text-file saves.
# Keep password auth enabled and relax only the XSRF check for smoother workshop UX.
c.ServerApp.disable_check_xsrf = True
# Use a stable cookie name independent of host/IP variants.
c.IdentityProvider.cookie_name = "jupyterlab_session"
# Make auth cookies explicit for direct IP-based HTTP access to reduce intermittent session loss.
c.IdentityProvider.cookie_options = {"SameSite": "Lax"}
c.IdentityProvider.secure_cookie = False

# Load Oracle Redwood custom theme CSS
c.ServerApp.extra_static_paths = ["/etc/jupyter/custom"]
c.LabApp.extra_static_paths = ["/etc/jupyter/custom"]
