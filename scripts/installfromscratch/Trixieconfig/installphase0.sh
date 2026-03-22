#
# script for initial configuration of an image file 
# 3 scripts to be run in sequence:
#   installphase0.sh
#   installphase1.sh
#   installphase2.sh

#
#            installphase0.sh
# this starts from just the Saturn repository cloned
# and ends with an image ready to be run on users' hardware.
#
# before this script is run you should have cloned the Saturn repository:
#  $ mkdir github
#  $ cd github
#  $ git clone https://github.com/laurencebarker/Saturn

# and make the scripts executable
#  $ cd ~/github/Saturn/scripts/installfromscratch/Trixieconfig
#  $ chmod +x installphase0.sh
#  $ chmod +x installphase1.sh
#  $ chmod +x installphase2.sh
#
# then run this script
#  $ ./installphase0.sh
#
# further scripts will need to be auto-run after this one:
# installphase1.sh
#   select the correct kernel config.txt file
#
# installphase2.sh
#   install the remaining applications
#

#
#            installphase0.sh
#

#install the kernel headers:
echo "Installing kernel headers"
echo 
sudo apt install linux-headers-rpi-v8
echo 
echo "================================================================="


# install the required libraries
echo 
echo "Installing libraries"
sudo apt-get install -y libgpiod-dev
sudo apt-get install -y libi2c-dev
sudo apt-get install -y rsync
sudo apt-get install -y lxterminal
sudo apt-get install -y libglib2.0-bin
sudo apt-get install -y libgtk-3-dev
echo 
echo "================================================================="


# install xdma
echo 
echo "Installing xdma device driver"
sudo rmmod xdma
cd ~/github/Saturn/linuxdriver/xdma
make
sudo make install
sudo modprobe xdma
sudo cp ../etc/udev/rules.d/* /etc/udev/rules.d

echo 
echo "================================================================="

# clone piHPSDR
echo 
echo "Cloning piHPSDR repository"
cd ~/github
git clone https://github.com/dl1ycf/pihpsdr
echo 
echo "================================================================="


# prepare to auto-run the phase 1 script
