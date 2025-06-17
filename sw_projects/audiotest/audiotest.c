/*
 * audiotest.c - Audio Test GUI Application
 *
 * This program creates a GTK3-based GUI for testing audio input/output using DMA
 * transfers to/from a codec on a PCIe-based hardware platform (Saturn). It supports
 * microphone recording/playback and speaker tests with configurable settings.
 *
 * Key features:
 * - GUI for controlling microphone and speaker tests.
 * - Threaded operation for non-blocking DMA transfers and PTT monitoring.
 * - Thread-safe access to shared resources using mutexes.
 * - Comprehensive error handling and resource cleanup.
 * - Optimized audio data processing and DMA operations.
 *
 * Dependencies:
 * - GTK3 for GUI.
 * - POSIX threads and semaphores for concurrency.
 * - Custom hardware libraries (saturntypes.h, hwaccess.h, etc.).
 * - Device files (/dev/xdma0_user, /dev/xdma0_h2c_0, /dev/xdma0_c2h_0).
 *
 * Compilation:
 *   gcc -o audiotest audiotest.c `pkg-config --cflags --libs gtk+-3.0` -lpthread -lm
 */

#include <gtk/gtk.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/poll.h>
#include <math.h>

#include "../common/saturntypes.h"
#include "../common/hwaccess.h"
#include "../common/saturnregisters.h"
#include "../common/saturndrivers.h"
#include "../common/codecwrite.h"
#include "../common/version.h"
#include "../common/debugaids.h"

// Configuration constants
#define ALIGNMENT 4096                    // Memory alignment for DMA buffers
#define SAMPLE_RATE 48000                 // Audio sample rate in Hz
#define MEM_BUFFER_SIZE (2 * 1024 * 1024) // 2MB buffer for DMA transfers
#define DURATION_SECONDS 10               // Default microphone test duration in seconds
#define SPK_DURATION_SECONDS 1            // Speaker test duration in seconds
#define TOTAL_SAMPLES (SAMPLE_RATE * DURATION_SECONDS) // Total samples for mic test
#define SPK_SAMPLES (SAMPLE_RATE * SPK_DURATION_SECONDS) // Total samples for speaker test
#define DMA_TRANSFER_SIZE 1024            // Bytes per DMA transfer
#define SAMPLE_WORDS_PER_DMA 256         // Number of 16-bit samples per DMA
#define DMA_WORDS_PER_DMA 128            // Number of 8-byte words per DMA
#define DMA_TRANSFERS (TOTAL_SAMPLES * 4) / DMA_TRANSFER_SIZE // Total DMA transfers
#define DMA_DISP_UPDATE 6                 // Number of DMAs before UI update
#define AXI_BASE_ADDRESS 0x40000L         // Base address of StreamRead/Writer IP
#define AXI_FNAME "/dev/xdma0_user"       // PCIe device driver path for AXI-lite access
#define MIC_STATUS_IDLE "Idle"            // Status label for idle state
#define MIC_STATUS_RECORDING "Speak Now"  // Status label for recording
#define MIC_STATUS_PLAYING "Playing"      // Status label for playback

// Application context for GUI elements
typedef struct {
    GtkWidget *window;               // Main application window
    GtkStatusbar *status_bar;        // Status bar for general messages
    GtkTextBuffer *text_buffer;      // Text buffer for log messages
    GtkLabel *mic_activity_label;    // Label for microphone status
    GtkLabel *ptt_label;             // Label for PTT status
    GtkProgressBar *mic_progress_bar; // Progress bar for test progress
    GtkProgressBar *mic_level_bar;    // Progress bar for mic signal level
    GtkRange *volume_scale;          // Slider for speaker test volume
    GtkSpinButton *mic_duration_spin; // Spin button for mic test duration
    GtkSpinButton *gain_spin;        // Spin button for mic input gain
    GtkAdjustment *vol_adjustment;   // Adjustment for volume scale
    GtkAdjustment *gain_adjustment;  // Adjustment for gain spin button
    GtkToggleButton *mic_boost_check; // Checkbox for mic boost
    GtkToggleButton *mic_xlr_check;  // Checkbox for XLR input
    GtkToggleButton *mic_tip_check;  // Checkbox for mic tip/ring
    GtkToggleButton *mic_bias_check; // Checkbox for mic bias
    GtkToggleButton *line_check;     // Checkbox for line input
} AppContext;

