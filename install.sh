#!/bin/bash

# Copyright (C) 2021 Xilinx, Inc
#
# SPDX-License-Identifier: BSD-3-Clause

set -e

GRAY='\033[1;30m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]
  then echo -e "${RED}Please run as root${NC}"
  exit
fi

echo -e "${GREEN}Installing PYNQ, this process takes around 25 minutes ${NC}"

echo -e "${YELLOW} Extracting archive kria_v3.0_binaries.tar.gz${NC}"
# Get PYNQ Binaries (gcc-mb/sdist/pynq v3.0/pynqutils/pynqmetadata/xclbinutil)
cp kria_v3.0_binaries.tar.gz /tmp
pushd /tmp
if [ $(file --mime-type -b kria_v3.0_binaries.tar.gz) != "application/gzip" ]; then
  echo -e "${RED}Could not extract pynq binaries, is the tarball named correctly?${NC}\n"
  exit
fi
tar -xvf kria_v3.0_binaries.tar.gz
popd

# Populate the repo
echo -e "${YELLOW} Copying SDIST ${NC}"
sudo rm -rf pynq
cp -r /tmp/kria_v3.0_binaries/pynq-3.0.0 ./
mv pynq-3.0.0 pynq
echo -e "${YELLOW} Copying PYNQmetadata ${NC}"
cp -r /tmp/kria_v3.0_binaries/pydantic-pynq-metadata ./
echo -e "${YELLOW} Copying PYNQutils ${NC}"
cp -r /tmp/kria_v3.0_binaries/pynq-utils ./
echo -e "${YELLOW} Copying Latest PYNQ repo ${NC}"
cp -r /tmp/kria_v3.0_binaries/PYNQ ./PYNQ

ARCH=aarch64
HOME=/root
PYNQ_JUPYTER_NOTEBOOKS=/home/$LOGNAME/jupyter_notebooks
BOARD=KV260
PYNQ_VENV=/usr/local/share/pynq-venv

# Get PYNQ SDbuild Packages
#if [ -d ".git/" ]
#then
#  git submodule init && git submodule update
#else
#  rm -rf pynq/
#  #git clone https://github.com/Xilinx/PYNQ.git -b image_v2.7 --depth 1 pynq
#fi


## Stop unattended upgrades to prevent apt install from failing
systemctl stop unattended-upgrades.service


# Wait for Ubuntu to finish unattended upgrades
while [[ $(lsof -w /var/lib/dpkg/lock-frontend) ]] || [[ $(lsof -w /var/lib/apt/lists/lock) ]]
do
  echo -e "${YELLOW}Waiting for Ubuntu unattended upgrades to finish ${NC}"
  sleep 20s
done

# Install Required Debian Packages
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 \
	        --verbose 803DDF595EA7B6644F9B96B752150A179A9E84C9
echo "deb http://ppa.launchpad.net/ubuntu-xilinx/updates/ubuntu jammy main" > /etc/apt/sources.list.d/xilinx-gstreamer.list
apt update 

apt-get -o DPkg::Lock::Timeout=10 update && \
apt-get install -y python3.10-venv python3-cffi libssl-dev libcurl4-openssl-dev \
  portaudio19-dev libcairo2-dev libdrm-xlnx-dev libopencv-dev python3-opencv graphviz i2c-tools \
  fswebcam

# Install PYNQ Virtual Environment 
cp PYNQ/sdbuild/packages/python_packages_jammy/requirements.txt /root/
pushd PYNQ/sdbuild/packages/python_packages_jammy
mkdir -p $PYNQ_VENV
cat > $PYNQ_VENV/pip.conf <<EOT
[install]
no-build-isolation = yes
EOT

./qemu.sh
popd


# PYNQ VENV Activate Updates
echo "export PYNQ_JUPYTER_NOTEBOOKS=${PYNQ_JUPYTER_NOTEBOOKS}" >> /etc/profile.d/pynq_venv.sh
echo "export BOARD=$BOARD" >> /etc/profile.d/pynq_venv.sh
echo "export XILINX_XRT=/usr" >> /etc/profile.d/pynq_venv.sh
source /etc/profile.d/pynq_venv.sh

# Check to makesure that we are in the venv before proceeding.
if [[ "$VIRTUAL_ENV" == "" ]]
then
        echo "ERROR: could not enter the Pynq venv, stopping the installation"
        exit 1
fi


# PYNQMetadata
pushd pydantic-pynq-metadata
python -m pip install .
popd

# PYNQUtils
pushd pynq-utils
python -m pip install .
popd

# PYNQ JUPYTER
pushd PYNQ/sdbuild/packages/jupyter
./pre.sh
./qemu.sh
popd


# PYNQ Allocator
pushd PYNQ/sdbuild/packages/libsds
./pre.sh
./qemu.sh
popd


# PYNQ Python Package
pushd PYNQ 
python -m pip install . --no-build-isolation
popd


## GCC-MB and XCLBINUTILS
pushd /tmp

cp -r /tmp/kria_v3.0_binaries/gcc-mb/microblazeel-xilinx-elf /usr/local/share/pynq-venv/bin/
echo "export PATH=\$PATH:/usr/local/share/pynq-venv/bin/microblazeel-xilinx-elf/bin/" >> /etc/profile.d/pynq_venv.sh

