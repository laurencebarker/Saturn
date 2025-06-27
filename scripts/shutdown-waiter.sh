#
# script to wait for a shutdown input
# put GPIO26 (pin 37) into pullup mode
# The first read will be before the pullup is activated
# so wait for a delay before scanning proper. 
#
sleep 20
gpioget --bias=pull-up gpiochip0 26
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

