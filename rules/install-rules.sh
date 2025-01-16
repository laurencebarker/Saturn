#
# install serial port rules file in /etc/udev/rules.d
# this needs ot be run as sudo!

echo installing serial rules file:
sudo cp 61-g2-serial.rules /etc/udev/rules.d
sudo udevadm control --reload-rules && sudo udevadm trigger 