// Audio context for hardware and buffer management
typedef struct {
    char *write_buffer;              // Buffer for DMA writes to codec
    char *read_buffer;               // Buffer for DMA reads from codec
    int dma_write_fd;                // File descriptor for DMA write device
    int dma_read_fd;                 // File descriptor for DMA read device
    uint32_t buffer_size;            // Size of DMA buffers
    bool mic_test_initiated;         // Flag to start microphone test
    bool speaker_test_initiated;     // Flag to start speaker test
    bool speaker_test_is_left_channel; // True for left channel speaker test
    pthread_mutex_t mic_test_mutex;  // Mutex for mic_test_initiated
    pthread_mutex_t speaker_test_mutex; // Mutex for speaker_test_initiated
} AudioContext;

// Global synchronization primitives
sem_t DDCInSelMutex;                 // Protects DDC input select register
sem_t DDCResetFIFOMutex;             // Protects FIFO reset register
sem_t RFGPIOMutex;                   // Protects RF GPIO register
sem_t CodecRegMutex;                 // Protects codec register writes
volatile bool keep_running = true;    // Flag to control thread termination

/*
 * HandlerSetEERMode: Placeholder callback for EER mode setting.
 * @param Unused: Boolean parameter (not used in this implementation).
 * Note: This function is required by saturndrivers.c but not used in audiotest.
 */
void HandlerSetEERMode(bool Unused) {
    // Stub implementation to satisfy linker dependency
}

/*
 * cleanup: Frees allocated resources and closes file descriptors.
 * @param app: Pointer to application context.
 * @param audio: Pointer to audio context.
 */
void cleanup(AppContext *app, AudioContext *audio) {
    keep_running = false; // Signal threads to terminate
    if (audio->write_buffer) free(audio->write_buffer);
    if (audio->read_buffer) free(audio->read_buffer);
    if (audio->dma_write_fd >= 0) close(audio->dma_write_fd);
    if (audio->dma_read_fd >= 0) close(audio->dma_read_fd);
    sem_destroy(&DDCInSelMutex);
    sem_destroy(&DDCResetFIFOMutex);
    sem_destroy(&RFGPIOMutex);
    sem_destroy(&CodecRegMutex);
    pthread_mutex_destroy(&audio->mic_test_mutex);
    pthread_mutex_destroy(&audio->speaker_test_mutex);
}

/*
 * set_mic_test_initiated: Thread-safe setting of mic test flag.
 * @param audio: Pointer to audio context.
 * @param value: New value for mic_test_initiated.
 */
void set_mic_test_initiated(AudioContext *audio, bool value) {
    pthread_mutex_lock(&audio->mic_test_mutex);
    audio->mic_test_initiated = value;
    pthread_mutex_unlock(&audio->mic_test_mutex);
}

/*
 * get_mic_test_initiated: Thread-safe retrieval of mic test flag.
 * @param audio: Pointer to audio context.
 * @return: Current value of mic_test_initiated.
 */
bool get_mic_test_initiated(AudioContext *audio) {
    bool value;
    pthread_mutex_lock(&audio->mic_test_mutex);
    value = audio->mic_test_initiated;
    pthread_mutex_unlock(&audio->mic_test_mutex);
    return value;
}

/*
 * set_speaker_test_initiated: Thread-safe setting of speaker test flags.
 * @param audio: Pointer to audio context.
 * @param value: New value for speaker_test_initiated.
 * @param is_left: True for left channel, false for right.
 */
void set_speaker_test_initiated(AudioContext *audio, bool value, bool is_left) {
    pthread_mutex_lock(&audio->speaker_test_mutex);
    audio->speaker_test_initiated = value;
    audio->speaker_test_is_left_channel = is_left;
    pthread_mutex_unlock(&audio->speaker_test_mutex);
}

/*
 * get_speaker_test_initiated: Thread-safe retrieval of speaker test flags.
 * @param audio: Pointer to audio context.
 * @param value: Pointer to store speaker_test_initiated.
 * @param is_left: Pointer to store speaker_test_is_left_channel.
 */
