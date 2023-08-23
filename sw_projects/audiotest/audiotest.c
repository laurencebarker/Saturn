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
GtkLabel *MicActivityLbl;
GtkLabel *PTTLbl;
GtkProgressBar *MicProgressBar;
GtkScale *VolumeScale;
GtkSpinButton *MicDurationSpin;
GtkSpinButton *GainSpin;
GtkProgressBar *MicLevelBar;   
GtkAdjustment *VolAdjustment; 
GtkAdjustment *GainAdjustment;
GtkCheckButton *MicBoostCheck;
GtkCheckButton *MicXLRCheck;
GtkCheckButton *MicTipCheck;
GtkCheckButton *MicBiasCheck;
GtkCheckButton *LineCheck;

//
// mem read/write variables:
//
int fd;                             // device identifier
gboolean DriverPresent;             // true if device driver is accessible
pthread_t CheckForPTTThread;        // thread looks for PTT press
pthread_t MicTestThread;        	// thread runs microphone test
pthread_t SpeakerTestThread;        // thread runs speaker test
bool GMicTestInitiated;				// true if to start mic test
bool GSpeakerTestInitiated;			// true if to start speaker test
bool GSpeakerTestIsLeftChannel;		// true for left channel speaker test

#define VALIGNMENT 4096


#define VSAMPLERATE 48000							// sample rate, Hz
#define VMEMBUFFERSIZE 2097152L						// memory buffer to reserve
#define AXIBaseAddress 0x40000L						// address of StreamRead/Writer IP
#define VDURATION 10								// seconds
#define VTOTALSAMPLES VSAMPLERATE * VDURATION
#define VSPKDURATION 1								// seconds
#define VSPKSAMPLES VSAMPLERATE * VSPKDURATION
#define VDMATRANSFERSIZE 1024
#define VSAMPLEWORDSPERDMA 256
#define VDMAWORDSPERDMA 128							// 8 byte memory words
#define VDMATRANSFERS (VTOTALSAMPLES * 4) / VDMATRANSFERSIZE


int DMAWritefile_fd = -1;											// DMA write file device
int DMAReadfile_fd = -1;											// DMA read file device
char* WriteBuffer = NULL;											// data for DMA write
char* ReadBuffer = NULL;											// data for DMA read
uint32_t BufferSize = VMEMBUFFERSIZE;
bool PTTPressed = false;

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
// callback from microphone testing code. Set the progress bar accordingly.
// parameters are pecentage complete, and percentage level (0 to 100)
//
static void MyStatusCallback(float ProgressPercent, float LevelPercent)
{
	float ProgressFraction;

	ProgressFraction = ProgressPercent / 100.0;
    gtk_progress_bar_set_fraction(MicProgressBar, ProgressFraction);

	if(LevelPercent < 0.1)
		LevelPercent = 0.1;
	LevelPercent = 20.0*log10(LevelPercent) + 20;		// 0-60.0
	LevelPercent *= (100.0/60.0);
    gtk_progress_bar_set_fraction(MicLevelBar, (LevelPercent/100.0));

    // update the window - MAY NOT NEED THIS AS THREADED
//    while(gtk_events_pending())
//        gtk_main_iteration();
}

  




//
// create test data into memory buffer
// Samples is the number of samples to create
// data format is twos complement
// Freq is in Hz; ramp is freq increment over duration of pulse
// Amplitude is 0-1
//
void CreateSpkTestData(char* MemPtr, uint32_t Samples, float StartFreq, float FreqRamp, float Amplitude, bool IsL)
{
	uint32_t* Data;						// ptr to memory block to write data
	int16_t Word;						// a word of write data
	uint16_t ZeroWord = 0;
	uint32_t Cntr;						// memory counter
	double Sample;
	double Phase;
	double Ampl;
	double Freq;
	uint32_t TwoWords;					// 32 bit L&R sample

	Phase = 2.0 * M_PI * Freq / (double)VSAMPLERATE;		// 2 pi f t
	Ampl = 32767.0 * Amplitude;
	//Ampl = 400.0 * Amplitude;

	Data = (uint32_t *) MemPtr;
	printf("Scaled amplitude = %5.1f\n", Ampl);
	for(Cntr=0; Cntr < Samples; Cntr++)
	{
		Freq = StartFreq + FreqRamp*(float)Cntr/(float)Samples;
		Phase = 2.0 * M_PI * Freq / (double)VSAMPLERATE;		// 2 pi f t
		Sample = Ampl * sin(Phase * (double)Cntr);
		Word = (int16_t)Sample;
		if(IsL)
			TwoWords = (ZeroWord << 16) | (uint32_t) Word;
		else
			TwoWords = ((uint32_t) Word << 16) | ZeroWord;
		*Data++ = TwoWords;
	}
}



