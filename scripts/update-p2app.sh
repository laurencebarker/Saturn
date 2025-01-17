################################################################
# update-p2app.sh
# build p2app executable
#
#

echo "##############################################################"
echo ""
echo "making p2app"
echo "this will create a lot of warning - please ignore them"
echo ""
echo "##############################################################"
cd ~/github/Saturn/sw_projects/P2_app
make clean
make

