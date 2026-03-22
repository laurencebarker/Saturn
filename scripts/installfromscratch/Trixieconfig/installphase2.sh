#
# script for initial configuration of an image file 
# 3 scripts to be run in sequence:
#   installphase0.sh
#   installphase1.sh
#   installphase2.sh
#
#            installphase2.sh
# this script install the remaining applications

# before this script is run you should have cloned the Saturn repository
# and run installphase0.sh
#  $ mkdir github
#  $ cd github
#  $ git clone https://github.com/laurencebarker/Saturn

# and run the phase 0 script
#  $ cd ~/github/Saturn/scripts/installfromscratch/Trixieconfig
#  $ sudo chmod +X installphase0.sh
#  $ sudo ./installphase0.sh
#
# there should have been a reboot; phase 1 should have auto-run, the rebooted
# this script should auto-run after a restart


#
#            installphase2.sh
#

# install the udev rules
echo 
echo "Installing udev rules"
sudo bash ~/github/Saturn/rules/install-rules.sh
echo 
echo "================================================================="


# git pull the repositories, to make sure we have the latest
echo 
echo "updating saturn git repository to the newest version"
cd ~/github/Saturn
git pull
echo "updating piHPSDR git repository to the newest version"
cd ~/github/pihpsdr
git pull
echo 
echo "================================================================="


# build p2app
echo 
echo "building p2app"
cd ~/github/Saturn/sw_projects/P2_app
make clean
make
echo 
echo "================================================================="


# build desktop FPGA flash writer
echo 
echo "building desktop FPGA flash writer"
cd ~/github/Saturn/sw_tools/flashwriter
make clean
make
echo 
echo "================================================================="

# build desktop axi register read/writer
echo 
echo "building desktop register read/writer"
cd ~/github/Saturn/sw_tools/axi_rw
make clean
make
echo 
echo "================================================================="

# build FPGA version reader
echo 
echo "building FPGA version reader"
cd ~/github/Saturn/sw_tools/FPGAVersion
make clean
make
echo 
echo "================================================================="

# build command line FPGA programmer
echo 
echo "building command line FPGA programmer"
cd ~/github/Saturn/sw_tools/load-FPGA
make clean
make
echo 
echo "================================================================="

# build command line FPGA flash writer
echo 
echo "building command line FPGA flash writer"
cd ~/github/Saturn/sw_tools/load-FPGA
make clean
make
echo 
echo "================================================================="

# build desktop audiotest app
echo 
echo "building desktop audiotest app"
cd ~/github/Saturn/sw_projects/audiotest
make clean
make
echo 
echo "================================================================="

# build desktop biashheck app
echo 
echo "building desktop biascheck app"
cd ~/github/Saturn/sw_projects/biascheck
make clean
make
echo 
echo "================================================================="

# program FPGA with newest code
echo 
echo "updating FPGA"
cd ~/github/Saturn/scripts
bash program-bin.sh
echo 
echo "================================================================="

# build desktop piHPSDR
echo 
echo "building piHPSDR"
cd ~/github/pihpsdr
./LINUX/libinstall.sh
make
echo 
echo "================================================================="

# install desktop shortcuts and auto-run files
echo 
echo "adding desktop shortcuts and auto-run files"
cd ~/github/Saturn/desktop
cp Audiotest ~/Desktop
cp AXIReaderWriter ~/Desktop
cp biascheck ~/Desktop
cp flashwriter ~/Desktop
cp p2app ~/Desktop

mkdir ~/.config/autostart
cd ~/github/Saturn/autostart-files
cp g2-shutdown.desktop ~/.config/autostart

echo 
echo "================================================================="
