################################################################
# update-desktop-apps.sh
# build additional desktop apps
#
#


echo "##############################################################"
echo ""
echo "making bias check app"
echo ""
echo "##############################################################"
cd ~/github/Saturn/sw_projects/biascheck
make clean 
make


echo "##############################################################"
echo ""
echo "making audio test app"
echo ""
echo "##############################################################"
cd ~/github/Saturn/sw_projects/audiotest
make clean 
make


echo "##############################################################"
echo ""
echo "making AXI reader/writer app"
echo ""
echo "##############################################################"
cd ~/github/Saturn/sw_tools/axi_rw
make clean 
make


echo "##############################################################"
echo ""
echo "making flash writer app"
echo ""
echo "##############################################################"
cd ~/github/Saturn/sw_tools/flashwriter
make clean 
make


echo "##############################################################"
echo ""
echo "Copying Desktop shortcuts"
echo ""
echo "##############################################################"
#




