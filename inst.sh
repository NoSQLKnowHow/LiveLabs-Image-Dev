#!/bin/bash

#######    S T A R T      S C R I P T    ######
#######   (This is for Oracle Linux 9)   ######

## update
sudo dnf update -y

## set firewall rules
sudo firewall-cmd --permanent --add-port=1521/tcp #Database
sudo firewall-cmd --permanent --add-port=1522/tcp #Database
sudo firewall-cmd --permanent --add-port=8888/tcp #JupyterLabs
sudo firewall-cmd --permanent --add-port=8181/tcp #ORDS
sudo firewall-cmd --permanent --add-port=8501/tcp #Streamlit
sudo firewall-cmd --permanent --add-port=8502/tcp #Streamlit
sudo firewall-cmd --permanent --add-port=8503/tcp #Streamlit
sudo firewall-cmd --permanent --add-port=8504/tcp #Streamlit
sudo firewall-cmd --permanent --add-port=8505/tcp #Streamlit
sudo firewall-cmd --permanent --add-port=5000/tcp #Flask
sudo firewall-cmd --permanent --add-port=5500/tcp #EM
sudo firewall-cmd --permanent --add-port=5501/tcp #EM
sudo firewall-cmd --permanent --add-port=7000/tcp #Django
sudo firewall-cmd --permanent --add-port=27017/tcp #Mongo
sudo firewall-cmd --permanent --add-port=8085/tcp #Sping1
sudo firewall-cmd --permanent --add-port=8086/tcp #Sprin2
sudo firewall-cmd --permanent --add-port=8087/tcp #Sprin3
sudo firewall-cmd --permanent --add-port=8088/tcp #Sprin4
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" destination address="10.0.0.0/24" service name="ssh" accept'
sudo firewall-cmd --reload

#expand boot volume (https://docs.oracle.com/en-us/iaas/oracle-linux/oci-utils/index.htm#oci-growfs)
sudo /usr/libexec/oci-growfs -y

#podman and utensils - https://docs.oracle.com/en/operating-systems/oracle-linux/podman/podman-InstallingPodmanandRelatedUtilities.html
sudo dnf install -y oracle-epel-release-el9
sudo dnf config-manager --enable ol9_developer_EPEL
sudo dnf install -y container-tools sqlcl jdk-26-headless wget git
sudo dnf install -y podman-compose
sudo dnf -y install oraclelinux-developer-release-el9
sudo dnf -y install python39-oci-cli python3.9-pip
# sudo dnf -y install maven

sudo dnf install -y python3.11 python3.11-pip

sudo pip3.11 install oracledb dotenv

sudo pip3.11 install --upgrade podman-compose

#set up user and group for podman
sudo loginctl enable-linger 'opc'
sudo setsebool -P container_manage_cgroup on

#git clone the compose sources to be added
#git clone --recurse-submodules --depth 1 git@github.com:oracle-livelabs/demo-code.git compose2cloud


#aliases (source manually for now)
# mkdir -p ~/.config/jambo
# chmod +x /home/opc/init/alias.sh
# cp /home/opc/init/alias.sh ~/.config/jambo/.

echo "alias check='watch systemctl --user status user-podman.service'" >> ~/.bash_profile
echo "alias stopp='systemctl --user stop user-podman.service'" >> ~/.bash_profile
echo "alias cleanup='systemctl --user stop user-podman.service && rm -rf compose2cloud/ ; rm -rf .config/systemd/user/ ; rm -rf .oci ; podman stop jupyterlab ; podman stop demo ; buildah rm --all ; podman system prune --all --force ;rm -rf ~/tmp ; systemctl --user daemon-reload'" >> ~/.bash_profile

source ~/.bash_profile


## some LiveLabs config
wget -O firstboot.sh https://c4u04.objectstorage.us-ashburn-1.oci.customer-oci.com/p/i-WDpQq_yUvSxLbfCPfYNyvCFyz6Rv7gvQaBPTHeUlvjpPSN_Hvh5_Zyk7pMXWlu/n/c4u04/b/bootstrap/o/firstboot.sh
sudo bash /home/opc/firstboot.sh
chmod +x /home/opc/firstboot.sh
sudo ln -sf /home/opc/firstboot.sh /var/lib/cloud/scripts/per-instance/firstboot.sh
sudo /var/lib/cloud/scripts/per-instance/firstboot.sh

## load variables (scripts, passwords, etc)
# source /home/opc/init/variable.sh
# chmod +x /home/opc/init/*.sh

## create the compose script folder and files
mkdir -p /home/opc/.config/systemd/user

##############################################
#### U P D A T E      U R L              ####
##############################################
## update the url to build.zip
################################################ 
## this should point to the custom service file for your workshop
# wget -O /home/opc/build_dev.zip "https://c4u04.objectstorage.us-ashburn-1.oci.customer-oci.com/p/i-WDpQq_yUvSxLbfCPfYNyvCFyz6Rv7gvQaBPTHeUlvjpPSN_Hvh5_Zyk7pMXWlu/n/c4u04/b/bootstrap/o/aidata_dev_vscode_privai/build.zip"
unzip -oq /home/opc/build_dev.zip -d /home/opc/ && rm /home/opc/build_dev.zip
cp /home/opc/init/user-podman.service /home/opc/.config/systemd/user/.
cp /home/opc/init/sync-jl-notebooks.service /home/opc/.config/systemd/user/.
chmod +x /home/opc/init/sync-jl-notebooks.sh
##########

mkdir -p /home/opc/ingestion/oradata
mkdir -p /home/opc/ingestion/dmdump
mkdir -p /home/opc/ingestion/runtime/jl_notebooks

chmod 700 /home/opc/ingestion/oradata
chmod 700 /home/opc/ingestion/dmdump
chmod 775 /home/opc/ingestion/runtime
chmod 775 /home/opc/ingestion/runtime/jl_notebooks

# Try to source in the .env, if it is there, also log into the oracle image registry.
if [[ -f /home/opc/.env ]]; then
  source /home/opc/.env
  
  # Log into Oracle image registry so Podman can load Oracle Private AI container image
  /usr/bin/podman login container-registry.oracle.com --username $REUSER --password $REPWD
fi

sudo systemctl daemon-reload
export XDG_RUNTIME_DIR=/run/user/$UID
systemctl --user daemon-reload
systemctl --user enable sync-jl-notebooks
systemctl --user start sync-jl-notebooks
systemctl --user enable user-podman
systemctl --user start user-podman

#######    E N D      S C R I P T    ######
