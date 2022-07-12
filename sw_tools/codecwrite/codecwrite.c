//
// test of write to Codec registers using XDMA driver
// Laurence Barker July 2022
//
// ./codecwrite
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
#include "xiic_regdefs.h"

//#define VTRANSFERSIZE 65536											// size in bytes to transfer
#define VMEMBUFFERSIZE 32768										// memory buffer to reserve
#define AXIBaseAddress 0x10000									// address of StreamRead/Writer IP

//
// mem read/write variables:
//
	int register_fd;                             // device identifier

//
// 32 bit register write over the AXILite bus
//
void RegisterWrite(uint32_t Address, uint32_t Data)
{
    ssize_t nsent = pwrite(register_fd, &Data, sizeof(Data), (off_t) Address); 
    if (nsent != sizeof(Data))
        printf("ERROR: Write: addr=0x%08X   error=%s\n",Address, strerror(errno));
}


uint32_t RegisterRead(uint32_t Address)
{
	uint32_t result = 0;

    ssize_t nread = pread(register_fd, &result, sizeof(result), (off_t) Address);
    if (nread != sizeof(result))
        printf("ERROR: register read: addr=0x%08X   error=%s\n",Address, strerror(errno));
    return result;
}


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
// Send the specified buffer to the device that has been previously addressed
// on the IIC bus.  This function assumes that the 7 bit address has been sent
// and it should wait for the transmit of the address to complete.
//
// BaseAddress contains the base address of the IIC device.
// BufferPtr points to the data to be sent.
// ByteCount is the number of bytes to be sent.
// Option indicates whether to hold or free the bus after transmitting the data.
//
// returns The number of bytes remaining to be sent.
// note
//
// This function does not take advantage of the transmit FIFO because it is
// designed for minimal code space and complexity.  It contains loops that
// that could cause the function not to return if the hardware is not working.
//
static unsigned SendData(uint32_t BaseAddress, uint8_t *BufferPtr,
			 uint32_t ByteCount, uint8_t Option)
{
	uint32_t IntrStatus;

	/*
	 * Send the specified number of bytes in the specified buffer by polling
	 * the device registers and blocking until complete
	 */
	while (ByteCount > 0)
	{
		/*
		 * Wait for the transmit to be empty before sending any more
		 * data by polling the interrupt status register
		 */
		while (1)
		{
			IntrStatus = XIic_ReadIisr(BaseAddress);

			if (IntrStatus & (XIIC_INTR_TX_ERROR_MASK | XIIC_INTR_ARB_LOST_MASK | XIIC_INTR_BNB_MASK))
				return ByteCount;

			if (IntrStatus & XIIC_INTR_TX_EMPTY_MASK) 
				break;
		}
		/* If there is more than one byte to send then put the
		 * next byte to send into the transmit FIFO
		 */
		if (ByteCount > 1)
		{
			XIic_WriteReg(BaseAddress,  XIIC_DTR_REG_OFFSET, *BufferPtr++);
		}
		else
		{
			if (Option == XIIC_STOP)
			{
				/*
				 * If the Option is to release the bus after
				 * the last data byte, Set the stop Option
				 * before sending the last byte of data so
				 * that the stop Option will be generated
				 * immediately following the data. This is
				 * done by clearing the MSMS bit in the
				 * control register.
				 */
				XIic_WriteReg(BaseAddress,  XIIC_CR_REG_OFFSET,
					 XIIC_CR_ENABLE_DEVICE_MASK |
					 XIIC_CR_DIR_IS_TX_MASK);
			}

			/*
			 * Put the last byte to send in the transmit FIFO
			 */
			XIic_WriteReg(BaseAddress,  XIIC_DTR_REG_OFFSET, *BufferPtr++);

			if (Option == XIIC_REPEATED_START)
			{
				XIic_ClearIisr(BaseAddress, XIIC_INTR_TX_EMPTY_MASK);
				/*
				 * Wait for the transmit to be empty before
				 * setting RSTA bit.
				 */
				while (1)
				{
					IntrStatus = XIic_ReadIisr(BaseAddress);
					if (IntrStatus & XIIC_INTR_TX_EMPTY_MASK)
					{
						/*
						 * RSTA bit should be set only
						 * when the FIFO is completely
						 * Empty.
						 */
						XIic_WriteReg(BaseAddress, XIIC_CR_REG_OFFSET, XIIC_CR_REPEATED_START_MASK | 
													XIIC_CR_ENABLE_DEVICE_MASK | XIIC_CR_DIR_IS_TX_MASK | XIIC_CR_MSMS_MASK);
						break;
					}
				}
			}
		}

		/*
		 * Clear the latched interrupt status register and this must be
		 * done after the transmit FIFO has been written to or it won't
		 * clear
		 */
		XIic_ClearIisr(BaseAddress, XIIC_INTR_TX_EMPTY_MASK);

		/*
		 * Update the byte count to reflect the byte sent and clear
		 * the latched interrupt status so it will be updated for the
		 * new state
		 */
		ByteCount--;
	}

	if (Option == XIIC_STOP) {
		/*
		 * If the Option is to release the bus after transmission of
		 * data, Wait for the bus to transition to not busy before
		 * returning, the IIC device cannot be disabled until this
		 * occurs. Note that this is different from a receive operation
		 * because the stop Option causes the bus to go not busy.
		 */
		while (1) {
			if (XIic_ReadIisr(BaseAddress) &
				XIIC_INTR_BNB_MASK) {
				break;
			}
		}
	}

	return ByteCount;
}





