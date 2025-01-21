################################################################
# update-G2.sh
# pull repository and build p2app
#
#
echo "##############################################################"
echo ""
echo "updating G2:"
echo "pulling new files from repository"
echo ""
echo "##############################################################"
cd ~/github/Saturn
git config pull.rebase false
git pull



echo "making p2app"
./scripts/update-p2app.sh



echo "##############################################################"
echo ""
echo "making desktop apps"
echo ""
echo "##############################################################"
cd ~/github/Saturn
./scripts/update-desktop-apps.sh


echo "setting udev rules"
cd ~/github/Saturn/rules
sudo ./install-rules.sh


echo "##############################################################"
echo ""
echo "copying desktop icons"
echo ""
echo "##############################################################"
cd ~/github/Saturn
cp desktop/* ~/Desktop

 



echo "##############################################################"
echo ""
echo "returning to home folder"
echo ""
echo "the Raspberry Pi programs have now all been updated."
echo "you may need to reflash the FPGA, if it has been updated"
echo ""
echo "execute flashwriter desktop app"
echo "click       Open file"
echo "click       Home"
echo "click       github"
echo "click       Saturn"
echo "click       FPGA"
echo "choose the new .BIT file (eg saturnprimary2024V19.bin)"
echo "click       open"
echo "make sure primary is selected"
echo "click       Program"
echo ""
echo "you will get progress messages and a progress bar. It takes about 3 minutes"
echo ""
echo "completely power off then back on after programming"
echo ""
echo "##############################################################"
cd ~