void get_speaker_test_initiated(AudioContext *audio, bool *value, bool *is_left) {
    pthread_mutex_lock(&audio->speaker_test_mutex);
    *value = audio->speaker_test_initiated;
    *is_left = audio->speaker_test_is_left_channel;
    pthread_mutex_unlock(&audio->speaker_test_mutex);
}

/*
 * update_progress_bar: Updates a progress bar in the GTK main thread.
 * @param user_data: Pointer to ProgressUpdateData.
 * @return: G_SOURCE_REMOVE to remove the idle callback.
 */
typedef struct {
    GtkProgressBar *progress_bar; // Target progress bar
    float fraction;               // Fraction to set (0.0 to 1.0)
} ProgressUpdateData;

static gboolean update_progress_bar(gpointer user_data) {
    ProgressUpdateData *data = (ProgressUpdateData *)user_data;
    gtk_progress_bar_set_fraction(data->progress_bar, data->fraction);
    g_free(data);
    return G_SOURCE_REMOVE;
}

/*
 * MyStatusCallback: Updates progress bars for test progress and mic level.
 * @param app: Pointer to application context.
 * @param ProgressPercent: Percentage of test completion (0 to 100).
 * @param LevelPercent: Microphone signal level percentage (0 to 100).
 */
static void MyStatusCallback(AppContext *app, float ProgressPercent, float LevelPercent) {
    // Update progress bar
    ProgressUpdateData *data = g_new(ProgressUpdateData, 1);
    data->progress_bar = app->mic_progress_bar;
    data->fraction = ProgressPercent / 100.0;
    g_idle_add(update_progress_bar, data);

    // Update level bar with logarithmic scaling
    data = g_new(ProgressUpdateData, 1);
    data->progress_bar = app->mic_level_bar;
    LevelPercent = (LevelPercent < 0.0) ? 0.0 : LevelPercent;
    LevelPercent = 20.0 * log10(LevelPercent + 1e-6) + 20; // Avoid log(0)
    LevelPercent *= (100.0 / 60.0); // Scale to 0-100
    data->fraction = LevelPercent / 100.0;
    g_idle_add(update_progress_bar, data);
}

/*
 * CreateSpkTestData: Generates sinewave test data for speaker output.
 * @param MemPtr: Buffer to store generated data.
 * @param Samples: Number of samples to generate.
 * @param StartFreq: Starting frequency in Hz.
 * @param FreqRamp: Frequency ramp over duration.
 * @param Amplitude: Amplitude (0 to 1).
 * @param IsL: True for left channel, false for right.
 */
void CreateSpkTestData(char *MemPtr, uint32_t Samples, float StartFreq, float FreqRamp, float Amplitude, bool IsL) {
    uint32_t *Data = (uint32_t *)MemPtr;
    double Ampl = 32767.0 * Amplitude; // Scale to 16-bit range
    double Phase = 0.0; // Current phase in radians
    double PhaseIncrement;
    float Freq = StartFreq;
    uint16_t ZeroWord = 0; // Zero for unused channel

    printf("Scaled amplitude = %5.1f\n", Ampl);
    for (uint32_t Cntr = 0; Cntr < Samples; Cntr++) {
        // Calculate phase increment for current frequency
        Freq = StartFreq + FreqRamp * (float)Cntr / Samples;
        PhaseIncrement = 2.0 * M_PI * Freq / SAMPLE_RATE;
        Phase += PhaseIncrement;
        int16_t Word = (int16_t)(Ampl * sin(Phase));
        // Pack left or right channel sample
        uint32_t TwoWords = IsL ? (ZeroWord << 16) | (uint16_t)Word : ((uint16_t)Word << 16) | ZeroWord;
        *Data++ = TwoWords;
    }
}

/*
 * DMAWriteToCodec: Writes data to codec via DMA.
 * @param audio: Pointer to audio context.
 * @param MemPtr: Buffer containing data to write.
 * @param Length: Number of bytes to transfer.
 */
