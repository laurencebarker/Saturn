# script to discover if a front panel is present
# could be none, G2V1 or G2V2
#G2V1: I2C interface, discovered by device presence
#G2V2: serial, discovered by CAT response
# print() response sends back strings as the return value
#
# Laurence barker March 2026
# written as Python script as bash serial seems unreliable
#
import serial
import os
import sys
import smbus

G2V2Found = False
G2V1Found = False

serial_path = '/dev/serial/by-id/g2-front-9600'
if os.path.exists(serial_path):
	ser = serial.Serial(serial_path, 9600, timeout=1)
	ser.write(b'ZZZS;')
	ser.flush()
	# we should now get a zzzs response with panel id
	str=ser.read_until(b';')
	#look for "ZZZS05" to identify a G2V2
	startpoint=str.find(b'ZZZS05') #-1 if not found
	if(startpoint == 0):
		G2V2Found = True

	ser.close()


# detect presence of G2V1 from MCP32017 with address 32
bus=smbus.SMBus(1) # /dev/i2c1
try:
	bus.read_byte(32)
	G2V1Found=True
except:
	G2V1Found=False
	

if (G2V1Found==True):
	print("G2V1")
elif (G2V2Found==True):
	print("G2V2")
else:
	print("NONE")

sys.exit(0)