//
// Send data as a master on the IIC bus.  This function sends the data
// using polled I/O and blocks until the data has been sent. It only supports
// 7 bit addressing mode of operation.  This function returns zero if bus is busy.
//
// BaseAddress contains the base address of the IIC device.
// Address contains the 7 bit IIC address of the device to send the	specified data to.
// BufferPtr points to the data to be sent.
// ByteCount is the number of bytes to be sent.
// Option indicates whether to hold or free the bus after
// 		transmitting the data.
//
// returns	The number of bytes sent.
//
uint32_t XIic_Send(uint32_t BaseAddress, uint8_t Address,
		   uint8_t *BufferPtr, unsigned ByteCount, uint8_t Option)
{
	uint32_t RemainingByteCount;
	uint32_t ControlReg;
	volatile uint32_t StatusReg;

	/* Wait until I2C bus is freed, exit if timed out. */
	if (XIic_WaitBusFree(BaseAddress) != XST_SUCCESS)
		return 0;

	/* Check to see if already Master on the Bus.
	 * If Repeated Start bit is not set send Start bit by setting
	 * MSMS bit else Send the address.
	 */
	ControlReg = XIic_ReadReg(BaseAddress,  XIIC_CR_REG_OFFSET);
	if ((ControlReg & XIIC_CR_REPEATED_START_MASK) == 0)
	{
		/*
		 * Put the address into the FIFO to be sent and indicate
		 * that the operation to be performed on the bus is a
		 * write operation
		 */
		XIic_Send7BitAddress(BaseAddress, Address, XIIC_WRITE_OPERATION);
		/* Clear the latched interrupt status so that it will
		 * be updated with the new state when it changes, this
		 * must be done after the address is put in the FIFO
		 */
		XIic_ClearIisr(BaseAddress, XIIC_INTR_TX_EMPTY_MASK |
				XIIC_INTR_TX_ERROR_MASK |
				XIIC_INTR_ARB_LOST_MASK);

		/*
		 * MSMS must be set after putting data into transmit FIFO,
		 * indicate the direction is transmit, this device is master
		 * and enable the IIC device
		 */
		XIic_WriteReg(BaseAddress,  XIIC_CR_REG_OFFSET,
			 XIIC_CR_MSMS_MASK | XIIC_CR_DIR_IS_TX_MASK |
			 XIIC_CR_ENABLE_DEVICE_MASK);

		/*
		 * Clear the latched interrupt
		 * status for the bus not busy bit which must be done while
		 * the bus is busy
		 */
		StatusReg = XIic_ReadReg(BaseAddress,  XIIC_SR_REG_OFFSET);
		while ((StatusReg & XIIC_SR_BUS_BUSY_MASK) == 0)
		{
			StatusReg = XIic_ReadReg(BaseAddress, XIIC_SR_REG_OFFSET);
		}

		XIic_ClearIisr(BaseAddress, XIIC_INTR_BNB_MASK);
	}
	else
	{
		/*
		 * Already owns the Bus indicating that its a Repeated Start
		 * call. 7 bit slave address, send the address for a write
		 * operation and set the state to indicate the address has
		 * been sent.
		 */
		XIic_Send7BitAddress(BaseAddress, Address, XIIC_WRITE_OPERATION);
	}

	/* Send the specified data to the device on the IIC bus specified by the
	 * the address
	 */
	RemainingByteCount = SendData(BaseAddress, BufferPtr, ByteCount, Option);

	ControlReg = XIic_ReadReg(BaseAddress,  XIIC_CR_REG_OFFSET);
	if ((ControlReg & XIIC_CR_REPEATED_START_MASK) == 0)
	{
		/*
		 * The Transmission is completed, disable the IIC device if
		 * the Option is to release the Bus after transmission of data
		 * and return the number of bytes that was received. Only wait
		 * if master, if addressed as slave just reset to release
		 * the bus. 
		 */
		if ((ControlReg & XIIC_CR_MSMS_MASK) != 0)
		{
			XIic_WriteReg(BaseAddress,  XIIC_CR_REG_OFFSET, (ControlReg & ~XIIC_CR_MSMS_MASK));
		}

		if ((XIic_ReadReg(BaseAddress, XIIC_SR_REG_OFFSET) &
		    XIIC_SR_ADDR_AS_SLAVE_MASK) != 0)
		{
			XIic_WriteReg(BaseAddress,  XIIC_CR_REG_OFFSET, 0);
		}
		else
		{
			StatusReg = XIic_ReadReg(BaseAddress,
					XIIC_SR_REG_OFFSET);
			while ((StatusReg & XIIC_SR_BUS_BUSY_MASK) != 0)
			{
				StatusReg = XIic_ReadReg(BaseAddress,
						XIIC_SR_REG_OFFSET);
			}
		}
	}

	return ByteCount - RemainingByteCount;
}