void DMAWriteToCodec(AudioContext *audio, char *MemPtr, uint32_t Length) {
    uint32_t Depth = 0, Spare;
    bool FIFOOverflow, OverThreshold, Underflow;
    uint32_t DMACount, TotalDMACount = Length / DMA_TRANSFER_SIZE;
    struct pollfd pfd = { .fd = audio->dma_write_fd, .events = POLLOUT };

    printf("Starting Write DMAs; total = %d\n", TotalDMACount);
    for (DMACount = 0; DMACount < TotalDMACount; DMACount++) {
        // Wait for FIFO to have enough space
        Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow, &OverThreshold, &Underflow, &Spare);
        while (Depth < DMA_WORDS_PER_DMA) {
            if (poll(&pfd, 1, 1000) < 0) {
                fprintf(stderr, "Poll error on DMA write: %s\n", strerror(errno));
                break;
            }
            Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow, &OverThreshold, &Underflow, &Spare);
        }
        // Perform DMA write
        DMAWriteToFPGA(audio->dma_write_fd, MemPtr, DMA_TRANSFER_SIZE, AXI_BASE_ADDRESS);
        MemPtr += DMA_TRANSFER_SIZE;
    }
    usleep(10000); // Brief wait to ensure completion
}

/*
 * CopyMicToSpeaker: Copies microphone data to speaker buffer (dual mono).
 * @param Read: Input buffer with 16-bit mic samples.
 * @param Write: Output buffer for 32-bit stereo samples.
 * @param Length: Number of bytes in input buffer.
 */
void CopyMicToSpeaker(char *Read, char *Write, uint32_t Length) {
    uint32_t *WritePtr = (uint32_t *)Write;
    uint16_t *ReadPtr = (uint16_t *)Read;

    for (uint32_t Cntr = 0; Cntr < Length / 2; Cntr++) {
        uint16_t Sample = *ReadPtr++;
        uint32_t TwoSamples = (uint32_t)Sample;
        TwoSamples = (TwoSamples << 16) | TwoSamples; // Duplicate to both channels
        *WritePtr++ = TwoSamples;
    }
}

/*
 * DMAReadFromCodec: Reads data from codec via DMA and updates UI.
 * @param app: Pointer to application context.
 * @param audio: Pointer to audio context.
 * @param MemPtr: Buffer to store read data.
 * @param Length: Number of bytes to read.
 */
void DMAReadFromCodec(AppContext *app, AudioContext *audio, char *MemPtr, uint32_t Length) {
    uint32_t Depth = 0, Spare;
    bool FIFOOverflow, OverThreshold, Underflow;
    uint32_t DMACount, TotalDMACount = Length / DMA_TRANSFER_SIZE;
    int16_t *MicReadPtr = (int16_t *)MemPtr;
    int MaxMicLevel = 0;
    struct pollfd pfd = { .fd = audio->dma_read_fd, .events = POLLIN };

    printf("Starting Read DMAs; total = %d\n", TotalDMACount);
    for (DMACount = 0; DMACount < TotalDMACount; DMACount++) {
        // Wait for sufficient data in FIFO
        Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow, &OverThreshold, &Underflow, &Spare);
        while (Depth < DMA_WORDS_PER_DMA) {
            if (poll(&pfd, 1, 1000) < 0) {
                fprintf(stderr, "Poll error on DMA read: %s\n", strerror(errno));
                break;
            }
            Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow, &OverThreshold, &Underflow, &Spare);
        }
        // Read DMA data and find peak amplitude
        DMAReadFromFPGA(audio->dma_read_fd, MemPtr, DMA_TRANSFER_SIZE, AXI_BASE_ADDRESS);
        for (uint32_t SampleCntr = 0; SampleCntr < DMA_TRANSFER_SIZE / 2; SampleCntr++) {
            int MicSample = *MicReadPtr++;
            MicSample = abs(MicSample);
            if (MicSample > MaxMicLevel) MaxMicLevel = MicSample;
        }
        MemPtr += DMA_TRANSFER_SIZE;
        // Update UI periodically
        if ((DMACount % DMA_DISP_UPDATE) == 0) {
            float ProgressFraction = 100.0 * (float)DMACount / TotalDMACount;
            float AmplPercent = 100.0 * (float)MaxMicLevel / 32767.0;
            MyStatusCallback(app, ProgressFraction, AmplPercent);
            MaxMicLevel = 0;
        }
    }
}

/*
 * on_testL_button_clicked: Handler for left speaker test button.
 * @param button: The clicked button.
 * @param audio: Pointer to audio context.
 */
