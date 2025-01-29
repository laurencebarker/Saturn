//
// main file for audio test GUI app
// GUI created with GTK3
//

//
// this value may need to be edited depending on the current sensing circuit
//
//#define PACURRENTSCALE 0.00996F                         // for ACS713-20
#define PACURRENTSCALE 0.01844F                         // for TMCS1100A2



#include <gtk/gtk.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <getopt.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <math.h>
#include <semaphore.h>
#include <pthread.h>


#include "../common/saturntypes.h"
#include "../common/hwaccess.h"                     // access to PCIe read & write
#include "../common/saturnregisters.h"              // register I/O for Saturn
#include "../common/saturndrivers.h"              	// register I/O for Saturn
#include "../common/codecwrite.h"                   // codec register I/O for Saturn
#include "../common/version.h"                      // version I/O for Saturn
#include "../common/debugaids.h"


//
// global variables: for GUI:
//
GtkBuilder      *Builder; 
GtkWidget       *Window;
GtkTextBuffer   *TextBuffer;
GtkStatusbar      *StatusBar;
GtkToggleButton *TXCheck;
GtkEntry *DriverCurrentText;
GtkEntry *PACurrentText;
//
// mem read/write variables:
//
int fd;                             // device identifier
gboolean DriverPresent;             // true if device driver is accessible
pthread_t CurrentReadThread;        // thread looks for PTT press
gboolean GPTTPressed;               // true if in TX
#define VALIGNMENT 4096





extern sem_t DDCInSelMutex;                 // protect access to shared DDC input select register
extern sem_t DDCResetFIFOMutex;             // protect access to FIFO reset register
extern sem_t RFGPIOMutex;                   // protect access to RF GPIO register
extern sem_t CodecRegMutex;                 // protect writes to codec



//
// global needed to re-use Xilinx code
// pathname for the PCIe device driver axi-lite bus access device
//
const char* gAXI_FNAME = "/dev/xdma0_user";


///
// callback from saturn register code
// not really needed!
//
void HandlerSetEERMode(bool Unused)
{

}



//
// called when TX button is clicked
//
void on_TXButton_toggled()
{
//    GPTTPressed = gtk_check_button_get_active(TXCheck);
    GPTTPressed = gtk_toggle_button_get_active(TXCheck);
    if (GPTTPressed)
        gtk_text_buffer_insert_at_cursor(TextBuffer, "TX Enabled...  ", -1);
    else
        gtk_text_buffer_insert_at_cursor(TextBuffer, "TX Disabled\n", -1);
    SetMOX(GPTTPressed);
}


// called when window is closed
void on_window_main_destroy()
{
    gtk_main_quit();
	sem_destroy(&DDCInSelMutex);
	sem_destroy(&DDCResetFIFOMutex);
	sem_destroy(&RFGPIOMutex);
	sem_destroy(&CodecRegMutex);
	SetMOX(false);
	SetTXEnable(false);
}


// called when window is closed
void on_close_button_clicked()
{
    SetMOX(false);
    SetTXEnable(false);
    gtk_main_quit();
} 





// this runs as its own thread to read PA and bias currents periodically
// thread initiated at the start.
// done in a thread so GUI event handlers not hung
//
void* CurrentRead(void *arg)
{
	gint Duration;					// record and replay duration in seconds
	uint32_t PAReading, DriverReading;
    float PACurrent, DriverCurrent;
    char DisplayedValue [100];

	while (1)
	{
		usleep(100000);												// 100ms wait
		if(GPTTPressed)
		{
            DriverReading = GetAnalogueIn(6);               // current = ADC reading /1638.4
            PAReading = GetAnalogueIn(3);                   // current = ADC reading * 0.01387
            DriverCurrent = (float)DriverReading / 1638.4F;
            PACurrent = (float)PAReading * PACURRENTSCALE;
            sprintf(DisplayedValue, "%6.3f", DriverCurrent);
            gtk_entry_set_text(DriverCurrentText, DisplayedValue);
            sprintf(DisplayedValue, "%6.2f", PACurrent);
            gtk_entry_set_text(PACurrentText, DisplayedValue);
		}
	}
}



//
// "main" essentially creates the window and attaches event handlers
//
int main(int argc, char *argv[])
{
    guint Context;                                  // status bar context

    gtk_init(&argc, &argv);

    // Update October 2019: The line below replaces the 2 lines above
    Builder = gtk_builder_new_from_file("biascheck.ui");

    Window = GTK_WIDGET(gtk_builder_get_object(Builder, "window_main"));
    StatusBar = GTK_STATUSBAR(gtk_builder_get_object(Builder, "statusbar_main"));
    TextBuffer = GTK_TEXT_BUFFER(gtk_builder_get_object(Builder, "textbuffer_main"));
    TXCheck = GTK_TOGGLE_BUTTON(gtk_builder_get_object(Builder, "TXButton"));
	DriverCurrentText = GTK_ENTRY(gtk_builder_get_object(Builder, "DriverCurrentBox"));
	PACurrentText = GTK_ENTRY(gtk_builder_get_object(Builder, "PACurrentBox"));

    gtk_builder_add_callback_symbol (Builder, "on_TXButton_Toggled", G_CALLBACK (on_TXButton_toggled));
    gtk_builder_add_callback_symbol (Builder, "on_window_main_destroy", G_CALLBACK (on_window_main_destroy));
    gtk_builder_add_callback_symbol (Builder, "on_close_button_clicked", G_CALLBACK (on_close_button_clicked));
    
    gtk_builder_connect_signals(Builder, NULL);

    g_object_unref(Builder);
    gtk_widget_show(Window);                
    Context = gtk_statusbar_get_context_id(StatusBar, "context");
  //
  // initialise register access semaphores
  //
  	sem_init(&DDCInSelMutex, 0, 1);                                   // for DDC input select register
  	sem_init(&DDCResetFIFOMutex, 0, 1);                               // for FIFO reset register
  	sem_init(&RFGPIOMutex, 0, 1);                                     // for RF GPIO register
  	sem_init(&CodecRegMutex, 0, 1);                                   // for codec writes

	OpenXDMADriver();
	PrintVersionInfo();
	CodecInitialise();
	SetByteSwapping(false);                                            // h/w to generate normalbyte order
	SetSpkrMute(false);
    SetTXDriveLevel(0);                                                 // DAC current & Atten value
    SetTXAmplitudeScaling(0);                                           // DUC ampl scale value
    SetTXEnable(true);

//
// now start current reading thread
//
	if(pthread_create(&CurrentReadThread, NULL, CurrentRead, NULL) < 0)
	{
	    perror("pthread_create check for current read");
	    return EXIT_FAILURE;
	}
	pthread_detach(CurrentReadThread);


    gtk_entry_set_text(DriverCurrentText, "0.0");
    gtk_entry_set_text(PACurrentText, "0.0");



    gtk_main();

out:
    return 0;
}