//
// DMA Write sample data to Codec
// Length = number of bytes to transfer
void DMAWriteToCodec(char* MemPtr, uint32_t Length)
{
	uint32_t Depth = 0;
	bool FIFOOverflow;
	uint32_t DMACount;
	uint32_t  TotalDMACount;

	TotalDMACount = Length / VDMATRANSFERSIZE;
	printf("Starting Write DMAs; total = %d\n", TotalDMACount);

	for(DMACount = 0; DMACount < TotalDMACount; DMACount++)
	{
		Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow);        // read the FIFO free locations
//		printf("FIFO monitor read; depth = %d\n", Depth);
		while (Depth < VDMAWORDSPERDMA)       // loop till space available
		{
			usleep(1000);								                    // 1ms wait
			Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow);    // read the FIFO free locations
		}
		// DMA write next batch
		DMAWriteToFPGA(DMAWritefile_fd, MemPtr, VDMATRANSFERSIZE, AXIBaseAddress);
		MemPtr += VDMATRANSFERSIZE;
	}
	usleep(10000);
}


//
// copy codec read data to codec write data
// read 16 bits; write 2 concatenated samples
// Length = number of MIC bytes to transfer
// need to read the bytes in, then write 2 copies to output buffer
//
void CopyMicToSpeaker(char* Read, char *Write, uint32_t Length)
{
	uint32_t *WritePtr;
	uint16_t *ReadPtr;
	uint16_t Sample;
	uint32_t TwoSamples;
	uint32_t Cntr;

	ReadPtr = (uint16_t *)Read;
	WritePtr = (uint32_t *)Write;

	for(Cntr=0; Cntr < Length/2; Cntr++)		// count 16 bit samples
	{
		Sample = *ReadPtr++;
		TwoSamples = (uint32_t)Sample;
		TwoSamples =((TwoSamples << 16) | TwoSamples);
		*WritePtr++ = TwoSamples;
	}
}


#define VDMADISPUPDATE 6				// #DMAs before updating the UI
//
// DMA read sample data from Codec
// Length = number of bytes to transfer
// need to read the bytes in, then write 2 copies to output buffer
// transfer 1024 bytes (512 samples, 10.7ms) per DMA
// every few DMAs, update the screen
void DMAReadFromCodec(char* MemPtr, uint32_t Length)
{
	uint32_t Depth = 0;
	bool FIFOOverflow;
	uint32_t DMACount;
	uint32_t  TotalDMACount;
	int16_t *MicReadPtr;
	uint32_t SampleCntr;
	int MicSample;
	int MaxMicLevel = 0;
	float ProgressFraction;						// activity progress (0 to 100)
	float AmplPercent;							// amplitude % (0 to 100)

	MicReadPtr = (int16_t*)MemPtr;
	TotalDMACount = Length / VDMATRANSFERSIZE;
	printf("Starting Read DMAs; total = %d\n", TotalDMACount);

	for(DMACount = 0; DMACount < TotalDMACount; DMACount++)
	{
		Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow);        // read the FIFO free locations
		//printf("FIFO monitor read; depth = %d\n", Depth);
		while (Depth < VDMAWORDSPERDMA)       // loop till enough data available
		{
			usleep(2000);								                    // 2ms wait
			Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow);    // read the FIFO free locations
		}
		// DMA read next batch of 16 bit mic samples
		// then update mic amplitude
		//
		DMAReadFromFPGA(DMAReadfile_fd, MemPtr, VDMATRANSFERSIZE, AXIBaseAddress);
		for(SampleCntr=0; SampleCntr < VDMATRANSFERSIZE/2; SampleCntr++)
		{
			MicSample = *MicReadPtr++;		// get mic sample
			if(MicSample < 0)
				MicSample = -MicSample;		// end up with abs value
			if(MicSample > MaxMicLevel)
				MaxMicLevel = MicSample;	// find largest
		}
		MemPtr += VDMATRANSFERSIZE;
		if((DMACount % VDMADISPUPDATE) == 0)
		{
			ProgressFraction = 100.0* (float)DMACount / (float)TotalDMACount;
			AmplPercent = 100.0*(float)MaxMicLevel / 32767.0;
			MyStatusCallback(ProgressFraction, AmplPercent);
			MaxMicLevel = 0;
		}
	}
}




//////////////////////////////////////////////////////////////////////////////////////
// GUI event handlers



//
// called when L speaker test button is clicked
//
void on_testL_button_clicked()
{
	GSpeakerTestIsLeftChannel = true;
	GSpeakerTestInitiated = true;
}


