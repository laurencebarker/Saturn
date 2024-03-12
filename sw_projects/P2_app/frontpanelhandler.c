/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2 
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// frontpanelhandler.h:
//
// handle interface to front panel controls
//
//////////////////////////////////////////////////////////////

#include "threaddata.h"
#include <stdint.h>
#include "../common/saturntypes.h"
#include <errno.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <pthread.h>

#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/hwaccess.h"
#include "../common/debugaids.h"
#include "frontpanelhandler.h"
#include "g2panel.h"
#include "g2v2panel.h"

char* pi_i2c_device = "/dev/i2c-1";
unsigned int G2MCP23017 = 0x20;                     // i2c slave address of MCP23017 on G2 panel
unsigned int G2V2Arduino = 0x15;                    // i2c slave address of Arduino on G2V2
static int i2c_fd;                                  // file reference
bool FoundG2Panel = false;
bool FoundG2V2Panel = false;


//
// function to initialise a connection to the front panel; call if selected as a command line option
// establish which if any front panel is attached, and get it set up.
//
void InitialiseFrontPanelHandler(void)
{
}


//
// function to initialise a connection to the front panel; call if selected as a command line option
// establish which if any front panel is attached, and get it set up.
//
void ShutdownFrontPanelHandler(void)
{
}

