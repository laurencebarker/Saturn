//
// write to Codec registers using XDMA driver
// Laurence Barker July 2022
//

#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 500
#include <assert.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>

#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#include "../common/xiic_regdefs.h"
#include "../common/hwaccess.h"

//
// addresses of codec device
//
#define VCODEC7BITADDR 0x1A						// addr of codec device on I2C bus
#define VIICIPCOREADDR 0x14000					// AXILite address for core


////////////////////////////////////// code cut from xiic_l.c //////////////////////////////////

//
// Read from the specified IIC device register.
//
// BaseAddress is the base address of the device.
// RegOffset is the offset from the 1st register of the device to select the specific register.
//
// returns	The value read from the register.
//
uint32_t XIic_ReadReg(uint32_t BaseAddress, uint32_t RegOffset)
{
	uint32_t Result;
	Result = RegisterRead(BaseAddress + RegOffset);
	return Result;
}



//
// Write to the specified IIC device register.
//
// BaseAddress is the base address of the device.
// RegOffset is the offset from the 1st register of the device to select the specific register.
// RegisterValue is the value to be written to the register.
//
void XIic_WriteReg(uint32_t BaseAddress, uint32_t RegOffset, uint32_t RegisterValue)
{
	RegisterWrite(BaseAddress + RegOffset, RegisterValue);
}


//
// This is a function which tells whether the I2C bus is busy or free.
//
// BaseAddr is the base address of the I2C core to work on.
// return
//		- TRUE if the bus is busy.
//		- FALSE if the bus is NOT busy.
//
uint32_t XIic_CheckIsBusBusy(uint32_t BaseAddress)
{
	uint32_t StatusReg;

	StatusReg = XIic_ReadReg(BaseAddress, XIIC_SR_REG_OFFSET);
	if (StatusReg & XIIC_SR_BUS_BUSY_MASK) 
		return 1;
	else
		return 0;
}

//
// This function will wait until the I2C bus is free or timeout.
//
// BaseAddress contains the base address of the I2C device.
// returns
//		- XST_SUCCESS if the I2C bus was freed before the timeout.
//		- XST_FAILURE otherwise.
//
uint32_t XIic_WaitBusFree(uint32_t BaseAddress)
{
	uint32_t BusyCount = 0;

	while (XIic_CheckIsBusBusy(BaseAddress)) 
	{
		if (BusyCount++ > 10000) 
			return XST_FAILURE;
		usleep(100);
	}

	return XST_SUCCESS;
}




//
// This macro sends the address for a 7 bit address during both read and write
// operations. It takes care of the details to format the address correctly.
// This macro is designed to be called internally to the drivers.
//
// BaseAddress is the base address of the IIC Device.
// SlaveAddress is the address of the slave to send to.
// Operation indicates XIIC_READ_OPERATION or XIIC_WRITE_OPERATION
//
void XIic_Send7BitAddress(uint32_t BaseAddress, uint8_t SlaveAddress, uint8_t Operation)
{
	uint8_t LocalAddr = (SlaveAddress << 1);
	LocalAddr = (LocalAddr & 0xFE) | (Operation);
	XIic_WriteReg(BaseAddress, XIIC_DTR_REG_OFFSET, LocalAddr);
	printf("Sent 7 bit addr word 0x%2X\n", LocalAddr);
}




//
// This function gets the contents of the Interrupt Status Register.
// This register indicates the status of interrupt sources for the device.
// The status is independent of whether interrupts are enabled such
// that the status register may also be polled when interrupts are not enabled.
//
// BaseAddress is the base address of the IIC device.
//
// returns The value read from the Interrupt Status Register.
//
uint32_t XIic_ReadIisr(uint32_t BaseAddress)
{
	return XIic_ReadReg(BaseAddress, XIIC_IISR_OFFSET);
}



//
// This function sets the Interrupt status register to the specified value.
//
// This register implements a toggle on write functionality. The interrupt is
// cleared by writing to this register with the bits to be cleared set to a one
// and all others to zero. Setting a bit which is zero within this register
// causes an interrupt to be generated.
//
// This function writes only the specified value to the register such that
// some status bits may be set and others cleared.  It is the caller's
// responsibility to get the value of the register prior to setting the value
// to prevent an destructive behavior.
//
// BaseAddress is the base address of the IIC device.
// Status is the value to be written to the Interrupt status register.
//
void XIic_WriteIisr(uint32_t BaseAddress, uint32_t Status)
{
	XIic_WriteReg(BaseAddress, XIIC_IISR_OFFSET, Status);
}	




