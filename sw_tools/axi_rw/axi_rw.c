#include <gtk/gtk.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

#define ADDRWINDOWSIZE 0x20000L                     // size of mapped window for AXI-lite bus
//
// global variables:
//
    GtkBuilder      *Builder; 
    GtkWidget       *Window;
    GtkTextBuffer   *Textbuffer;
    GtkEntry       *Addrentry;
    GtkEntry       *Dataentry;
    GtkStatusbar      *Statusbar;
    GtkScrolledWindow *Scrollwin;

//
// mem read/write variables:
//
	int fd;                             // device identifier
    gboolean DriverPresent;



// called when write button is clicked
void on_write_button_clicked()
{
    const gchar* AddrStr;
    const gchar* DataStr;
    uint32_t Address;
    uint32_t Data;
    gchar NumString[20];
    gchar ResultString[60];

    AddrStr = gtk_entry_get_text(Addrentry);
    Address = strtoul(AddrStr, 0, 16);
    DataStr = gtk_entry_get_text(Dataentry);
    Data = strtoul(DataStr, 0, 16);
//
// check address is in window, and write if it is
//
    if(DriverPresent == TRUE)
    {
        if (Address <= (ADDRWINDOWSIZE-4))
        {
            ssize_t nsent = pwrite(fd, &Data, sizeof(Data), (off_t) Address); 
            if (nsent != sizeof(Data))
            {
                sprintf(ResultString, "ERROR: Write: addr=0x%08X   error=%s\n",Address, strerror(errno));
                gtk_text_buffer_insert_at_cursor(Textbuffer, ResultString, -1);
            }
            else
            {
                sprintf(NumString, "%08x",Data);
                gtk_entry_set_text(Dataentry, NumString);
                sprintf(ResultString, "Write: addr=0x%08X   data=0x%08X\n",Address, Data);
                gtk_text_buffer_insert_at_cursor(Textbuffer, ResultString, -1);
            }
        }
        else
        {
                sprintf(ResultString, "ERROR: Write: addr=0x%08X is outside memory window\n",Address);
                gtk_text_buffer_insert_at_cursor(Textbuffer, ResultString, -1);
        }
    }
}
  
// called when read button is clicked
void on_read_button_clicked()
{
    const gchar* AddrStr;
    const gchar* DataStr;
    uint32_t Address;
    uint32_t Data;
    gchar NumString[20];
    gchar ResultString[60];

    AddrStr = gtk_entry_get_text(Addrentry);
    Address = strtoul(AddrStr, 0, 16);
//
// check address is in window
//
    if(DriverPresent == TRUE)
    {
        if (Address <= (ADDRWINDOWSIZE-4))
        {
            ssize_t nread = pread(fd, &Data, sizeof(Data), (off_t) Address);
            if (nread != sizeof(Data))
            {
                sprintf(ResultString, "ERROR: Read: addr=0x%08X   error=%s\n",Address, strerror(errno));
                gtk_text_buffer_insert_at_cursor(Textbuffer, ResultString, -1);
            }
            else
            {
                sprintf(NumString, "%08x",Data);
                gtk_entry_set_text(Dataentry, NumString);
                sprintf(ResultString, "Read: addr=0x%08X   data=0x%08X\n",Address, Data);
                gtk_text_buffer_insert_at_cursor(Textbuffer, ResultString, -1);
            }
        }
        else
        {
                sprintf(ResultString, "ERROR: Read: addr=0x%08X is outside memory window\n",Address);
                gtk_text_buffer_insert_at_cursor(Textbuffer, ResultString, -1);
        }
    }
}


// called when window is closed
void on_window_main_destroy()
{
	close(fd);
    gtk_main_quit();
}


// called when window is closed
void on_close_button_clicked()
{
   	close(fd);
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
    Builder = gtk_builder_new_from_file("axi_rw.ui");

    Window = GTK_WIDGET(gtk_builder_get_object(Builder, "window_main"));
    Addrentry = GTK_ENTRY(gtk_builder_get_object(Builder, "txt_addr"));
    Dataentry = GTK_ENTRY(gtk_builder_get_object(Builder, "txt_data"));
    Statusbar = GTK_STATUSBAR(gtk_builder_get_object(Builder, "statusbar_main"));
    Scrollwin = GTK_SCROLLED_WINDOW(gtk_builder_get_object(Builder, "win_scroll"));
    Textbuffer = GTK_TEXT_BUFFER(gtk_builder_get_object(Builder, "textbuffer_main"));
    gtk_builder_add_callback_symbol (Builder, "on_write_button_clicked", G_CALLBACK (on_write_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_read_button_clicked", G_CALLBACK (on_read_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_window_main_destroy", G_CALLBACK (on_window_main_destroy));
    gtk_builder_add_callback_symbol (Builder, "on_close_button_clicked", G_CALLBACK (on_close_button_clicked));
    gtk_builder_connect_signals(Builder, NULL);

    g_object_unref(Builder);
    gtk_widget_show(Window);                
    Context = gtk_statusbar_get_context_id(Statusbar, "context");
//
// try to open device
//
	if ((fd = open("/dev/xdma0_user", O_RDWR)) == -1)
    {
        gtk_statusbar_push(Statusbar, Context, "No PCIe Driver");
        DriverPresent = FALSE;
    }
    else
    {
        gtk_statusbar_push(Statusbar, Context, "Connected to /dev/xdma0_user");    
        DriverPresent = TRUE;
    }

    gtk_main();

    return 0;
}

