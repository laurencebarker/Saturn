These files provide configuration scripts and files ot set up a Trixie image for Anan radios.

Precursor: clone the Saturn repository first, to get this script!

mkdir github
cd github
git clone https://github.com/laurencebarker/Saturn



There are 3 primary scripts:
installphase0.sh

This script:
1. installs kernel headers
2. installs the required libraries
3. installs XDMA
4. Clones the piHPSDR repository
5. sets the phase 1 script to auto-run next time
at the end of this process, the image can be distributed to radio owners



installphase1.sh
This script needs to be running on the user's hardware. 
1. It works out the correct kernel config file and installs it.
2. thereafter it restarts with the final config stage set to auto-run.



installphase2.sh
This script finalises the installation. It carries out the following steps:
1. installs udev rules
2. git pull Saturn (to get latest)
3. git pull piHPSDR (to get latest)
4. builds p2app
5. builds the other desktop apps
6. builds piHPSDR
7. copies shortcuts to the desktop
8. removes itself from the auto-run list 






Config Files
There are kernel config.txt files required for Trixie OS. Likely to be similar for other OS variants, but please check!

There are files for each of:
CM4 processor, 7" touchscreen display
CM4 processor, 8" touchscreen display
CM5 processor, 7" touchscreen display
CM5 processor, 8" touchscreen display

These need to be copied (bormally by the phase 1 script) 
copy the relevant file to /boot/firmware, eg:
cd ~/github/Saturn/scripts/installfromscratch/Trixieconfig
sudo sp cm5_8inch_config.txt /boot/firmware/config.txt