void on_testL_button_clicked(GtkButton *button, AudioContext *audio) {
    set_speaker_test_initiated(audio, true, true);
}

/*
 * on_testR_button_clicked: Handler for right speaker test button.
 * @param button: The clicked button.
 * @param audio: Pointer to audio context.
 */
void on_testR_button_clicked(GtkButton *button, AudioContext *audio) {
    set_speaker_test_initiated(audio, true, false);
}

/*
 * on_MicSettings_Changed: Updates microphone settings based on GUI toggles.
 * @param button: The toggled button.
 * @param app: Pointer to application context.
 */
void on_MicSettings_Changed(GtkToggleButton *button, AppContext *app) {
    gboolean XLR = gtk_toggle_button_get_active(app->mic_xlr_check);
    gboolean MicBoost = gtk_toggle_button_get_active(app->mic_boost_check);
    gboolean MicTip = gtk_toggle_button_get_active(app->mic_tip_check);
    gboolean MicBias = gtk_toggle_button_get_active(app->mic_bias_check);
    gboolean LineInput = gtk_toggle_button_get_active(app->line_check);

    // Apply hardware settings
    SetOrionMicOptions(!MicTip, MicBias, true);
    SetMicBoost(MicBoost);
    SetBalancedMicInput(XLR);
    SetMicLineInput(LineInput);
}

/*
 * on_MicTestButton_clicked: Initiates microphone test.
 * @param button: The clicked button.
 * @param audio: Pointer to audio context.
 */
void on_MicTestButton_clicked(GtkButton *button, AudioContext *audio) {
    set_mic_test_initiated(audio, true);
}

/*
 * on_window_main_destroy: Cleans up and exits on window close.
 * @param widget: The window widget.
 * @param app: Pointer to application context.
 */
void on_window_main_destroy(GtkWidget *widget, AppContext *app) {
    gtk_main_quit();
}

/*
 * MicTest: Thread to handle microphone record and playback.
 * @param arg: Array containing AppContext and AudioContext pointers.
 */
void *MicTest(void *arg) {
    AppContext *app = ((void **)arg)[0];
    AudioContext *audio = ((void **)arg)[1];

    while (keep_running) {
        usleep(50000); // 50ms polling interval
        if (get_mic_test_initiated(audio)) {
            // Configure gain
            double Gain = gtk_spin_button_get_value(app->gain_spin);
            uint32_t IntGain = (uint32_t)((Gain + 34.5) / 1.5);
            SetCodecLineInGain(IntGain);
            printf("Line selected; gain = %7.1f dB; intGain = %d\n", Gain, IntGain);

            // Record phase
            gtk_label_set_text(app->mic_activity_label, MIC_STATUS_RECORDING);
            gint Duration = gtk_spin_button_get_value_as_int(app->mic_duration_spin);
            uint32_t Samples = SAMPLE_RATE * Duration;
            uint32_t Length = Samples * 2; // 16-bit samples
            ResetDMAStreamFIFO(eMicCodecDMA);
            DMAReadFromCodec(app, audio, audio->read_buffer, Length);
            CopyMicToSpeaker(audio->read_buffer, audio->write_buffer, Length);

            // Playback phase
            gtk_progress_bar_set_fraction(app->mic_level_bar, 0.0);
            gtk_label_set_text(app->mic_activity_label, MIC_STATUS_PLAYING);
            Length = Samples * 4; // 32-bit stereo samples
            usleep(1000); // Brief delay before playback
            DMAWriteToCodec(audio, audio->write_buffer, Length);
            gtk_label_set_text(app->mic_activity_label, MIC_STATUS_IDLE);
            set_mic_test_initiated(audio, false);
        }
    }
    return NULL;
}

/*
 * SpeakerTest: Thread to handle speaker test with sinewave output.
 * @param arg: Array containing AppContext and AudioContext pointers.
 */