cp /tmp/kria_v3.0_binaries/xrt/xclbinutil /usr/local/share/pynq-venv/bin/
chmod +x /usr/local/share/pynq-venv/bin/xclbinutil
popd

#cp -r /tmp/pynq-v3.0-binaries/bsps/bsp_iop_pmod /usr/local/share/pynq-venv/lib/python3.10/site-packages/pynq/lib/pmod/

# define the name of the platform
echo "$BOARD" > /etc/xocl.txt


# Compile pynq device tree overlay and insert it by default
pushd dts/
make
mkdir -p /usr/local/share/pynq-venv/pynq-dts/
cp insert_dtbo.py pynq.dtbo /usr/local/share/pynq-venv/pynq-dts/
echo "python3 /usr/local/share/pynq-venv/pynq-dts/insert_dtbo.py" >> /etc/profile.d/pynq_venv.sh

source /etc/profile.d/pynq_venv.sh
popd


#Install base overlay
python3 -m pip install .


#Install PYNQ-HelloWorld
python3 -m pip install pynq-helloworld


# Install composable overlays
pushd /tmp
rm -rf ./PYNQ_Composable_Pipeline
git clone https://github.com/Xilinx/PYNQ_Composable_Pipeline.git -b v1.1.0-dev
python3 -m pip install PYNQ_Composable_Pipeline/ --no-use-pep517
popd

# Install Pynq Peripherals
python3 -m pip install git+https://github.com/Xilinx/PYNQ_Peripherals.git

## Currently no DPU Support 
## Install DPU-PYNQ
#yes Y | apt remove --purge vitis-ai-runtime
#python3 -m pip install pynq-dpu --no-use-pep517
#
# Deliver all notebooks
yes Y | pynq-get-notebooks -p $PYNQ_JUPYTER_NOTEBOOKS -f

# Copy additional notebooks from pynq
cp pynq/pynq/notebooks/common/ -r $PYNQ_JUPYTER_NOTEBOOKS

# Patch notebooks
sed -i "s/\/home\/xilinx\/jupyter_notebooks\/common/\./g" $PYNQ_JUPYTER_NOTEBOOKS/common/python_random.ipynb
sed -i "s/\/home\/xilinx\/jupyter_notebooks\/common/\./g" $PYNQ_JUPYTER_NOTEBOOKS/common/usb_webcam.ipynb

for notebook in $PYNQ_JUPYTER_NOTEBOOKS/pynq_peripherals/*/*.ipynb; do
    sed -i "s/pynq.overlays.base/kv260/g" $notebook
    sed -i "s/PMODB/PMODA/g" $notebook
done

sed -i 's/Specifically a RALink WiFi dongle commonly used with \\n//g' $PYNQ_JUPYTER_NOTEBOOKS/common/wifi.ipynb
sed -i 's/Raspberry Pi kits is connected into the board.//g' $PYNQ_JUPYTER_NOTEBOOKS/common/wifi.ipynb

# Patch microblaze to use virtualenv libraries
sed -i "s/opt\/microblaze/usr\/local\/share\/pynq-venv\/bin/g" /usr/local/share/pynq-venv/lib/python3.10/site-packages/pynq/lib/pynqmicroblaze/rpc.py

# Remove unnecessary notebooks
rm -rf $PYNQ_JUPYTER_NOTEBOOKS/pynq_peripherals/app* $PYNQ_JUPYTER_NOTEBOOKS/pynq_peripherals/grove_joystick

# Change notebooks folder ownership and permissions
chown $LOGNAME:$LOGNAME -R $PYNQ_JUPYTER_NOTEBOOKS
chmod ugo+rw -R $PYNQ_JUPYTER_NOTEBOOKS

# Start Jupyter services 
systemctl start jupyter.service

# Start the service for clearing the statefile on boot
cp PYNQ/sdbuild/packages/clear_pl_statefile/clear_pl_statefile.sh /usr/local/bin
cp PYNQ/sdbuild/packages/clear_pl_statefile/clear_pl_statefile.service /lib/systemd/system
systemctl enable clear_pl_statefile

# Purge libdrm-xlnx-dev to allow `apt upgrade`
apt-get purge -y libdrm-xlnx-dev
apt-get purge -y libdrm-xlnx-amdgpu1

# OpenCV
python3 -m pip install opencv-python
apt-get install ffmpeg libsm6 libxext6 -y

## libssl
#wget wget http://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.1_1.1.0l-1~deb9u6_arm64.deb
#dpkg -i dpkg -i libssl1.1_1.1.0l-1~deb9u6_arm64.deb

# PMOD BSPS
cp -r pynq/pynq/lib/pmod/bsp_iop_pmod /usr/local/share/pynq-venv/lib/python3.10/site-packages/pynq/lib/pmod/

# Latest composable arch
cp -r /tmp/kria_v3.0_binaries/composable/overlay/* /usr/local/share/pynq-venv/lib/python3.10/site-packages/pynq_composable/overlay/
# Clear any stale *.pkl files
rm -rf /usr/local/share/pynq-venv/lib/python3.10/site-packages/pynq_composable/overlay/*.pkl

# Ask to connect to Jupyter
ip_addr=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo -e "${GREEN}PYNQ Installation completed.${NC}\n"
echo -e "\n${YELLOW}To continue with the PYNQ experience, connect to JupyterLab via a web browser using this url: ${ip_addr}:9090/lab or $(hostname):9090/lab - The password is xilinx${NC}\n"
