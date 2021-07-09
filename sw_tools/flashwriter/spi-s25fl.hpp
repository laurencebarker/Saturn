//-----------------------------------------------------------------------------
// Name: spi-s25fl.hpp
// Description: Header file for module to implement spansion S25FL flash routines
//-----------------------------------------------------------------------------
#pragma once

#include "xspi.h"

#include <cstring>
#include <functional>
#include <mutex>
#include <sstream>
#include <vector>

//-------------------------------------------------------------------------------------//
// Typedefs- should be common to all flash parts
//-------------------------------------------------------------------------------------//

struct pgm_status_s
{
   std::string msg;
   double pcnt_cmplt = std::numeric_limits<double>::quiet_NaN();
};

typedef std::function<void(const pgm_status_s& stat)> status_callback_t;

class SPI_S25FL_c
{

public:

   ~SPI_S25FL_c();

/**
 * @brief Initialize this object with hardware-specific settings
 * 
 * @param cfg: The configuration structure that describes the hardware 
 */
   void Init(const XSpi_Config& cfg);

/**
 * @brief Register a callback function for flash status updates 
 * 
 * @param cb: The callback function to register 
 */
   void RegisterStatusCallback(const status_callback_t& cb);


/**
 * @brief Erase a section of the flash. 
 *  
 * @note: Flash naturally erases on sector boundaries; this function doesn't attempt to 
 * preserve data in a sector that isn't fully covered by addr, len 
 * 
 * @param addr: The Address to start erasing (will erase the entire sector containing this address) 
 * @param len: The desired number of bytes to erase. 
 */
   void EraseRange(uint32_t addr, size_t len);

/**
 * @brief Write to flash 
 * 
 * @param flash_addr: First address to start writing to 
 * @param src: Pointer to source data 
 * @param len: Number of bytes to write 
 */
   void Write(uint32_t flash_addr, const uint8_t* src, const size_t len);


/**
 * @brief Read data from flash into buffer
 * 
 * @param flash_addr: Flash address to read from 
 * @param dst: Buffer to place data from flash into 
 * @param len: Number of bytes to read 
 */
   void Read(uint32_t flash_addr, uint8_t* dst, const size_t len);



private:

   //-------------------------------------------------------------------------------------//
   // Private functions
   //-------------------------------------------------------------------------------------//


//--------------------------------------------------------------------------------
// GetStatusRegister
// Reads status register and returns it
//--------------------------------------------------------------------------------
   uint8_t GetStatusRegister(void);


//--------------------------------------------------------------------------------
// ClearStatusRegister
// Clears volatile/error bits in the status register
//--------------------------------------------------------------------------------
   void ClearStatusRegister(void);



//--------------------------------------------------------------------------------
// WaitForFlashNotBusy
// Waits up to wait_s seconds for flash to indicate it is done with the previous operation
//--------------------------------------------------------------------------------
   void WaitForFlashNotBusy(double wait_s);


//--------------------------------------------------------------------------------
// StartCommand
// Initialize the system in prep for sending a flash command
//--------------------------------------------------------------------------------
   void StartCommand(uint8_t cmd);

   void AddAddr(uint32_t addr);


//--------------------------------------------------------------------------------
// AddFromBuffer
// Add len bytes from buf into transmit buffer to send to flash
//--------------------------------------------------------------------------------
   void AddFromBuffer(const uint8_t* buf, size_t len);

   // Executes the command. Returns a pointer to read data.
   uint8_t* Execute(size_t num2read, double timeout_s = FLASH_DEFAULT_CMD_TIMEOUT_S);


//--------------------------------------------------------------------------------
// WriteEnable
// Spansion flash requires this to be sent before writing/erasing
//--------------------------------------------------------------------------------
   void WriteEnable(void);


//--------------------------------------------------------------------------------
// SectorErase
// Erases the sector that contans address addr
//--------------------------------------------------------------------------------
   void SectorErase(u32 addr);


//--------------------------------------------------------------------------------
// SayStatus
// Report status to any registered callback functions
//--------------------------------------------------------------------------------
   void SayStatus(const std::string& msg, double pcnt_cplt = std::numeric_limits<double>::quiet_NaN());

   //-------------------------------------------------------------------------------------//
   // Private data
   //-------------------------------------------------------------------------------------//

   //-------------------------------------------------------------------------------------//
   // Details of this flash

   // Settings
   static constexpr double FLASH_ERASE_TIMEOUT_S = 10.0; 
   static constexpr double FLASH_DEFAULT_CMD_TIMEOUT_S = 10.0;
   static constexpr size_t FLASH_ENFORCED_SECTOR_BYTES = 256 * 1024; // Some parts have 256K pages. 
                                                                     // Since we don't check the part type, we must enforce the largest size

   // Sizes
   static constexpr size_t FLASH_PAGE_BYTES = 256;
   static constexpr size_t FLASH_MAX_CMD_BYTES = 5;
   static constexpr size_t FLASH_SECTOR_BYTES = 64 * 1024;        // Not true for S25FL128xxxxxx1 devices, which have 256K

   // Commands. Note: All commands must use 4 byte addressing
   static constexpr uint8_t CMD_RANDOM_READ       = 0x13;
   static constexpr uint8_t CMD_PAGEPROGRAM_WRITE = 0x12;
   static constexpr uint8_t CMD_WRITE_ENABLE	  = 0x06;
   static constexpr uint8_t CMD_SECTOR_ERASE	  = 0xDC;
   static constexpr uint8_t CMD_STATUSREG_READ    = 0x05;
   static constexpr uint8_t CMD_STATUSREG_WRITE   = 0x01;
   static constexpr uint8_t CMD_STATUSREG_CLEAR   = 0x30;

   // Register defs
   static constexpr uint8_t SR_IS_READY_MASK = 0x01; // D0 is 1 when busy
   static constexpr uint8_t SR_E_ERR_MASK = 0x20;       // D5 is 1 if erase error
   static constexpr uint8_t SR_P_ERR_MASK = 0x40;       // D6 is 1 if program error
   static constexpr uint8_t SR_ANY_ERR_MASK = (SR_P_ERR_MASK | SR_E_ERR_MASK);  // Any error
   //-------------------------------------------------------------------------------------//


   // Mutex to make the API thread safe. Must be locked by any public functions
   std::recursive_mutex mMutex;

   // Registered callback functions
   std::vector<status_callback_t> mCallBacks;

   // Xilinx-like SPI access classes
   XSpi_Config mCfg;
   XSpi        mSPI;

   // Buffers for interaction with Xilinx library
   static constexpr size_t TOTAL_BUFFER_SIZE = FLASH_MAX_CMD_BYTES + FLASH_PAGE_BYTES;
   uint8_t mWriteBuf[TOTAL_BUFFER_SIZE];
   uint8_t mReadBuf[TOTAL_BUFFER_SIZE];
   size_t mCurrWriteBufInx = 0;

};




