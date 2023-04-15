Laurence Barker 27/6/2021:
build instructions for the XDMA driver

1. get the kernel headers so the kernel module can compile: 
(note if this fails you will need to use an older OS release, or rebuild the kernel 
by following the instructions at https://www.raspberrypi.org/documentation/linux/kernel/building.md)


sudo apt install raspberrypi-kernel-headers


2. build the kernel module:

cd ~/github/Saturn/linuxdriver/xdma
make
sudo make install



3. copy the module "rules" files to /etc (among other things, this causes the access permissions to be changed when the module loads and the /dev/xdma devices are added)


sudo cp ../etc/udev/rules.d/* /etc/udev/rules.d



4. load the module: this results in the module loading every time the system boots, as required

sudo modprobe xdma


5. if it is necessary to unload the module (eg to recompile it)

rmmod -s xdma


6. to buld the tools for testing:

cd ~/github/saturn/linuxdriver/tools
make