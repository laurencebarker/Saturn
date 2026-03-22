#
# script to wait for a shutdown input
# put GPIO26 (pin 37) into input pullup mode
# The first read will be before the pullup is activated
# so wait for a delay before scanning proper. 
#
# set gpio18 to input, pullup so that it can be sensed
# by a high imprednace microcontroller input
#
# this should only be needed on G2V2 vintage radios. 
# Radios with a G2V1 panel use GPIO26 as an encodeer input.
# so exit script if G2V1 I2C device is found.
#
# this version determines the libgpiod version.
# gpiod V2 (Trixie onwards) has a different API
#
if i2cget -y 1 0x20
then
	echo "i2c device found, so shutdown waiter not needed"
else
	echo "G2V2 type radio found with no I2C device"
	gpiodversion=$(apt-cache policy gpiod |grep "Installed")
	majorversion=${gpiodversion:13:1}
	if [ $majorversion -eq 1 ]
	then 
		echo "gpiod v1 detected: Bookworm or earlier OS"
		sleep 20
		gpioget --bias=pull-up gpiochip0 26
		gpioget --bias=pull-up gpiochip0 18
		pinvalue=1
		sleep 2
		echo "waiting for shutdown to be triggered..."
		while [ $pinvalue -eq 1 ]
		do
	# poll input every second, and wait for logic zero
			pinvalue=$(gpioget --bias=pull-up gpiochip0 26)
			sleep 1
		done
		echo "shutdown request detected"
		shutdown 0
	else
		echo "gpiod v2 detected: Trixie or later OS"
		sleep 20
		gpioget -c 0 -b pull-up --numeric 26
		gpioget -c 0 -b pull-up --numeric 18
		pinvalue=1
		sleep 2
		echo "waiting for shutdown to be triggered..."
		while [ $pinvalue -eq 1 ]
		do
	# poll input every second, and wait for logic zero
			pinvalue=$(gpioget -c 0 -b pull-up --numeric 26)
			sleep 1
		done
		echo "shutdown request detected"
		shutdown 0
	fi
fi