void *SpeakerTest(void *arg) {
    AppContext *app = ((void **)arg)[0];
    AudioContext *audio = ((void **)arg)[1];

    while (keep_running) {
        bool initiated, is_left;
        get_speaker_test_initiated(audio, &initiated, &is_left);
        if (initiated) {
            // Configure test parameters
            double Ampl = gtk_range_get_value(app->volume_scale) / 100.0;
            float Freq = is_left ? 400.0 : 1000.0; // Different frequencies for L/R
            float FreqRamp = 0.0;
            ResetDMAStreamFIFO(eSpkCodecDMA);
            CreateSpkTestData(audio->write_buffer, SPK_SAMPLES, Freq, FreqRamp, Ampl, is_left);
            uint32_t Length = SPK_SAMPLES * 4; // 32-bit stereo samples
            gtk_text_buffer_insert_at_cursor(app->text_buffer, "Playing sinewave tone via DMA\n", -1);
            DMAWriteToCodec(audio, audio->write_buffer, Length);
            set_speaker_test_initiated(audio, false, is_left);
            usleep(50000); // 50ms delay between tests
        }
    }
    return NULL;
}

/*
 * CheckForPttPressed: Thread to monitor PTT input status.
 * @param arg: Pointer to AppContext.
 */
void *CheckForPttPressed(void *arg) {
    AppContext *app = (AppContext *)arg;
    bool PTTPressed = false;

    while (keep_running) {
        usleep(50000); // 50ms polling interval
        ReadStatusRegister();
        bool Pressed = GetPTTInput();
        if (Pressed != PTTPressed) {
            PTTPressed = Pressed;
            gtk_label_set_text(app->ptt_label, Pressed ? "PTT Pressed" : "PTT Released");
        }
    }
    return NULL;
}

/*
 * main: Initializes the application and runs the GTK main loop.
 * @param argc: Number of command-line arguments.
 * @param argv: Array of command-line arguments.
 * @return: 0 on success, non-zero on failure.
 */