// This macro clears the specified interrupt in the Interrupt status
// register.  It is non-destructive in that the register is read and only the
// interrupt specified is cleared.  Clearing an interrupt acknowledges it.
//
// BaseAddress is the base address of the IIC device.
// InterruptMask is the bit mask of the interrupts to be cleared.
//
void XIic_ClearIisr(uint32_t BaseAddress, uint32_t InterruptMask)
{
	uint32_t RegValue;
	RegValue = XIic_ReadIisr(BaseAddress);
	XIic_WriteIisr(BaseAddress, RegValue & InterruptMask);
}




//
// write to a Codec register. Based on Xlic_Send but stripped down.
// Send data as a master on the IIC bus.  This function sends the data
// using polled I/O and blocks until the data has been sent. It only supports
// 7 bit addressing mode of operation.  This function returns zero if bus is busy.
//
// returns the number of bytes sent.
//
uint32_t I2CWriteCodecRegister(uint16_t CodecData)
{
	uint32_t ControlReg;
	uint32_t IntrStatus;
	uint8_t HighByte, LowByte;
	volatile uint32_t StatusReg;

	HighByte = CodecData >> 8;				// high byte 1st
	LowByte = CodecData & 0xFF;				// low byte 2nd

	/* Wait until I2C bus is freed, exit if timed out. */
	if (XIic_WaitBusFree(VIICIPCOREADDR) != XST_SUCCESS)
	{
		IntrStatus = XIic_ReadIisr(VIICIPCOREADDR);
		printf("I2C bus not freed; ISR = %2x\n", IntrStatus);
		return 0;
	}

	// Check to see if already Master on the Bus.
	// If Repeated Start bit is not set send Start bit by setting
	// MSMS bit else Send the address.
	//
	ControlReg = XIic_ReadReg(VIICIPCOREADDR,  XIIC_CR_REG_OFFSET);
	if ((ControlReg & XIIC_CR_REPEATED_START_MASK) == 0)
	{
		//
		// Put the address into the FIFO to be sent and indicate
		// that the operation to be performed on the bus is a
		// write operation
		//
		XIic_Send7BitAddress(VIICIPCOREADDR, VCODEC7BITADDR, XIIC_WRITE_OPERATION);
		// Clear the latched interrupt status so that it will
		// be updated with the new state when it changes, this
		// must be done after the address is put in the FIFO
		//
		XIic_ClearIisr(VIICIPCOREADDR, XIIC_INTR_TX_EMPTY_MASK |
				XIIC_INTR_TX_ERROR_MASK |
				XIIC_INTR_ARB_LOST_MASK);

		//
		// MSMS must be set after putting data into transmit FIFO,
		// indicate the direction is transmit, this device is master
		// and enable the IIC device
		//
		XIic_WriteReg(VIICIPCOREADDR,  XIIC_CR_REG_OFFSET,
			 XIIC_CR_MSMS_MASK | XIIC_CR_DIR_IS_TX_MASK |
			 XIIC_CR_ENABLE_DEVICE_MASK);
		//
		// Clear the latched interrupt
		// status for the bus not busy bit which must be done while
		// the bus is busy
		//
		StatusReg = XIic_ReadReg(VIICIPCOREADDR,  XIIC_SR_REG_OFFSET);
		while ((StatusReg & XIIC_SR_BUS_BUSY_MASK) == 0)
			StatusReg = XIic_ReadReg(VIICIPCOREADDR, XIIC_SR_REG_OFFSET);

		XIic_ClearIisr(VIICIPCOREADDR, XIIC_INTR_BNB_MASK);
	}
	else				// already configured in right mode
	{
		//
		// Already owns the Bus indicating that its a Repeated Start
		// call. 7 bit slave address, send the address for a write
		// operation and set the state to indicate the address has
		// been sent.
		//
		XIic_Send7BitAddress(VIICIPCOREADDR, VCODEC7BITADDR, XIIC_WRITE_OPERATION);
	}
	//
	// Send bytes. 
	// Wait for the transmit to be empty before sending any more
	// data by polling the interrupt status register
	//
	while (1)
	{
		IntrStatus = XIic_ReadIisr(VIICIPCOREADDR);
		if (IntrStatus & (XIIC_INTR_TX_ERROR_MASK | XIIC_INTR_ARB_LOST_MASK | XIIC_INTR_BNB_MASK))
		{
				printf("TX error or arb lost. ISR = %2x\n", IntrStatus);
				return 0;
		}
		if (IntrStatus & XIIC_INTR_TX_EMPTY_MASK) 
			break;
	}
	//
	// Put the 1st byte in the FIFO & wait till empty
	// issue a "stop" after 1st byte
	//
	XIic_WriteReg(VIICIPCOREADDR,  XIIC_DTR_REG_OFFSET, HighByte);	// high byte
	printf("Sent 1st Byte 0x%02X\n", HighByte);

	while (1)				// wait till TX empty
	{
		IntrStatus = XIic_ReadIisr(VIICIPCOREADDR);
		if (IntrStatus & (XIIC_INTR_TX_ERROR_MASK | XIIC_INTR_ARB_LOST_MASK | XIIC_INTR_BNB_MASK))
		{
			printf("TX error or arb lost. ISR = %2x\n", IntrStatus);
			return 0;
		}
		if (IntrStatus & XIIC_INTR_TX_EMPTY_MASK)
			break;
	}
	XIic_WriteReg(VIICIPCOREADDR, XIIC_CR_REG_OFFSET, XIIC_CR_ENABLE_DEVICE_MASK | XIIC_CR_DIR_IS_TX_MASK);
	XIic_WriteReg(VIICIPCOREADDR,  XIIC_DTR_REG_OFFSET, LowByte); // low byte
	printf("Sent 2nd Byte 0x%02X\n", LowByte);

	while (1)				// wait till TX empty
	{
		IntrStatus = XIic_ReadIisr(VIICIPCOREADDR);
		if (IntrStatus & (XIIC_INTR_TX_ERROR_MASK | XIIC_INTR_ARB_LOST_MASK | XIIC_INTR_BNB_MASK))
		{
			printf("TX error or arb lost. ISR = %2x\n", IntrStatus);
			return 0;
		}
		if (IntrStatus & XIIC_INTR_TX_EMPTY_MASK)
			break;
	}

	//
	// Clear the latched interrupt status register and this must be
	// done after the transmit FIFO has been written to or it won't clear
	//
	XIic_ClearIisr(VIICIPCOREADDR, XIIC_INTR_TX_EMPTY_MASK);
	//
	// that should be the data sent!
	//

	ControlReg = XIic_ReadReg(VIICIPCOREADDR,  XIIC_CR_REG_OFFSET);
	if ((ControlReg & XIIC_CR_REPEATED_START_MASK) == 0)
	{
		//
		// The Transmission is completed, disable the IIC device if
		// the Option is to release the Bus after transmission of data
		// and return the number of bytes that was received. Only wait
		// if master, if addressed as slave just reset to release
		// the bus.
		//
		if ((ControlReg & XIIC_CR_MSMS_MASK) != 0)
			XIic_WriteReg(VIICIPCOREADDR,  XIIC_CR_REG_OFFSET, (ControlReg & ~XIIC_CR_MSMS_MASK));

		if ((XIic_ReadReg(VIICIPCOREADDR, XIIC_SR_REG_OFFSET) & XIIC_SR_ADDR_AS_SLAVE_MASK) != 0)
			XIic_WriteReg(VIICIPCOREADDR,  XIIC_CR_REG_OFFSET, 0);
		else
		{
			StatusReg = XIic_ReadReg(VIICIPCOREADDR, XIIC_SR_REG_OFFSET);
			while ((StatusReg & XIIC_SR_BUS_BUSY_MASK) != 0)
				StatusReg = XIic_ReadReg(VIICIPCOREADDR, XIIC_SR_REG_OFFSET);
		}
	}

	return 2;
}


//
// 8 bit Codec register write over the AXILite bus via I2C
// given 7 bit register address and 9 bit data
//
void CodecRegisterWrite(unsigned int Address, unsigned int Data)
{
unsigned int ByteCount;

	ByteCount = I2CWriteCodecRegister((Address << 9) | Data);
	printf("Codec write: send %02x to Codec register address %02x; transferred %d bytes\n", Data, Address, ByteCount);
}

