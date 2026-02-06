//******************************************************************************
// Main program for Saturnloader
//******************************************************************************

// Includes
#include "spi-s25fl.hpp"

#include <getopt.h>
#include <cstdlib>
#include <sys/stat.h>
#include <unistd.h>

// This is ugly, but a side effect of reusing Xilinx code
// We need another parameter to do I/O via XDMA, namely, the dev file to perform I/O on
// gAXI_FNAME is a global.
const char* gAXI_FNAME = "/dev/xdma/card0/user";


/**
 * @brief Parse 2 character literal as hex byte
 * @return The byte
 */
static unsigned char readHexByte(char *data)
{
   int val = 0;
   if (data[0] >= '0' && data[0] <= '9'){val = (val + (data[0] - '0')) << 4;}
   else if (data[0] >= 'a' && data[0] <= 'f'){val = (val + ((data[0] - 'a') + 10)) << 4;}
   else if (data[0] >= 'A' && data[0] <= 'F'){val = (val + ((data[0] - 'A') + 10)) << 4;}
   else{throw std::runtime_error("Invalid character in file");}

   if (data[1] >= '0' && data[1] <= '9'){val = val + (data[1] - '0');}
   else if (data[1] >= 'a' && data[1] <= 'f'){val = val + ((data[1] - 'a') + 10);}
   else if (data[1] >= 'A' && data[1] <= 'F'){val = val + ((data[1] - 'A') + 10);}
   else{throw std::runtime_error("Invalid character in file");}

   return val;
}



/**
 * @brief Load a raw binary file into memory for programming 
 * @param aOffset: offset into the file to start loading 
 * @param alen: Number of bytes to load (0=read all) 
 * @return Raw data to program
 */
static std::vector<uint8_t> LoadBin(const char* fname, long int aOffset, long int aLen)
{
   // Load file data into a vector
   std::vector<uint8_t> rez(aLen);
   FILE* fp = fopen(fname, "rb");
   if (fp)
   {
      // obtain file size
      fseek (fp, 0, SEEK_END);
      const auto fsize = ftell(fp);

      // Seek to the desired offset
      if (aOffset >= fsize)
      {
         throw std::runtime_error("File offset index exceeds file size");
      }

      // OK seek to desired offset.
      fseek(fp, aOffset, SEEK_SET);

      // Compute the number of bytes to program
      if (0 == aLen)
      {
         // Whole file
         aLen = fsize - aOffset;
      }

      // Read into rez
      rez.resize(aLen);
      const size_t num_read = fread(rez.data(), 1, aLen, fp);
      rez.resize(num_read);

      // Done
      fclose(fp);
   }
   else
   {
      char msg[256];
      snprintf(msg, sizeof(msg), "Failed to open %s:%s\n", fname, strerror(errno));
      throw std::runtime_error(std::string(msg));
   }

   return rez;

}



/**
 * @brief Verify the existance of a file 
 * 
 * @param fname: The file to check 
 * @param perm: Permissions to check for; a bitmask of the following: 
 *   R_OK  readable                             
 *   W_OK  writable                             
 *   X_OK  executable                           
 *   F_OK  exists                               
 * 
 * @return bool T if file exists with specified permissions, F otherwise
 */
static bool FileCheck(const char* fname, int perm = R_OK)
{
    return ( access(fname, perm ) != -1 );
}

/**
 * @brief Print command line args and usage 
 */
static void PrintUsage(void)
{
   printf("\nsaturn FPGA loader V1.3 based on code copyright 2019 RHS Research LLC"
	      "\nUsage: load-FPGA [-b binary file] [-f] [-v]"
          "\n Programming specification options"
          "\n   -b: Data file to load (raw binary)"
          "\n   -v: Verify after programming"
          "\n   -f: program fallback image\n"
          );
}

/**
 * @brief This function gets called by the SPI programming library when status changes 
 * 
 * @param stat: New status being reported by the library 
 */
static void MyStatusCallback(const pgm_status_s& stat)
{
   printf("\r(%.1f%%):%-60s", stat.pcnt_cmplt * 100.0, stat.msg.c_str());
}

/** 
 * MAIN 
 */