#define VCODEC7BITADDR 0x1A						// addr of codec device on I2C bus
#define VIICIPCOREADDR 0x14000					// AXILite address for core
//
// write to a Codec register. Based on Xlic_Send but stripped down.
// Send data as a master on the IIC bus.  This function sends the data
// using polled I/O and blocks until the data has been sent. It only supports
// 7 bit addressing mode of operation.  This function returns zero if bus is busy.
//
// returns the number of bytes sent.
//
uint32_t WriteCodecRegister(uint16_t CodecData)
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






/////////////////////////////////////////////////////////////////////////////////////////////////
//
// main program
//
// either call: ./codecwrite    (sends all regs)
// or call: ./codecwrite 3C57 (write ox57 to register 0x3C)
//
//
int main(int argc, char *argv[])
{
	uint32_t RegisterValue;
	uint32_t ByteCount;
	uint16_t CodecReg;

	//
	// try to open memory device
	//
	if ((register_fd = open("/dev/xdma0_user", O_RDWR)) == -1)
	{
		printf("register R/W address space not available\n");
		goto out;
	}
	else
	{
		printf("register access connected to /dev/xdma0_user\n");
	}

	//
	// now read the user access register (it should have a date code)
	//
	RegisterValue = RegisterRead(0x4004);				// read the user access register
	printf("User register = %08x\n", RegisterValue);

//
// now write all reset registers, or one specificed register
//
	if(argc==2)					// just one reg from command line
	{
		CodecReg = strtol(argv[1], NULL, 16);
		ByteCount = WriteCodecRegister(CodecReg);
		printf("send %4X; transferred %d bytes\n", CodecReg, ByteCount);
	}
	else
	{
		ByteCount = WriteCodecRegister(0x1E00);
		printf("send 0x1E00; transferred %d bytes\n", ByteCount);

		ByteCount = WriteCodecRegister(0x1201);
		printf("send 0x1201; transferred %d bytes\n", ByteCount);

		ByteCount = WriteCodecRegister(0x0814);
		printf("send 0x0814; transferred %d bytes\n", ByteCount);

		ByteCount = WriteCodecRegister(0x0C00);
		printf("send 0x0C00; transferred %d bytes\n", ByteCount);

		ByteCount = WriteCodecRegister(0x0E02);
		printf("send 0x0E02; transferred %d bytes\n", ByteCount);

		ByteCount = WriteCodecRegister(0x1000);
		printf("send 0x1000; transferred %d bytes\n", ByteCount);

		ByteCount = WriteCodecRegister(0x0A00);
		printf("send 0x0A00; transferred %d bytes\n", ByteCount);

		ByteCount = WriteCodecRegister(0x0000);
		printf("send 0x0000; transferred %d bytes\n", ByteCount);
	}



	//
	// close down. Deallocate memory and close files
	//
out:
	close(register_fd);
}

