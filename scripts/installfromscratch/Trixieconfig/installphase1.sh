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
# 1. whether a t7" or 8" display is fitted;
# 2. whether the code runs on a CM4 or CM5 processor. 
# remember we are setting up code for existing users' radio, not just new build!
#



