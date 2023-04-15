//
// main file for audio test GUI app
// GUI created with GTK3
//
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


//
// global variables: for GUI:
//
GtkBuilder      *Builder; 
GtkWidget       *Window;
GtkTextBuffer   *TextBuffer;
GtkStatusbar      *StatusBar;
GtkLabel *MicActivityLbl;
GtkProgressBar *MicProgressBar;
GtkToggleButton *RbPrimary;
GtkToggleButton *RbFallback;
GtkWidget       *DlgFileChoose;
    

//
// mem read/write variables:
//
int fd;                             // device identifier
gboolean DriverPresent;             // true if device driver is accessible



//
// global needed to re-use Xilinx code
// pathname for the PCIe device driver axi-lite bus access device
//
const char* gAXI_FNAME = "/dev/xdma/card0/user";





//////////////////////////////////////////////////////////////////////////////////////
// GUI event handlers


//
// callback from microphone testing code. Set the progress bar accordingly.
//
static void MyStatusCallback(int ProgressPercent, int LevelPercent)
{
    gtk_progress_bar_set_fraction(MicProgressBar, ProgressPercent);
    // update the window
    while(gtk_events_pending())
        gtk_main_iteration();
}



  
//
// called when L speaker test button is clicked
//
void on_testL_button_clicked()
{
    gtk_text_buffer_insert_at_cursor(TextBuffer, "test L clicked", -1);
}

//
// called when R speaker test button is clicked
//
void on_testR_button_clicked()
{
    gtk_text_buffer_insert_at_cursor(TextBuffer, "test R clicked", -1);
}


//
// called when microphone test button is clicked
//
void on_MicTestButton_clicked()
{
    gtk_text_buffer_insert_at_cursor(TextBuffer, "Mic test clicked", -1);

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

    // Update October 2019: The line below replaces the 2 lines above
    Builder = gtk_builder_new_from_file("audiotest.ui");

    Window = GTK_WIDGET(gtk_builder_get_object(Builder, "window_main"));
    StatusBar = GTK_STATUSBAR(gtk_builder_get_object(Builder, "statusbar_main"));
    TextBuffer = GTK_TEXT_BUFFER(gtk_builder_get_object(Builder, "textbuffer_main"));
    MicActivityLbl = GTK_LABEL(gtk_builder_get_object(Builder, "MicActivityLabel"));
    MicProgressBar = GTK_PROGRESS_BAR(gtk_builder_get_object(Builder, "id_progress"));

    gtk_builder_add_callback_symbol (Builder, "on_testL_button_clicked", G_CALLBACK (on_testL_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_testR_button_clicked", G_CALLBACK (on_testR_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_MicTestButton_clicked", G_CALLBACK (on_MicTestButton_clicked));
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