int main(int argc, char* argv[])
{
   try
   {
      // Since our erase/program reports don't have a newline, we disable stdout buffering
      // to achieve the desired effect
      setbuf(stdout, NULL);

      // Default SPI settings
      XSpi_Config cfg;
      cfg.BaseAddress = 0x10000;                /**< Base address of the device */
      cfg.HasFifos = 1;                         /**< Does device have FIFOs? */
      cfg.SlaveOnly = 0;                        /**< Is the device slave only? */
      cfg.NumSlaveBits = 1;                     /**< Num of slave select bits on the device */
      cfg.DataWidth = XSP_DATAWIDTH_BYTE;       /**< Data transfer Width. 0=byte */
      cfg.SpiMode = XSP_QUAD_MODE;              /**< Standard/Dual/Quad mode */
      cfg.AxiFullBaseAddress = 0x10000;         /**< AXI Full Interface Base address of the device */
      cfg.XipMode = 0;                          /**< 0 if Non-XIP, 1 if XIP Mode */
      cfg.Use_Startup = 1;                      /**< 1 if Starup block is used in h/w */
      cfg.dev_fname = "/dev/xdma/card0/user";  // Default to XDMA driver, first device

      // Unused properties
      cfg.AxiInterface = 0;             /**< AXI-Lite/AXI Full Interface */
      cfg.DeviceId = 0;                 /**< Unique ID  of device */

      // Storage for arguments
      char* dataFileBIN = NULL;
      long int byteLen = 0;
      long int srcInx = 0;
      long int dstInx = 0x00980000;             // load primary image at this location
      bool verify = false;
      bool fallback = false;

      // Process command line args
      int option;
      while ((option = getopt(argc, argv, "b:vf")) != -1)
      {
         switch (option)
         {
            case 'b':
               dataFileBIN = optarg;
               break;

            case 'v':
               verify = true;
               break;

            case 'f':
               fallback = true;
               break;

         default:
            break;
         }
      }

      if(fallback == true)                         // fallback image at start of flash
         dstInx = 0;



      // Make sure the user specified a data file to load into flash
      if (!dataFileBIN)
      {
         PrintUsage();
         return 1;
// << early exit
      }


      // Make sure the device file to access the AXI-SPI block exists
      if (!FileCheck(cfg.dev_fname, R_OK | W_OK))
      {
         printf("Device file not found:%s. Is the XDMA driver installed and working?\n", cfg.dev_fname);
         return 1; 
// << early exit
      }

      // Load file
      std::vector<uint8_t> data_to_write;
      data_to_write = LoadBin(dataFileBIN, srcInx, byteLen);

      // Make sure we have at least one byte to write
      if (data_to_write.empty())
      {
         printf("Binary data file empty- no data to write\n");
         return 1; 
// << early exit
      }

      // At this point, we have a device and some data to write to it.
      // Reveal final plans to the user
      printf("Loading %ld bytes from %s[%ld] to flash[%ld] using %s[%ld]\n"
             , data_to_write.size()
             , dataFileBIN
             , srcInx
             , dstInx
             , cfg.dev_fname
             , cfg.BaseAddress
            );

      // This is ugly, but a side effect of reusing Xilinx code
      // We need another parameter to do I/O via XDMA, namely, the dev file to perform I/O on
      // gAXI_FNAME is a global.
      // Assign the user-specified device filename to the global
      gAXI_FNAME = cfg.dev_fname;

      // Instantiate flash programming class
      SPI_S25FL_c fifc;
      fifc.RegisterStatusCallback(MyStatusCallback);

      // Init
      printf("\nInitializing...\n");
      fifc.Init(cfg);

      // Mark erase/program start
      const auto elap_start = std::chrono::steady_clock::now();

      // Erase
      printf("\nErasing...\n");
      auto start = std::chrono::steady_clock::now();
      fifc.EraseRange(dstInx, data_to_write.size());
      std::chrono::duration<double> dt = std::chrono::steady_clock::now() - start;
      printf("\nErased in %.3fs...\n", dt.count());

      // Program
      printf("\nProgramming...\n");
      start = std::chrono::steady_clock::now();
      fifc.Write(dstInx, data_to_write.data(), data_to_write.size());
      dt = std::chrono::steady_clock::now() - start;
      printf("\nProgrammed in %.3fs...\n", dt.count());

      // Report erase/program time
      dt = std::chrono::steady_clock::now() - elap_start;
      printf("\nErase/Program took %.3fs (%.0fKiB/s)\n", dt.count(), ((static_cast<double>(data_to_write.size()) / dt.count())) / 1024.0);

      // Verify
      if (verify)
      {
         printf("\nVerifying...\n");
         start = std::chrono::steady_clock::now();

         // Read section into vector
         std::vector<uint8_t> tmp(data_to_write.size());
         fifc.Read(dstInx, tmp.data(), tmp.size());

         dt = std::chrono::steady_clock::now() - start;
         printf("\nRead in %.3fs...\n", dt.count());

         // Check and report
         if (tmp != data_to_write)
         {
            printf("\nVerify failed\n");
            return 1; 
   // << early exit
         }
         else
         {
            printf("\nVerify OK\n");
         }
      }
   }
   catch (const std::exception& ex)
   {
      printf("\nException occurred: %s\n", ex.what());

      return 1;
   }

   return 0;
}