//
// called when R speaker test button is clicked
//
void on_testR_button_clicked()
{
	GSpeakerTestIsLeftChannel = false;
	GSpeakerTestInitiated = true;
}



//
// called to set Microphone tip/ring etc settings
//
void on_MicSettings_Changed(void)
{
	gboolean XLR, MicBoost, MicTip, MicBias, LineInput;

 
    XLR = gtk_toggle_button_get_active(MicXLRCheck);
    MicBoost = gtk_toggle_button_get_active(MicBoostCheck);
    MicTip = gtk_toggle_button_get_active(MicTipCheck);
    MicBias = gtk_toggle_button_get_active(MicBiasCheck);
    LineInput = gtk_toggle_button_get_active(LineCheck);

	SetOrionMicOptions(!MicTip, MicBias, true);
	SetMicBoost(MicBoost);
	SetBalancedMicInput(XLR);
	SetMicLineInput(LineInput);
}



//
// called when microphone test button is clicked
//
void on_MicTestButton_clicked()
{
	GMicTestInitiated = true;
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
    gtk_main_quit();
} 



//
// this runs as its own thread to do record then replay test
// thread initiated at the start.
// done in a thread so GUI event handlers not hung
//
void* MicTest(void *arg)
{
	gint Duration;					// record and replay duration in seconds
	uint32_t Length;
	uint32_t Samples;
	double Gain;											// line gain	
	uint32_t IntGain;


	while (1)
	{
		usleep(50000);												// 50ms wait
		if(GMicTestInitiated)
		{

			Gain = gtk_spin_button_get_value(GainSpin);
			IntGain = (uint32_t)((Gain+34.5)/1.5);
			SetCodecLineInGain(IntGain);
			printf("line selected; gain = %7.1f dB; intGain =%d\n", Gain, IntGain);

			gtk_label_set_text(MicActivityLbl, "Speak Now");
			Duration = gtk_spin_button_get_value_as_int(MicDurationSpin);
			Samples = 48000 * Duration;						// no. samples to record and play
			Length = Samples * 2;							// 2 bytes per mic sample
			ResetDMAStreamFIFO(eMicCodecDMA);
			DMAReadFromCodec(ReadBuffer, Length);
			CopyMicToSpeaker(ReadBuffer, WriteBuffer, Length);
//
// we have done the record. now play back.
//
    		gtk_progress_bar_set_fraction(MicLevelBar, 0.0);
			gtk_label_set_text(MicActivityLbl, "Playing");
			Length = Samples * 4;							// 4 bytes per speaker sample
			usleep(1000);
			DMAWriteToCodec(WriteBuffer, Length);
			gtk_label_set_text(MicActivityLbl, "Idle");
			GMicTestInitiated = false;
		}
	}
}


//
// this runs as its own thread to do speaker test
// thread initiated at the start.
// done in a thread so GUI event handlers not hung
//
void* SpeakerTest(void *arg)
{
    double Ampl;
	uint32_t Length;
	float Freq;
	float FreqRamp;

	while (1)
	{
		if(GSpeakerTestInitiated)
		{
			Ampl =  gtk_range_get_value(VolumeScale);			// 0 to 100.0
			Ampl = Ampl / 100.0;

			if(!GSpeakerTestIsLeftChannel)
			{
				Freq = 1000.0;
				FreqRamp = 0.0;
			}
			else
			{
				Freq = 400.0;
				FreqRamp = 0.0;
			}
			ResetDMAStreamFIFO(eSpkCodecDMA);
			CreateSpkTestData(WriteBuffer, VSPKSAMPLES, Freq, FreqRamp, Ampl, GSpeakerTestIsLeftChannel);
			Length = VSPKSAMPLES * 4;
			gtk_text_buffer_insert_at_cursor(TextBuffer, "playing sinewave tone via DMA\n", -1);
			DMAWriteToCodec(WriteBuffer, Length);
			GSpeakerTestInitiated = false;
			usleep(50000);												// 50ms wait
		}
	}
}


