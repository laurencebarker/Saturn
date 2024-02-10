#!/bin/bash
# simple script to update Saturn code 

audiotestdir=~/github/Saturn/sw_projects/audiotest
p2appdir=~/github/Saturn/sw_projects/P2_app

echo "removing existing audiotest app"
cd $audiotestdir
make clean

echo "removing existing p2app app"
cd $p2appdir
make clean

echo "getting noew code from git"
git pull

echo "rebuilding audiotest app"
cd $audiotestdir
make

echo "rebuilding p2app app"
cd $p2appdir
make



