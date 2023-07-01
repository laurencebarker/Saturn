//
// main file for SPI flash writer GUI app
// flash write created from command line code; GUI created with GTK3
//
#include <gtk/gtk.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

#include <getopt.h>
#include <cstdlib>
#include <sys/stat.h>
#include <unistd.h>

#include "spi-s25fl.hpp"                // class to access S25FL256x devices

//
// global variables: for GUI:
//
GtkBuilder      *Builder; 
GtkWidget       *Window;
GtkTextBuffer   *TextBuffer;
GtkStatusbar      *StatusBar;
GtkLabel *LblStage;
GtkLabel *LblFilename;
GtkProgressBar *ProgressBar;
GtkToggleButton *RbPrimary;
GtkToggleButton *RbFallback;
GtkWidget       *DlgFileChoose;
    

//
// mem read/write variables:
//
int fd;                             // device identifier
gboolean DriverPresent;             // true if device driver is accessible
gboolean FileNameSet;               // true if filename has been set by "file open"
gboolean PrimaryImage;              // set true if primary image to be written

#define VFALLBACKADDR 0x00000000    // start of flash Flash
#define VPRIMARYADDR  0x00980000    // at end of 1st image + timer barrier
#define VDEVICESIZE 0x02000000      // 32MByte
//
// SPI writer constron structure:
//
XSpi_Config cfg;
uint32_t FlashStartAddress; 


//
// global needed to re-use Xilinx code
// pathname for the PCIe device driver axi-lite bus access device
//
const char* gAXI_FNAME = "/dev/xdma/card0/user";


//
// Load a raw binary file into memory for programming 
//   aOffset: offset into the file to start loading 
//   alen: Number of bytes to load (0=read all) 
//   return Raw data to program
//
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
            throw std::runtime_error("File offset index exceeds file size");

        // OK seek to desired offset.
        fseek(fp, aOffset, SEEK_SET);

        // Compute the number of bytes to program
        if (0 == aLen)
            aLen = fsize - aOffset;         // Whole file

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






//////////////////////////////////////////////////////////////////////////////////////
// GUI event handlers


//
// callback from flash writing class. Set the progress bar accordingly.
//
static void MyStatusCallback(const pgm_status_s& stat)
{
    gtk_progress_bar_set_fraction(ProgressBar, stat.pcnt_cmplt);
    // update the window
    while(gtk_events_pending())
        gtk_main_iteration();
}


// called when "erase device" button is clicked
void on_erase_button_clicked()
{
    gchar TempString[100];
    uint32_t StartAddress;
    uint32_t EraseSize;

    if(DriverPresent)
    {
        cfg.BaseAddress = 0x10000;                // Base address of the SPI IP
        cfg.HasFifos = 1;                         // Does device have FIFOs?
        cfg.SlaveOnly = 0;                        // Is the device slave only?
        cfg.NumSlaveBits = 1;                     // Num of slave select bits on the device
        cfg.DataWidth = XSP_DATAWIDTH_BYTE;       // Data transfer Width. 0=byte
        cfg.SpiMode = XSP_QUAD_MODE;              // Standard/Dual/Quad mode
        cfg.AxiFullBaseAddress = 0x10000;         // AXI Full Interface Base address of the SPI IP (unused?)
        cfg.XipMode = 0;                          // 0 if Non-XIP, 1 if XIP Mode
        cfg.Use_Startup = 1;                      // 1 if Startup block is used in h/w
        cfg.dev_fname = gAXI_FNAME;               // Default to XDMA driver, first device

      // Unused properties
        cfg.AxiInterface = 0;             // AXI-Lite/AXI Full Interface
        cfg.DeviceId = 0;                 // Unique ID  of device

        StartAddress = 0x0;
        EraseSize = VDEVICESIZE;                   // 32MByte

        gtk_text_buffer_insert_at_cursor(TextBuffer, "Erase Whole device:\n", -1);
        // update the window
        while(gtk_events_pending())
            gtk_main_iteration();
        // begin programming operation
        try
        {
            // Instantiate flash programming class
            SPI_S25FL_c fifc;
            fifc.RegisterStatusCallback(MyStatusCallback);

            // Init
            gtk_text_buffer_insert_at_cursor(TextBuffer, "Initialising:\n", -1);
            gtk_label_set_label(LblStage, "Initialise");
            // update the window
            while(gtk_events_pending())
                gtk_main_iteration();
            fifc.Init(cfg);

            // Mark erase/program start
            const auto elap_start = std::chrono::steady_clock::now();

            // Erase
            gtk_text_buffer_insert_at_cursor(TextBuffer, "Erasing: ", -1);
            gtk_label_set_label(LblStage, "Erase");
            // update the window
            while(gtk_events_pending())
                gtk_main_iteration();
            auto start = std::chrono::steady_clock::now();
            fifc.EraseRange(StartAddress, EraseSize);
            std::chrono::duration<double> dt = std::chrono::steady_clock::now() - start;
            sprintf(TempString, "complete in %.3fs...\n", dt.count());
            gtk_text_buffer_insert_at_cursor(TextBuffer, TempString, -1);
            gtk_label_set_label(LblStage, "Complete");
        }
        catch (const std::exception& ex)
        {
            sprintf(TempString, "\nException occurred: %s\n", ex.what());
            gtk_text_buffer_insert_at_cursor(TextBuffer, TempString, -1);
        }
    }
}