int main(int argc, char *argv[]) {
    AppContext app = {0};
    AudioContext audio = {0};
    audio.buffer_size = MEM_BUFFER_SIZE;
    pthread_t ptt_thread, mic_test_thread, speaker_test_thread;
    void *thread_args[2] = {&app, &audio};

    // Initialize GTK
    gtk_init(&argc, &argv);

    // Load GUI from UI file
    GtkBuilder *builder = gtk_builder_new_from_file("audiotest.ui");
    if (!builder) {
        fprintf(stderr, "Failed to load audiotest.ui\n");
        return EXIT_FAILURE;
    }

    // Initialize GUI elements
    app.window = GTK_WIDGET(gtk_builder_get_object(builder, "window_main"));
    app.status_bar = GTK_STATUSBAR(gtk_builder_get_object(builder, "statusbar_main"));
    app.text_buffer = GTK_TEXT_BUFFER(gtk_builder_get_object(builder, "textbuffer_main"));
    app.mic_activity_label = GTK_LABEL(gtk_builder_get_object(builder, "MicActivityLabel"));
    app.ptt_label = GTK_LABEL(gtk_builder_get_object(builder, "PTTLabel"));
    app.mic_progress_bar = GTK_PROGRESS_BAR(gtk_builder_get_object(builder, "id_progress"));
    app.mic_level_bar = GTK_PROGRESS_BAR(gtk_builder_get_object(builder, "MicLevelBar"));
    app.volume_scale = GTK_RANGE(gtk_builder_get_object(builder, "VolumeScale"));
    app.mic_duration_spin = GTK_SPIN_BUTTON(gtk_builder_get_object(builder, "MicDurationSpin"));
    app.gain_spin = GTK_SPIN_BUTTON(gtk_builder_get_object(builder, "GainSpin"));
    app.vol_adjustment = GTK_ADJUSTMENT(gtk_builder_get_object(builder, "id_voladjustment"));
    app.gain_adjustment = GTK_ADJUSTMENT(gtk_builder_get_object(builder, "id_gainadjustment"));
    app.mic_boost_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "MicBoostCheck"));
    app.mic_xlr_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "MicXLRCheck"));
    app.mic_tip_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "MicTipCheck"));
    app.mic_bias_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "MicBiasCheck"));
    app.line_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "LineCheck"));

    // Connect signal handlers
    gtk_builder_add_callback_symbol(builder, "on_testL_button_clicked", G_CALLBACK(on_testL_button_clicked));
    gtk_builder_add_callback_symbol(builder, "on_testR_button_clicked", G_CALLBACK(on_testR_button_clicked));
    gtk_builder_add_callback_symbol(builder, "on_MicTestButton_clicked", G_CALLBACK(on_MicTestButton_clicked));
    gtk_builder_add_callback_symbol(builder, "on_window_main_destroy", G_CALLBACK(on_window_main_destroy));
    gtk_builder_add_callback_symbol(builder, "on_MicSettings_toggled", G_CALLBACK(on_MicSettings_Changed));
    gtk_builder_connect_signals(builder, &audio);
    gtk_label_set_text(app.mic_activity_label, MIC_STATUS_IDLE);
    g_object_unref(builder);

    // Initialize synchronization primitives
    sem_init(&DDCInSelMutex, 0, 1);
    sem_init(&DDCResetFIFOMutex, 0, 1);
    sem_init(&RFGPIOMutex, 0, 1);
    sem_init(&CodecRegMutex, 0, 1);
    pthread_mutex_init(&audio.mic_test_mutex, NULL);
    pthread_mutex_init(&audio.speaker_test_mutex, NULL);

    // Initialize hardware
    OpenXDMADriver(true);
    PrintVersionInfo();
    CodecInitialise();
    SetByteSwapping(false);
    SetSpkrMute(false);

    // Allocate aligned DMA buffers
    if (posix_memalign((void **)&audio.write_buffer, ALIGNMENT, audio.buffer_size) != 0) {
        fprintf(stderr, "Write buffer allocation failed\n");
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    if ((uintptr_t)audio.write_buffer % ALIGNMENT != 0) {
        fprintf(stderr, "Write buffer not aligned\n");
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }

    if (posix_memalign((void **)&audio.read_buffer, ALIGNMENT, audio.buffer_size) != 0) {
        fprintf(stderr, "Read buffer allocation failed\n");
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    if ((uintptr_t)audio.read_buffer % ALIGNMENT != 0) {
        fprintf(stderr, "Read buffer not aligned\n");
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }

    // Open DMA device files with security checks
    struct stat st;
    if (stat("/dev/xdma0_h2c_0", &st) == 0 && !S_ISCHR(st.st_mode)) {
        fprintf(stderr, "Invalid DMA write device\n");
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    audio.dma_write_fd = open("/dev/xdma0_h2c_0", O_RDWR | O_CLOEXEC);
    if (audio.dma_write_fd < 0) {
        fprintf(stderr, "Failed to open DMA write device: %s\n", strerror(errno));
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }

    if (stat("/dev/xdma0_c2h_0", &st) == 0 && !S_ISCHR(st.st_mode)) {
        fprintf(stderr, "Invalid DMA read device\n");
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    audio.dma_read_fd = open("/dev/xdma0_c2h_0", O_RDWR | O_CLOEXEC);
    if (audio.dma_read_fd < 0) {
        fprintf(stderr, "Failed to open DMA read device: %s\n", strerror(errno));
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }

    // Apply initial microphone settings
    on_MicSettings_Changed(NULL, &app);
    gtk_progress_bar_set_fraction(app.mic_level_bar, 0.0);

    // Start threads
    if (pthread_create(&ptt_thread, NULL, CheckForPttPressed, &app) < 0) {
        fprintf(stderr, "Failed to create PTT thread: %s\n", strerror(errno));
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    if (pthread_create(&mic_test_thread, NULL, MicTest, thread_args) < 0) {
        fprintf(stderr, "Failed to create mic test thread: %s\n", strerror(errno));
        cleanup(&app, &audio);
        pthread_cancel(ptt_thread);
        return EXIT_FAILURE;
    }
    if (pthread_create(&speaker_test_thread, NULL, SpeakerTest, thread_args) < 0) {
        fprintf(stderr, "Failed to create speaker test thread: %s\n", strerror(errno));
        cleanup(&app, &audio);
        pthread_cancel(ptt_thread);
        pthread_cancel(mic_test_thread);
        return EXIT_FAILURE;
    }

    // Run GTK main loop
    gtk_main();

    // Cleanup and join threads
    keep_running = false;
    pthread_join(ptt_thread, NULL);
    pthread_join(mic_test_thread, NULL);
    pthread_join(speaker_test_thread, NULL);
    cleanup(&app, &audio);
    return 0;
}
