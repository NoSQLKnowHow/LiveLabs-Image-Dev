from pathlib import Path

from jupyter_server.auth import passwd

vncpwd_file = Path("/home/.vncpwd")
try:
    vncpwd = vncpwd_file.read_text(encoding="utf-8").rstrip("\r\n")
except OSError as exc:
    raise RuntimeError(f"Cannot read JupyterLab password from {vncpwd_file}.") from exc

if not vncpwd:
    raise RuntimeError(f"JupyterLab password in {vncpwd_file} is empty.")

hash = passwd(vncpwd)

# Configuration file for jupyter-notebook.

c = get_config()

# Set the port to 8888
c.ServerApp.port = 8888

# Allow root to run JupyterLab
c.ServerApp.allow_root = True

# Listen on all IP addresses
c.ServerApp.ip = "0.0.0.0"

# Disable authentication token and use the password from /home/.vncpwd
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