// called when "open file" button is clicked
void on_file_button_clicked()
{
    gchar *FileName = NULL;                     // filename from dialog
    gboolean Success = FALSE;

    gtk_widget_show(DlgFileChoose);                     // show the file chooser dialog
//
// now wait till it closes, and get the filename
//
    if(gtk_dialog_run(GTK_DIALOG(DlgFileChoose)) == GTK_RESPONSE_OK)
    {
        FileName = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(DlgFileChoose));
        if(FileName!= NULL)
            Success = TRUE;
        if(Success == TRUE)
        {
            gtk_text_buffer_insert_at_cursor(TextBuffer, "open succeeded\n", -1);
            gtk_label_set_label(LblFilename, FileName);
        }

    }
    else
        gtk_text_buffer_insert_at_cursor(TextBuffer, "open cancelled\n", -1);

    gtk_widget_hide(DlgFileChoose);
    FileNameSet = Success;
}
  
//
// called when program button is clicked
//
void on_program_button_clicked()
{
    gchar TempString[100];

    if(gtk_toggle_button_get_active(RbPrimary))
    {
        PrimaryImage = TRUE;
        FlashStartAddress = VPRIMARYADDR;
    }
    else
    {
        PrimaryImage = FALSE; 
        FlashStartAddress = VFALLBACKADDR;
    }

//
// if we have a device driver and filename, commence programming operations.
// unsure if this can be int he same thread though.
//
    if(DriverPresent && FileNameSet)
    {
        cfg.BaseAddress = 0x10000;                // Base address of the SPI IP
        cfg.HasFifos = 1;                         // Does device have FIFOs?
        cfg.SlaveOnly = 0;                        // Is the device slave only?
        cfg.NumSlaveBits = 1;                     // Num of slave select bits on the device
        cfg.DataWidth = XSP_DATAWIDTH_BYTE;       // Data transfer Width. 0=byte
        cfg.SpiMode = XSP_QUAD_MODE;              // Standard/Dual/Quad mode
        cfg.AxiFullBaseAddress = 0x10000;         // AXI Full Interface Base address of the SPI IP (unused?)
        cfg.XipMode = 0;                          // 0 if Non-XIP, 1 if XIP Mode
        cfg.Use_Startup = 1;                      // 1 if Startup block is used in h/w
        cfg.dev_fname = gAXI_FNAME;               // Default to XDMA driver, first device

      // Unused properties
        cfg.AxiInterface = 0;             // AXI-Lite/AXI Full Interface
        cfg.DeviceId = 0;                 // Unique ID  of device
//
// read and check binary file
//
      // Load file and make sure not empty
        std::vector<uint8_t> data_to_write;
        data_to_write = LoadBin(gtk_label_get_label(LblFilename), 0, 0);
        if (data_to_write.empty())
            gtk_text_buffer_insert_at_cursor(TextBuffer, "file is empty\n", -1);
        else
        {
            sprintf(TempString, "programming %d bytes at address 0x%08x\n", data_to_write.size(), FlashStartAddress);
            gtk_text_buffer_insert_at_cursor(TextBuffer, TempString, -1);
            // update the window
            while(gtk_events_pending())
                gtk_main_iteration();
            // begin programming operation
            try
            {
                // Instantiate flash programming class
                SPI_S25FL_c fifc;
                fifc.RegisterStatusCallback(MyStatusCallback);

                // Init
                gtk_text_buffer_insert_at_cursor(TextBuffer, "Initialising:\n", -1);
                gtk_label_set_label(LblStage, "Initialise");
               // update the window
                while(gtk_events_pending())
                    gtk_main_iteration();
                fifc.Init(cfg);

                // Mark erase/program start
                const auto elap_start = std::chrono::steady_clock::now();

                // Erase
                gtk_text_buffer_insert_at_cursor(TextBuffer, "Erasing: ", -1);
                gtk_label_set_label(LblStage, "Erase");
               // update the window
                while(gtk_events_pending())
                    gtk_main_iteration();
                auto start = std::chrono::steady_clock::now();
                fifc.EraseRange(FlashStartAddress, data_to_write.size());
                std::chrono::duration<double> dt = std::chrono::steady_clock::now() - start;
                sprintf(TempString, "complete in %.3fs...\n", dt.count());
                gtk_text_buffer_insert_at_cursor(TextBuffer, TempString, -1);

                // Program
                gtk_text_buffer_insert_at_cursor(TextBuffer, "Programming: ", -1);
                gtk_label_set_label(LblStage, "Program");
               // update the window
                while(gtk_events_pending())
                    gtk_main_iteration();
                start = std::chrono::steady_clock::now();
                fifc.Write(FlashStartAddress, data_to_write.data(), data_to_write.size());
                dt = std::chrono::steady_clock::now() - start;
                sprintf(TempString, "complete in %.3fs...\n", dt.count());
                gtk_text_buffer_insert_at_cursor(TextBuffer, TempString, -1);

                gtk_text_buffer_insert_at_cursor(TextBuffer, "Verifying: ", -1);
                gtk_label_set_label(LblStage, "Verify");
                               // update the window
                while(gtk_events_pending())
                    gtk_main_iteration();

                start = std::chrono::steady_clock::now();
                // Read section into vector
                std::vector<uint8_t> tmp(data_to_write.size());
                fifc.Read(FlashStartAddress, tmp.data(), tmp.size());
                dt = std::chrono::steady_clock::now() - start;
                sprintf(TempString, "read complete in %.3fs...\n", dt.count());
                gtk_text_buffer_insert_at_cursor(TextBuffer, TempString, -1);

                // Check and report
                if (tmp != data_to_write)
                    gtk_text_buffer_insert_at_cursor(TextBuffer, "Verify FAIL\n", -1);
                else
                    gtk_text_buffer_insert_at_cursor(TextBuffer, "Verify Successful\n", -1);
                gtk_label_set_label(LblStage, "Complete");
            }
            catch (const std::exception& ex)
            {
                sprintf(TempString, "\nException occurred: %s\n", ex.what());
                gtk_text_buffer_insert_at_cursor(TextBuffer, TempString, -1);
            }
        }
    }
}




