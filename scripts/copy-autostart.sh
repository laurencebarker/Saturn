#
# script to copy autostart files to autostart folder
#
if [ "$1" == "display" ];  then
echo "copying piHPSDR startup, and shutdown script"
rm -f /home/pi/.config/autostart/*
cd /home/pi/github/Saturn/autostart-files
cp g2-shutdown.desktop /home/pi/.config/autostart
cp g2-autostart-piHPSDR.desktop /home/pi/.config/autostart

elif [ "$1" == "nodisplay" ]; then
echo "copying p2app startup, and shutdown script"
rm -f /home/pi/.config/autostart/*
cd /home/pi/github/Saturn/autostart-files
cp g2-shutdown.desktop /home/pi/.config/autostart
cp g2-autostart-p2app.desktop /home/pi/.config/autostart

else
echo "usage: ./copy-autostart.sh display (if there is a display on your radio)"
echo "    or ./copy-autostart.sh nodisplay"
fi
