#
# install serial port rules file in /etc/udev/rules.d
# this needs to be run as sudo!

echo "##############################################################"
echo ""
echo "installing serial rules file:"
echo ""
echo "##############################################################"

sudo cp 61-g2-serial.rules /etc/udev/rules.d
sudo udevadm control --reload-rules && sudo udevadm trigger 