// called when window is closed
void on_window_main_destroy()
{
    gtk_main_quit();
}


// called when window is closed
void on_close_button_clicked()
{
    gtk_main_quit();
} 



//
// "main" essentially creates the window and attaches event handlers
//
int main(int argc, char *argv[])
{
    guint Context;                                  // status bar context

    gtk_init(&argc, &argv);
    PrimaryImage = FALSE;
    FileNameSet = FALSE;

    // Update October 2019: The line below replaces the 2 lines above
    Builder = gtk_builder_new_from_file("flashwriter.ui");

    Window = GTK_WIDGET(gtk_builder_get_object(Builder, "window_main"));
    DlgFileChoose = GTK_WIDGET(gtk_builder_get_object(Builder, "dlg_file_choose"));
    StatusBar = GTK_STATUSBAR(gtk_builder_get_object(Builder, "statusbar_main"));
    TextBuffer = GTK_TEXT_BUFFER(gtk_builder_get_object(Builder, "textbuffer_main"));
    LblStage = GTK_LABEL(gtk_builder_get_object(Builder, "lbl_stage"));
    LblFilename = GTK_LABEL(gtk_builder_get_object(Builder, "lbl_filename"));
    ProgressBar = GTK_PROGRESS_BAR(gtk_builder_get_object(Builder, "id_progress"));
    RbPrimary = GTK_TOGGLE_BUTTON(gtk_builder_get_object(Builder, "rb_1"));
    RbFallback = GTK_TOGGLE_BUTTON(gtk_builder_get_object(Builder, "rb_2"));

    gtk_builder_add_callback_symbol (Builder, "OnEraseButtonClicked", G_CALLBACK (on_erase_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_program_button_clicked", G_CALLBACK (on_program_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_file_button_clicked", G_CALLBACK (on_file_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_window_main_destroy", G_CALLBACK (on_window_main_destroy));
    gtk_builder_add_callback_symbol (Builder, "on_close_button_clicked", G_CALLBACK (on_close_button_clicked));
    gtk_builder_connect_signals(Builder, NULL);

    g_object_unref(Builder);
    gtk_widget_show(Window);                
    Context = gtk_statusbar_get_context_id(StatusBar, "context");
//
// try to open PCIe device temporarily
//
	if ((fd = open("/dev/xdma0_user", O_RDWR)) == -1)
    {
        gtk_statusbar_push(StatusBar, Context, "No PCIe Driver");
        DriverPresent = FALSE;
    }
    else
    {
        gtk_statusbar_push(StatusBar, Context, "Connected to /dev/xdma0_user");    
        DriverPresent = TRUE;
       	close(fd);
    }

    gtk_main();

    return 0;
}

