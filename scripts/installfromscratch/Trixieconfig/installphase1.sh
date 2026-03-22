#
# script for initial configuration of an image file 
# 3 scripts to be run in sequence:
#   installphase0.sh
#   installphase1.sh
#   installphase2.sh
#
#            installphase0.sh
# This script selects the correct kernel config.txt file
 
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
# this script should auto-run, then reboot
#
# after this script finishes it should set installphase2.sh to auto-run, then reboot



#
#            installphase1.sh
# this script needs to work out the correct config.txt file, then install it
# this depends on:
# 1. whether a 7" display is fitted;
# 2. whether the code runs on a CM4 or CM5 processor. 
# remember we are setting up code for existing users' radio, not just new build!
#
cd ~/github/Saturn/scripts/installfromscratch/Trixieconfig
# discover the processor type:
CMText=$(cat /sys/firmware/devicetree/base/model)
CMModel=${CMText:28:1}
#discover the 7" panel: then copy a file to config.txt
#
if i2cget -y 1 0x20
then
	echo "7 inch display present"
	if [ $CMModel -eq 5 ]
	then
		sudo cp cm5_7inch_config.txt /boot/firmware/config.txt
	else
		sudo cp cm4_7inch_config.txt /boot/firmware/config.txt
	fi
	
else
	echo "7 inch display is not fitted"
	if [ $CMModel -eq 5 ]
	then
		sudo cp cm5_8inch_config.txt /boot/firmware/config.txt
	else
		sudo cp cm4_8inch_config.txt /boot/firmware/config.txt
	fi
fi


#
# now set to restart with installphase2 script auto-running
#