//
// this runs as its own thread to check for PTT pressed
// thread initiated at the start.
//
void* CheckForPttPressed(void *arg)
{
	bool Pressed;
	bool PTTPressed = false;							// persistent state

	while (1)
	{
		usleep(50000);												// 50ms wait
		ReadStatusRegister();											// read h/w register
		Pressed = GetPTTInput();
		if(Pressed != PTTPressed)
		{
			PTTPressed =Pressed;
			if(Pressed)
				gtk_label_set_text(PTTLbl, "PTT Pressed");
			else
				gtk_label_set_text(PTTLbl, "PTT Released");
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
    Builder = gtk_builder_new_from_file("audiotest.ui");

    Window = GTK_WIDGET(gtk_builder_get_object(Builder, "window_main"));
    StatusBar = GTK_STATUSBAR(gtk_builder_get_object(Builder, "statusbar_main"));
    TextBuffer = GTK_TEXT_BUFFER(gtk_builder_get_object(Builder, "textbuffer_main"));
    MicActivityLbl = GTK_LABEL(gtk_builder_get_object(Builder, "MicActivityLabel"));
    PTTLbl = GTK_LABEL(gtk_builder_get_object(Builder, "PTTLabel"));
    MicProgressBar = GTK_PROGRESS_BAR(gtk_builder_get_object(Builder, "id_progress"));
    VolumeScale = GTK_SCALE(gtk_builder_get_object(Builder, "VolumeScale"));
    MicDurationSpin = GTK_SPIN_BUTTON(gtk_builder_get_object(Builder, "MicDurationSpin"));
    GainSpin = GTK_SPIN_BUTTON(gtk_builder_get_object(Builder, "GainSpin"));
    MicLevelBar = GTK_PROGRESS_BAR(gtk_builder_get_object(Builder, "MicLevelBar"));    
    VolAdjustment = GTK_ADJUSTMENT(gtk_builder_get_object(Builder, "id_voladjustment"));
    GainAdjustment = GTK_ADJUSTMENT(gtk_builder_get_object(Builder, "id_gainadjustment"));
    MicBoostCheck = GTK_CHECK_BUTTON(gtk_builder_get_object(Builder, "MicBoostCheck"));
    MicXLRCheck = GTK_CHECK_BUTTON(gtk_builder_get_object(Builder, "MicXLRCheck"));
    MicTipCheck = GTK_CHECK_BUTTON(gtk_builder_get_object(Builder, "MicTipCheck"));
    MicBiasCheck = GTK_CHECK_BUTTON(gtk_builder_get_object(Builder, "MicBiasCheck"));
    LineCheck = GTK_CHECK_BUTTON(gtk_builder_get_object(Builder, "LineCheck"));

    gtk_builder_add_callback_symbol (Builder, "on_testL_button_clicked", G_CALLBACK (on_testL_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_testR_button_clicked", G_CALLBACK (on_testR_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_MicTestButton_clicked", G_CALLBACK (on_MicTestButton_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_window_main_destroy", G_CALLBACK (on_window_main_destroy));
    gtk_builder_add_callback_symbol (Builder, "on_close_button_clicked", G_CALLBACK (on_close_button_clicked));
    gtk_builder_add_callback_symbol (Builder, "on_MicSettings_toggled", G_CALLBACK (on_MicSettings_Changed));

    gtk_builder_connect_signals(Builder, NULL);
	gtk_label_set_text(MicActivityLbl, "Idle");

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
	posix_memalign((void **)&WriteBuffer, VALIGNMENT, BufferSize);
	if(!WriteBuffer)
	{
		printf("write buffer allocation failed\n");
		goto out;
	}

	posix_memalign((void **)&ReadBuffer, VALIGNMENT, BufferSize);
	if(!ReadBuffer)
	{
		printf("read buffer allocation failed\n");
		goto out;
	}

	DMAWritefile_fd = open("/dev/xdma0_h2c_0", O_RDWR);
	if(DMAWritefile_fd < 0)
	{
		printf("XDMA write device open failed\n");
		goto out;
	}

	DMAReadfile_fd = open("/dev/xdma0_c2h_0", O_RDWR);
	if(DMAReadfile_fd < 0)
	{
		printf("XDMA read device open failed\n");
		goto out;
	}
	//
	// we have devices and memory.
	//
	on_MicSettings_Changed();									// set mic inputs for defaults
	gtk_progress_bar_set_fraction(MicLevelBar, 0.0);

//
// start up thread to check for no longer getting messages, to set back to inactive
//
	if(pthread_create(&CheckForPTTThread, NULL, CheckForPttPressed, NULL) < 0)
	{
	perror("pthread_create check for PTT");
	return EXIT_FAILURE;
	}
	pthread_detach(CheckForPTTThread);

//
// start up thread to check for mic test pressed
//
	if(pthread_create(&MicTestThread, NULL, MicTest, NULL) < 0)
	{
	perror("pthread_create check for Mic Test");
	return EXIT_FAILURE;
	}
	pthread_detach(MicTestThread);

//
// start up thread to check for speaker test pressed
//
	if(pthread_create(&SpeakerTestThread, NULL, SpeakerTest, NULL) < 0)
	{
	perror("pthread_create check for Speaker Test");
	return EXIT_FAILURE;
	}
	pthread_detach(SpeakerTestThread);




    gtk_main();

out:
    return 0;
}

