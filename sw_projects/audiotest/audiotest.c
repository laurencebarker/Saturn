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
 * - Overload indicator (latches for 0.5s with dBFS value) and near-peak indicator (6dB/10dB from peak with dBFS value).
 * - Separate line and mic gain controls with persistent settings saved to ~/.audiotestrc.
 * - Dynamic mic level bar using a circular buffer for peak detection over 250ms.
 *
 * NOTE
 * audiotest will not run correctly if there is an instance of p2app or piHPSDR
 * running in the background. p2app/piHPSDR set byte swapping to "network byte order"
 * which is NOT what this app uses. A warning dialog will appear if these are detected.
 * Kill any instance of p2app or piHPSDR first!
 *
 * Dependencies:
 * - GTK3 for GUI.
 * - POSIX threads and semaphores for concurrency.
 * - GLib for configuration file handling.
 * - Custom hardware libraries (saturntypes.h, hwaccess.h, etc.).
 * - Device files (/dev/xdma0_user, /dev/xdma0_h2c_0, /dev/xdma0_c2h_0).
 *
 * Compilation:
 *   make clean
 *   make
 */

#include <gtk/gtk.h>
#include <glib.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h> // For usleep and waitpid
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/poll.h>
#include <math.h>   // For M_PI
#include <time.h>

// Fallback declaration for waitpid if unistd.h fails
pid_t waitpid(pid_t pid, int *status, int options);

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
#define SAMPLE_WORDS_PER_DMA 256          // Number of 16-bit samples per DMA
#define DMA_WORDS_PER_DMA 128             // Number of 8-byte words per DMA
#define DMA_TRANSFERS (TOTAL_SAMPLES * 4) / DMA_TRANSFER_SIZE // Total DMA transfers
#define DMA_DISP_UPDATE 12                // Number of DMAs before UI update
#define AXI_BASE_ADDRESS 0x40000L         // Base address of StreamRead/Writer IP
#define AXI_FNAME "/dev/xdma0_user"       // PCIe device driver path for AXI-lite access
#define MIC_STATUS_IDLE "Idle"            // Status label for idle state
#define MIC_STATUS_RECORDING "Speak Now"  // Status label for recording
#define MIC_STATUS_PLAYING "Playing"      // Status label for playback
#define MIN_UPDATE_INTERVAL 100000000     // Minimum 100ms between UI updates (in ns)
#define OVERLOAD_LATCH_NS 500000000       // 0.5s latch for overload indicator (in ns)
#define CIRCULAR_BUFFER_SIZE 24           // Buffer for 250ms of DMA peak levels (~10.67ms per DMA)

// Circular buffer for peak levels
static float peak_buffer[CIRCULAR_BUFFER_SIZE];
static int peak_buffer_index = 0;

// Global volume variable to store the slider value
static volatile double global_volume = 0.1;
static pthread_mutex_t volume_mutex = PTHREAD_MUTEX_INITIALIZER;

// Application context for GUI elements
typedef struct
{
    GtkWidget *window;               // Main application window
    GtkStatusbar *status_bar;        // Status bar for general messages
    GtkTextBuffer *text_buffer;      // Text buffer for log messages
    GtkLabel *mic_activity_label;    // Label for microphone status
    GtkLabel *ptt_label;             // Label for PTT status
    GtkProgressBar *mic_progress_bar; // Progress bar for test progress
    GtkProgressBar *mic_level_bar;   // Progress bar for mic signal level
    GtkRange *volume_scale;          // Slider for speaker test volume
    GtkSpinButton *mic_duration_spin; // Spin button for mic test duration
    GtkSpinButton *gain_spin;        // Spin button for line gain
    GtkScale *mic_gain_scale;        // Slider for mic gain
    GtkAdjustment *vol_adjustment;   // Adjustment for volume scale
    GtkAdjustment *gain_adjustment;  // Adjustment for line gain spin button
    GtkAdjustment *mic_gain_adjustment; // Adjustment for mic gain slider
    GtkToggleButton *mic_boost_check; // Checkbox for mic boost
    GtkToggleButton *mic_xlr_check;  // Checkbox for XLR input
    GtkToggleButton *mic_tip_check;  // Checkbox for mic tip/ring
    GtkToggleButton *mic_bias_check; // Checkbox for mic bias
    GtkToggleButton *line_check;     // Checkbox for line input
    GtkLabel *overload_label;        // Label for overload indicator
    GtkLabel *near_peak_label;       // Label for near-peak indicator
} AppContext;

// Audio context for hardware and buffer management
typedef struct
{
    char *write_buffer;              // Buffer for DMA writes to codec
    char *read_buffer;               // Buffer for DMA reads from codec
    int dma_write_fd;                // File descriptor for DMA write device
    int dma_read_fd;                 // File descriptor for DMA read device
    uint32_t buffer_size;            // Size of DMA buffers
    bool mic_test_initiated;         // Flag to start microphone test
    bool speaker_test_initiated;     // Flag to start speaker test
    bool speaker_test_is_left_channel; // True for left channel speaker test
    pthread_mutex_t mic_test_mutex;  // Mutex for mic_test_initiated
    pthread_mutex_t speaker_test_mutex; // Mutex for speaker_test_mutex
    AppContext *AppPtr;              // Pointer to app context for event handlers
} AudioContext;

// Global synchronization primitives
extern sem_t DDCInSelMutex;                 // Protects DDC input select register
extern sem_t DDCResetFIFOMutex;             // Protects FIFO reset register
extern sem_t RFGPIOMutex;                   // Protects RF GPIO register
extern sem_t CodecRegMutex;                 // Protects codec register writes
volatile bool keep_running = true;           // Flag to control thread termination
static bool hardware_available = true;       // Flag to indicate hardware availability

// Function prototypes
static void on_MicSettings_Changed(GtkToggleButton *button, AudioContext *audio);
void on_close_button_clicked(GtkButton *button, AppContext *app);
static void on_volume_changed(GtkRange *range, gpointer user_data);
static void load_gains(AppContext *app);
static void save_gains(AppContext *app);

// Function to load the input gains from the configuration file
static void load_gains(AppContext *app)
{
    GKeyFile *keyfile = g_key_file_new();
    gchar *filename = g_build_filename(g_get_home_dir(), ".audiotestrc", NULL);
    if (g_key_file_load_from_file(keyfile, filename, G_KEY_FILE_NONE, NULL))
    {
        if (g_key_file_has_key(keyfile, "audiotest", "line_gain", NULL))
        {
            gdouble gain = g_key_file_get_double(keyfile, "audiotest", "line_gain", NULL);
            if (app->gain_spin) {
                gtk_spin_button_set_value(app->gain_spin, gain);
                printf("Loaded line gain: %.1f dB\n", gain);
            }
        }
        else
        {
            if (app->gain_spin) {
                gtk_spin_button_set_value(app->gain_spin, 0.0); // Default line gain
                printf("No saved line gain, using default: 0.0 dB\n");
            }
        }
        if (g_key_file_has_key(keyfile, "audiotest", "mic_gain", NULL))
        {
            gdouble gain = g_key_file_get_double(keyfile, "audiotest", "mic_gain", NULL);
            if (app->mic_gain_scale) {
                gtk_range_set_value((GtkRange *)app->mic_gain_scale, gain);
                printf("Loaded mic gain: %.1f dB\n", gain);
            }
        }
        else
        {
            if (app->mic_gain_scale) {
                gtk_range_set_value((GtkRange *)app->mic_gain_scale, 0.0); // Default mic gain
                printf("No saved mic gain, using default: 0.0 dB\n");
            }
        }
    }
    else
    {
        if (app->gain_spin) {
            gtk_spin_button_set_value(app->gain_spin, 0.0); // Default line gain
        }
        if (app->mic_gain_scale) {
            gtk_range_set_value((GtkRange *)app->mic_gain_scale, 0.0); // Default mic gain
        }
        printf("No config file found, using default gains: 0.0 dB\n");
    }
    g_free(filename);
    g_key_file_free(keyfile);
}

// Function to save the input gains to the configuration file
static void save_gains(AppContext *app)
{
    GKeyFile *keyfile = g_key_file_new();
    gdouble line_gain = app->gain_spin ? gtk_spin_button_get_value(app->gain_spin) : 0.0;
    gdouble mic_gain = app->mic_gain_scale ? gtk_range_get_value((GtkRange *)app->mic_gain_scale) : 0.0;
    g_key_file_set_double(keyfile, "audiotest", "line_gain", line_gain);
    g_key_file_set_double(keyfile, "audiotest", "mic_gain", mic_gain);
    gchar *filename = g_build_filename(g_get_home_dir(), ".audiotestrc", NULL);
    if (!g_key_file_save_to_file(keyfile, filename, NULL))
    {
        fprintf(stderr, "Failed to save config file\n");
    }
    else
    {
        printf("Saved line gain: %.1f dB, mic gain: %.1f dB\n", line_gain, mic_gain);
    }
    g_free(filename);
    g_key_file_free(keyfile);
}

// Callback for when the line gain spin button value changes
static void on_line_gain_changed(GtkSpinButton *spin_button, AudioContext *audio)
{
    AppContext *app = audio->AppPtr;
    save_gains(app);
    on_MicSettings_Changed(NULL, audio);
}

// Callback for when the mic gain slider value changes
static void on_mic_gain_changed(GtkRange *range, AudioContext *audio)
{
    AppContext *app = audio->AppPtr;
    double new_gain = gtk_range_get_value(range);
    save_gains(app);
    printf("Mic gain changed to: %.1f dB\n", new_gain); // Debug mic gain
    on_MicSettings_Changed(NULL, audio);
}

// Callback for when the volume slider value changes
static void on_volume_changed(GtkRange *range, gpointer user_data)
{
    double new_volume = gtk_range_get_value(range) / 100.0; // Normalize to 0.0-1.0, scaled to 0.0-2.0 for testing
    pthread_mutex_lock(&volume_mutex);
    global_volume = new_volume * 2.0; // Increase range to test hardware response
    pthread_mutex_unlock(&volume_mutex);
    printf("Volume set to: %.2f (scaled to %.2f)\n", new_volume, global_volume);
}

// Callback for the Close button
void on_close_button_clicked(GtkButton *button, AppContext *app)
{
    save_gains(app);
    gtk_main_quit();
}

/*
 * check_background_apps: Checks for running instances of p2app or piHPSDR and warns user.
 * @param parent: Parent window for the dialog (can be NULL).
 * @return: true if conflicting apps are running, false otherwise.
 */
static bool check_background_apps(GtkWidget *parent)
{
    FILE *fp;
    char buffer[128];
    bool conflict_found = false;
    const char *apps[] = {"p2app", "piHPSDR"};
    int num_apps = sizeof(apps) / sizeof(apps[0]);

    for (int i = 0; i < num_apps; i++) {
        char cmd[64];
        snprintf(cmd, sizeof(cmd), "pidof %s", apps[i]);
        fp = popen(cmd, "r");
        if (fp == NULL) {
            fprintf(stderr, "Failed to run pidof for %s: %s\n", apps[i], strerror(errno));
            continue;
        }

        if (fgets(buffer, sizeof(buffer), fp) != NULL) {
            conflict_found = true;
            if (parent) {
                GtkWidget *dialog = gtk_message_dialog_new(
                    GTK_WINDOW(parent),
                    GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
                    GTK_MESSAGE_WARNING,
                    GTK_BUTTONS_OK,
                    "Warning: %s is running in the background!\n"
                    "This will cause audio issues due to byte swapping. "
                    "Please terminate %s before continuing.",
                    apps[i], apps[i]
                );
                gtk_window_set_title(GTK_WINDOW(dialog), "Background Application Conflict");
                gtk_dialog_run(GTK_DIALOG(dialog));
                gtk_widget_destroy(dialog);
            } else {
                fprintf(stderr, "Warning: %s is running in the background!\n", apps[i]);
            }
        }
        pclose(fp);
    }
    return conflict_found;
}

/*
 * HandlerSetEERMode: Placeholder callback for EER mode setting.
 * @param Unused: Boolean parameter (not used in this implementation).
 */
void HandlerSetEERMode(bool Unused)
{
    // Stub implementation to satisfy linker dependency
}

/*
 * cleanup: Frees allocated resources and closes file descriptors.
 * @param app: Pointer to application context.
 * @param audio: Pointer to audio context.
 */
void cleanup(AppContext *app, AudioContext *audio)
{
    keep_running = false;
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
    pthread_mutex_destroy(&volume_mutex);
}

/*
 * set_mic_test_initiated: Thread-safe setting of mic test flag.
 * @param audio: Pointer to audio context.
 * @param value: New value for mic_test_initiated.
 */
void set_mic_test_initiated(AudioContext *audio, bool value)
{
    pthread_mutex_lock(&audio->mic_test_mutex);
    audio->mic_test_initiated = value;
    pthread_mutex_unlock(&audio->mic_test_mutex);
}

/*
 * get_mic_test_initiated: Thread-safe retrieval of mic test flag.
 * @param audio: Pointer to audio context.
 * @return: Current value of mic_test_initiated.
 */
bool get_mic_test_initiated(AudioContext *audio)
{
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
void set_speaker_test_initiated(AudioContext *audio, bool value, bool is_left)
{
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
void get_speaker_test_initiated(AudioContext *audio, bool *value, bool *is_left)
{
    pthread_mutex_lock(&audio->speaker_test_mutex);
    *value = audio->speaker_test_initiated;
    *is_left = audio->speaker_test_is_left_channel;
    pthread_mutex_unlock(&audio->speaker_test_mutex);
}

/*
 * update_progress_bars: Updates progress, level bars, and indicators in the GTK main thread.
 * @param user_data: Pointer to ProgressUpdateData.
 * @return: G_SOURCE_REMOVE to remove the idle callback.
 */
typedef struct
{
    GtkProgressBar *progress_bar; // Target progress bar
    GtkProgressBar *level_bar;    // Target level bar
    GtkLabel *overload_label;     // Overload indicator label
    GtkLabel *near_peak_label;    // Near-peak indicator label
    float progress_fraction;      // Fraction for progress bar (0.0 to 1.0)
    float level_fraction;         // Fraction for level bar (0.0 to 1.0)
    float overload_dbfs;          // dBFS value for overload (or 0 if inactive)
    bool overload;                // true if there is an overload
    float near_peak_dbfs;         // dBFS value for near-peak (or 0 if inactive)
} ProgressUpdateData;

static gboolean update_progress_bars(gpointer user_data)
{
    ProgressUpdateData *data = (ProgressUpdateData *)user_data;
    if (data->progress_bar) 
        gtk_progress_bar_set_fraction(data->progress_bar, data->progress_fraction);
    if (data->level_bar)
        gtk_progress_bar_set_fraction(data->level_bar, data->level_fraction);

    // Update overload indicator
    if (data->overload_label) 
    {
        if (data->overload)
        { // Near or above 0 dBFS
            char label_text[32];
//            snprintf(label_text, sizeof(label_text), "Overload: %.1f dBFS", data->overload_dbfs);
            gtk_label_set_text(data->overload_label, "!! Overload !!");
            gtk_widget_set_name((GtkWidget *)data->overload_label, "overload-on");
        }
        else
        {
            gtk_label_set_text(data->overload_label, "(no overload)");
            gtk_widget_set_name((GtkWidget *)data->overload_label, "overload-off");
        }
    }

    // Update near-peak indicator
    if (data->near_peak_label) 
    {
        if (data->near_peak_dbfs > -10.0 && data->near_peak_dbfs < -0.01) 
        {
            char label_text[32];
            snprintf(label_text, sizeof(label_text), "Near Peak: %.1f dBFS", data->near_peak_dbfs);
            gtk_label_set_text(data->near_peak_label, label_text);
            gtk_widget_set_name((GtkWidget *)data->near_peak_label, "near-peak-on");
        }
        else
        {
            gtk_label_set_text(data->near_peak_label, "Near Peak: Idle");
            gtk_widget_set_name((GtkWidget *)data->near_peak_label, "near-peak-off");
        }
    }

    g_free(data);
    return G_SOURCE_REMOVE;
}

/*
 * reset_overload_latch: Resets the overload indicator after 0.5s.
 * @param user_data: Pointer to AppContext.
 * @return: G_SOURCE_REMOVE to remove the timeout callback.
 */
static gboolean reset_overload_latch(gpointer user_data)
{
    AppContext *app = (AppContext *)user_data;
    ProgressUpdateData *data = g_new(ProgressUpdateData, 1);
    data->progress_bar = app->mic_progress_bar;
    data->level_bar = app->mic_level_bar;
    data->overload_label = app->overload_label;
    data->near_peak_label = app->near_peak_label;
    data->progress_fraction = app->mic_progress_bar ? gtk_progress_bar_get_fraction(app->mic_progress_bar) : 0.0;
    data->level_fraction = app->mic_level_bar ? gtk_progress_bar_get_fraction(app->mic_level_bar) : 0.0;
    data->overload_dbfs = 0.0; // Reset to inactive
    data->near_peak_dbfs = app->near_peak_label && gtk_label_get_text(app->near_peak_label)[11] == ':' ? 0.0 : atof(gtk_label_get_text(app->near_peak_label) + 12); // Preserve near-peak if active
    g_idle_add(update_progress_bars, data);
    return G_SOURCE_REMOVE;
}

/*
 * MyStatusCallback: Updates progress bars and indicators for test progress and input level.
 * @param app: Pointer to application context.
 * @param ProgressPercent: Percentage of test completion (0 to 100).
 * @param LevelPercent: Input signal level percentage (0 to 100).
 * @param dBFS: Peak signal level in dBFS.
 * @param Overload: True if signal exceeds 0 dBFS.
 * @param NearPeak: True if signal is within -6 dB or -10 dB of peak.
 */
static void MyStatusCallback(AppContext *app, float ProgressPercent, float LevelPercent, float dBFS, bool Overload, bool NearPeak)
{
    if (!hardware_available) return; // Skip if hardware is unavailable
    ProgressUpdateData *data = g_new(ProgressUpdateData, 1);
    data->progress_bar = app->mic_progress_bar;
    data->level_bar = app->mic_level_bar;
    data->overload_label = app->overload_label;
    data->near_peak_label = app->near_peak_label;
    data->progress_fraction = ProgressPercent / 100.0;

    // Convert LevelPercent to dBFS and scale to 0-1 for level bar
    LevelPercent = (LevelPercent < 0.0) ? 0.0 : (LevelPercent > 100.0) ? 100.0 : LevelPercent;
    dBFS = (dBFS > 0.0) ? 0.0 : (dBFS < -60.0) ? -60.0 : dBFS;
    data->level_fraction = 1.0 + (dBFS / 60.0); // Normalize to 0-1
    data->overload = Overload;
    data->overload_dbfs = Overload ? dBFS : 0.0;
    data->near_peak_dbfs = NearPeak ? dBFS : 0.0;

    g_idle_add(update_progress_bars, data);

    // Set 0.5s latch for overload
    if (Overload) {
        g_timeout_add(500, reset_overload_latch, app);
    }
}

/*
 * CreateSpkTestData: Generates sinewave test data for speaker output.
 */
void CreateSpkTestData(char *MemPtr, uint32_t Samples, float StartFreq, float FreqRamp, float Amplitude, bool IsL)
{
    if (!hardware_available) return; // Skip if hardware is unavailable
    uint32_t *Data = (uint32_t *)MemPtr;
    double Ampl = 32767.0 * Amplitude;
    printf("CreateSpkTestData using Amplitude: %.2f (scaled to %.2f)\n", Amplitude, Ampl); // Debug amplitude
    double Phase = 0.0;
    double PhaseIncrement;
    float Freq = StartFreq;
    uint16_t ZeroWord = 0;

    for (uint32_t Cntr = 0; Cntr < Samples; Cntr++)
    {
        Freq = StartFreq + FreqRamp * (float)Cntr / Samples;
        PhaseIncrement = 2.0 * M_PI * Freq / SAMPLE_RATE;
        Phase += PhaseIncrement;
        int16_t Word = (int16_t)(Ampl * sin(Phase));
        uint32_t TwoWords = IsL ? ((ZeroWord << 16) | (uint16_t)Word) : (((uint16_t)Word << 16) | ZeroWord);
        *Data++ = TwoWords;
    }
}

/*
 * DMAWriteToCodec: Writes data to codec via DMA.
 */
void DMAWriteToCodec(AudioContext *audio, char *MemPtr, uint32_t Length)
{
    if (!hardware_available) return; // Skip if hardware is unavailable
    uint32_t Depth = 0, Spare;
    bool FIFOOverflow, OverThreshold, Underflow;
    uint32_t DMACount, TotalDMACount = Length / DMA_TRANSFER_SIZE;
    struct pollfd pfd = { .fd = audio->dma_write_fd, .events = POLLOUT };

    printf("DMAWriteToCodec: Starting %u transfers\n", TotalDMACount);
    for (DMACount = 0; DMACount < TotalDMACount; DMACount++)
    {
        Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow, &OverThreshold, &Underflow, &Spare);
        while (Depth < DMA_WORDS_PER_DMA)
        {
            if (poll(&pfd, 1, 1000) < 0)
            {
                fprintf(stderr, "Poll error on DMA write: %s\n", strerror(errno));
                break;
            }
            Depth = ReadFIFOMonitorChannel(eSpkCodecDMA, &FIFOOverflow, &OverThreshold, &Underflow, &Spare);
        }
        if (DMAWriteToFPGA(audio->dma_write_fd, (unsigned char *)MemPtr, DMA_TRANSFER_SIZE, AXI_BASE_ADDRESS) < 0)
            fprintf(stderr, "DMAWriteToFPGA failed at transfer %u\n", DMACount);
//        else
//            printf("DMAWriteToCodec: Completed transfer %u\n", DMACount);
        MemPtr += DMA_TRANSFER_SIZE;
    }
    printf("DMAWriteToCodec: Finished %u transfers\n", TotalDMACount);
    usleep(10000);
}

/*
 * CopyMicToSpeaker: Copies microphone data to speaker buffer (dual mono).
 */
void CopyMicToSpeaker(char *Read, char *Write, uint32_t Length)
{
    if (!hardware_available) return; // Skip if hardware is unavailable
    uint32_t *WritePtr = (uint32_t *)Write;
    uint16_t *ReadPtr = (uint16_t *)Read;

    for (uint32_t Cntr = 0; Cntr < Length / 2; Cntr++)
    {
        uint16_t Sample = *ReadPtr++;
        uint32_t TwoSamples = (uint32_t)Sample;
        TwoSamples = (TwoSamples << 16) | TwoSamples;
        *WritePtr++ = TwoSamples;
    }
}

/*
 * DMAReadFromCodec: Reads data from codec via DMA and updates UI.
 */
void DMAReadFromCodec(AppContext *app, AudioContext *audio, char *MemPtr, uint32_t Length)
{
    if (!hardware_available) return; // Skip if hardware is unavailable
    uint32_t Depth = 0, Spare;
    bool FIFOOverflow, OverThreshold, Underflow;
    uint32_t DMACount, TotalDMACount = Length / DMA_TRANSFER_SIZE;
    int16_t *MicReadPtr = (int16_t *)MemPtr;
    float PeakLevel = 0.0;
    float PeakdBFS = -60.0;
    bool Overload = false;
    bool NearPeak = false;
    const float NEAR_PEAK_10DB = 100.0 * pow(10.0, -10.0 / 20.0); // ~31.62%
    struct pollfd pfd = { .fd = audio->dma_read_fd, .events = POLLIN };
    struct timespec last_update = {0, 0};

    printf("DMAReadFromCodec: Starting %u transfers\n", TotalDMACount);
    for (DMACount = 0; DMACount < TotalDMACount; DMACount++)
    {
        Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow, &OverThreshold, &Underflow, &Spare);
        while (Depth < DMA_WORDS_PER_DMA)
        {
            if (poll(&pfd, 1, 1000) < 0)
            {
                fprintf(stderr, "Poll error on DMA read: %s\n", strerror(errno));
                break;
            }
            Depth = ReadFIFOMonitorChannel(eMicCodecDMA, &FIFOOverflow, &OverThreshold, &Underflow, &Spare);
        }
        if (DMAReadFromFPGA(audio->dma_read_fd, (unsigned char *)MemPtr, DMA_TRANSFER_SIZE, AXI_BASE_ADDRESS) < 0)
            fprintf(stderr, "DMAReadFromFPGA failed at transfer %u\n", DMACount);
//        else
//            printf("DMAReadFromCodec: Completed transfer %u\n", DMACount);

        // find max sample level in the recent DMA transfer
        PeakLevel = 0.0;
        for (uint32_t SampleCntr = 0; SampleCntr < DMA_TRANSFER_SIZE / 2; SampleCntr++)
        {
            int MicSample = *MicReadPtr++;
//            float SampleLevel = (float)abs(MicSample) / 32767.0 * 100.0;
            float SampleLevel = fabs((float)MicSample) / 32768.0 * 100.0;   // 0 to 100. (mic sample can be -32768 to +32767)
            if (SampleLevel > PeakLevel) 
            {
                PeakLevel = SampleLevel;
            }
            if (SampleLevel > 99.5) 
            {
                Overload = true;
                printf("Overload detected: SampleLevel=%.2f%%\n", SampleLevel);
            }
            if (SampleLevel >= NEAR_PEAK_10DB && SampleLevel < 99.5) NearPeak = true;
        }
        peak_buffer[peak_buffer_index] = PeakLevel;
        peak_buffer_index = (peak_buffer_index + 1) % CIRCULAR_BUFFER_SIZE;
        MemPtr += DMA_TRANSFER_SIZE;

        if (DMACount % DMA_DISP_UPDATE == 0)
        {
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            long long elapsed_ns = (now.tv_sec - last_update.tv_sec) * 1000000000LL + (now.tv_nsec - last_update.tv_nsec);
            if (elapsed_ns >= MIN_UPDATE_INTERVAL || DMACount == TotalDMACount - 1)
            {
                // Find max peak level in circular buffer
                float MaxPeakLevel = 0.0;
                for (int i = 0; i < CIRCULAR_BUFFER_SIZE; i++) 
                {
                    if (peak_buffer[i] > MaxPeakLevel) 
                        MaxPeakLevel = peak_buffer[i];
                }
                PeakdBFS = 20.0 * log10(MaxPeakLevel / 100.0 + 1e-6);   // min = -60dBFS
                float ProgressFraction = 100.0 * (float)DMACount / TotalDMACount;
                MyStatusCallback(app, ProgressFraction, MaxPeakLevel, PeakdBFS, Overload, NearPeak);
                last_update = now;
                Overload = false; // Reset after update (latch handled by timer)
                NearPeak = MaxPeakLevel >= NEAR_PEAK_10DB; // Persist near-peak based on max peak
            }
        }
    }
    printf("DMAReadFromCodec: Finished %u transfers\n", TotalDMACount);
    MyStatusCallback(app, 100.0, 0.0, -60.0, false, false);
}

/*
 * on_testL_button_clicked: Handler for left speaker test button.
 */
void on_testL_button_clicked(GtkButton *button, AudioContext *audio)
{
    if (!hardware_available) {
        g_print("Speaker test disabled: hardware unavailable\n");
        return;
    }
    set_speaker_test_initiated(audio, true, true);
}

/*
 * on_testR_button_clicked: Handler for right speaker test button.
 */
void on_testR_button_clicked(GtkButton *button, AudioContext *audio)
{
    if (!hardware_available) {
        g_print("Speaker test disabled: hardware unavailable\n");
        return;
    }
    set_speaker_test_initiated(audio, true, false);
}

/*
 * on_MicSettings_Changed: Updates input settings based on GUI toggles and gains.
 */
static void on_MicSettings_Changed(GtkToggleButton *button, AudioContext *audio)
{
    printf("Entering on_MicSettings_Changed, hardware_available = %d\n", hardware_available);
    if (!hardware_available) {
        g_print("Input settings update disabled: hardware unavailable\n");
        return;
    }
    AppContext *app = audio->AppPtr;
    gboolean XLR = app->mic_xlr_check ? gtk_toggle_button_get_active(app->mic_xlr_check) : false;
    gboolean MicBoost = app->mic_boost_check ? gtk_toggle_button_get_active(app->mic_boost_check) : false;
    gboolean MicTip = app->mic_tip_check ? gtk_toggle_button_get_active(app->mic_tip_check) : false;
    gboolean MicBias = app->mic_bias_check ? gtk_toggle_button_get_active(app->mic_bias_check) : false;
    gboolean LineInput = app->line_check ? gtk_toggle_button_get_active(app->line_check) : false;
    double Gain = LineInput ? (app->gain_spin ? gtk_spin_button_get_value(app->gain_spin) : 0.0) : 
                            (app->mic_gain_scale ? gtk_range_get_value((GtkRange *)app->mic_gain_scale) : 0.0);
    uint32_t IntGain = (uint32_t)((Gain + 34.5) / 1.5);
    printf("Before SetCodecLineInGain: Setting mic/line gain to: %.1f dB (IntGain: %u)\n", Gain, IntGain); // Debug

    pid_t pid = fork();
    if (pid == 0) 
    { // Child process
        SetOrionMicOptions(!MicTip, MicBias, true);
        SetMicBoost(MicBoost);
        SetBalancedMicInput(XLR);
        SetMicLineInput(LineInput);
        for (int attempt = 0; attempt < 5; attempt++) 
        {
            SetCodecLineInGain(IntGain);
            usleep(100000); // 100ms delay
            uint32_t regValue = RegisterRead(VADDRCODECSPIREG);
            printf("Child process: Attempt %d, Read codec register value: 0x%08x (IntGain expected: %u)\n", attempt + 1, regValue, IntGain);
            if ((regValue & 0x01FF) == IntGain) break; // Check lower 9 bits
        }
        exit(0); // Exit child after setting gain
    } 
    else if (pid > 0) 
    { // Parent process
        int status;
        alarm(1); // Set a 1-second alarm to kill the child if it hangs
        waitpid(pid, &status, 0); // Wait for child to finish
        alarm(0); // Cancel alarm
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) 
        {
            printf("SetCodecLineInGain succeeded via child process\n");
        }
        else
        {
            fprintf(stderr, "SetCodecLineInGain failed in child process\n");
            hardware_available = false; // Disable hardware on failure
        }
    }
    else
    {
        fprintf(stderr, "Fork failed: %s\n", strerror(errno));
        hardware_available = false; // Disable hardware on fork failure
    }

    printf("After SetCodecLineInGain\n"); // Debug
}

/*
 * on_MicTestButton_clicked: Initiates microphone test.
 */
void on_MicTestButton_clicked(GtkButton *button, AudioContext *audio)
{
    if (!hardware_available) 
    {
        g_print("Mic test disabled: hardware unavailable\n");
        return;
    }
    printf("MicTestButton clicked, setting mic_test_initiated to true\n");
    set_mic_test_initiated(audio, true);
}

/*
 * on_window_main_destroy: Cleans up and exits on window close.
 */
void on_window_main_destroy(GtkWidget *widget, AppContext *app)
{
    save_gains(app);
    gtk_main_quit();
}

/*
 * MicTest: Thread to handle microphone record and playback.
 */
void *MicTest(void *arg)
{
    AppContext *app = ((void **)arg)[0];
    AudioContext *audio = ((void **)arg)[1];

    while (keep_running)
    {
        usleep(50000);
        if (get_mic_test_initiated(audio))
        {
            printf("MicTest: Starting microphone test\n");
            if (!hardware_available) {
                g_print("Mic test skipped: hardware unavailable\n");
                if (app->mic_activity_label) 
                {
                    gtk_label_set_text(app->mic_activity_label, MIC_STATUS_IDLE);
                }
                set_mic_test_initiated(audio, false);
                continue;
            }
            // Reset circular buffer
            for (int i = 0; i < CIRCULAR_BUFFER_SIZE; i++) 
            {
                peak_buffer[i] = 0.0;
            }
            peak_buffer_index = 0;

            ProgressUpdateData *data = g_new(ProgressUpdateData, 1);
            data->progress_bar = app->mic_progress_bar;
            data->level_bar = app->mic_level_bar;
            data->overload_label = app->overload_label;
            data->near_peak_label = app->near_peak_label;
            data->progress_fraction = 0.0;
            data->level_fraction = 0.0;
            data->overload_dbfs = 0.0;
            data->near_peak_dbfs = 0.0;
            g_idle_add(update_progress_bars, data);

            double Gain = app->line_check ? 
                          (app->gain_spin ? gtk_spin_button_get_value(app->gain_spin) : 0.0) : 
                          (app->mic_gain_scale ? gtk_range_get_value((GtkRange *)app->mic_gain_scale) : 0.0);
            uint32_t IntGain = (uint32_t)((Gain + 34.5) / 1.5);
            SetCodecLineInGain(IntGain);

            if (app->mic_activity_label) 
            {
                gtk_label_set_text(app->mic_activity_label, MIC_STATUS_RECORDING);
            }
            gint Duration = app->mic_duration_spin ? gtk_spin_button_get_value_as_int(app->mic_duration_spin) : 5;
            uint32_t Samples = SAMPLE_RATE * Duration;
            uint32_t Length = Samples * 2;
            ResetDMAStreamFIFO(eMicCodecDMA);
            DMAReadFromCodec(app, audio, audio->read_buffer, Length);
            CopyMicToSpeaker(audio->read_buffer, audio->write_buffer, Length);

            if (app->mic_activity_label) 
            {
                gtk_label_set_text(app->mic_activity_label, MIC_STATUS_PLAYING);
            }
            Length = Samples * 4;
            usleep(1000);
            DMAWriteToCodec(audio, audio->write_buffer, Length);
            if (app->mic_activity_label) 
            {
                gtk_label_set_text(app->mic_activity_label, MIC_STATUS_IDLE);
            }
            set_mic_test_initiated(audio, false);
            printf("MicTest: Completed microphone test\n");
        }
    }
    return NULL;
}

/*
 * SpeakerTest: Thread to handle speaker test with sinewave output.
 */
void *SpeakerTest(void *arg)
{
    AppContext *app = ((void **)arg)[0];
    AudioContext *audio = ((void **)arg)[1];

    while (keep_running)
    {
        bool initiated, is_left;
        get_speaker_test_initiated(audio, &initiated, &is_left);
        if (initiated)
        {
            if (!hardware_available) 
            {
                g_print("Speaker test skipped: hardware unavailable\n");
                if (app->text_buffer) 
                {
                    gtk_text_buffer_insert_at_cursor(app->text_buffer, "Speaker test skipped: hardware unavailable\n", -1);
                }
                set_speaker_test_initiated(audio, false, is_left);
                continue;
            }
            double Ampl;
            pthread_mutex_lock(&volume_mutex);
            Ampl = global_volume; // Read current volume
            pthread_mutex_unlock(&volume_mutex);
            printf("SpeakerTest using volume: %.2f\n", Ampl); // Debug output
            float Freq = is_left ? 400.0 : 1000.0;
            float FreqRamp = 0.0;
            ResetDMAStreamFIFO(eSpkCodecDMA); // Ensure FIFO is reset for new volume
            CreateSpkTestData(audio->write_buffer, SPK_SAMPLES, Freq, FreqRamp, Ampl, is_left);
            uint32_t Length = SPK_SAMPLES * 4;
            if (app->text_buffer) 
            {
                gtk_text_buffer_insert_at_cursor(app->text_buffer, "Playing sinewave tone via DMA\n", -1);
                printf("SpeakerTest: Text buffer updated with playback message\n");
            }
            uint32_t regMute = RegisterRead(VADDRCODECSPIREG); // Temporary substitute for VADDRSPKRMUTE
            printf("Speaker mute register value: 0x%08x (0 = unmuted, check codec control bits)\n", regMute);
            DMAWriteToCodec(audio, audio->write_buffer, Length);
            set_speaker_test_initiated(audio, false, is_left);
            usleep(50000);
        }
    }
    return NULL;
}

/*
 * CheckForPttPressed: Thread to monitor PTT input status.
 */
void *CheckForPttPressed(void *arg)
{
    AppContext *app = (AppContext *)arg;
    bool PTTPressed = false;

    while (keep_running)
    {
        usleep(50000);
        if (!hardware_available) 
        {
            if (app->ptt_label) 
            {
                gtk_label_set_text(app->ptt_label, "PTT: Hardware unavailable");
            }
            continue;
        }
        ReadStatusRegister();
        bool Pressed = GetPTTInput();
        if (Pressed != PTTPressed)
        {
            PTTPressed = Pressed;
            if (app->ptt_label) 
            {
                gtk_label_set_text(app->ptt_label, Pressed ? "PTT Pressed" : "PTT Released");
            }
        }
    }
    return NULL;
}

/*
 * main: Initializes the application and runs the GTK main loop.
 */
int main(int argc, char *argv[])
{
    AppContext app = {0};
    AudioContext audio = {0};
    audio.buffer_size = MEM_BUFFER_SIZE;
    pthread_t ptt_thread, mic_test_thread, speaker_test_thread;
    void *thread_args[2] = {&app, &audio};

    // Initialize circular buffer
    for (int i = 0; i < CIRCULAR_BUFFER_SIZE; i++) 
    {
        peak_buffer[i] = 0.0;
    }

    gtk_init(&argc, &argv);

    // Load CSS for indicators and controls
    GtkCssProvider *css_provider = gtk_css_provider_new();
    const gchar *css_data =
        ".overload-on { background-color: red; color: white; font-weight: bold; }\n"
        ".overload-off { background-color: transparent; color: black; }\n"
        ".near-peak-on { background-color: yellow; color: black; font-weight: bold; }\n"
        ".near-peak-off { background-color: transparent; color: black; }\n"
        ".line-gain-spin { background-color: blue; }\n"
        ".mic-gain-slider { background-color: cyan; }\n"
        ".volume-slider { background-color: green; }";
    GError *error = NULL;
    if (!gtk_css_provider_load_from_data(css_provider, css_data, -1, &error)) 
    {
        fprintf(stderr, "Failed to load CSS: %s\n", error->message);
        g_error_free(error);
        g_object_unref(css_provider);
        return EXIT_FAILURE;
    }
    gtk_style_context_add_provider_for_screen(
        gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(css_provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION
    );
    g_object_unref(css_provider);

    if (check_background_apps(NULL)) 
    {
        fprintf(stderr, "Warning: Conflicting applications detected\n");
    }

    GError *ui_error = NULL;
    GtkBuilder *builder = gtk_builder_new();
    if (!gtk_builder_add_from_file(builder, "audiotest.ui", &ui_error)) 
    {
        fprintf(stderr, "Failed to load audiotest.ui: %s\n", ui_error->message);
        g_error_free(ui_error);
        g_object_unref(builder);
        return EXIT_FAILURE;
    }
    audio.AppPtr = &app;

    app.window = GTK_WIDGET(gtk_builder_get_object(builder, "window_main"));
    if (!app.window) fprintf(stderr, "Failed to load window_main widget\n");
    app.status_bar = GTK_STATUSBAR(gtk_builder_get_object(builder, "statusbar_main"));
    if (!app.status_bar) fprintf(stderr, "Failed to load statusbar_main widget\n");
    app.text_buffer = GTK_TEXT_BUFFER(gtk_builder_get_object(builder, "textbuffer_main"));
    if (!app.text_buffer) fprintf(stderr, "Failed to load textbuffer_main widget\n");
    app.mic_activity_label = GTK_LABEL(gtk_builder_get_object(builder, "MicActivityLabel"));
    if (!app.mic_activity_label) fprintf(stderr, "Failed to load MicActivityLabel widget\n");
    app.ptt_label = GTK_LABEL(gtk_builder_get_object(builder, "PTTLabel"));
    if (!app.ptt_label) fprintf(stderr, "Failed to load PTTLabel widget\n");
    app.mic_progress_bar = GTK_PROGRESS_BAR(gtk_builder_get_object(builder, "id_progress"));
    if (!app.mic_progress_bar) fprintf(stderr, "Failed to load id_progress widget\n");
    app.mic_level_bar = GTK_PROGRESS_BAR(gtk_builder_get_object(builder, "MicLevelBar"));
    if (!app.mic_level_bar) fprintf(stderr, "Failed to load MicLevelBar widget\n");
    app.volume_scale = GTK_RANGE(gtk_builder_get_object(builder, "VolumeScale"));
    if (!app.volume_scale) 
    {
        fprintf(stderr, "Failed to load VolumeScale widget, volume control disabled\n");
    }
    else 
    {
        printf("VolumeScale loaded successfully\n");
    }
    app.mic_duration_spin = GTK_SPIN_BUTTON(gtk_builder_get_object(builder, "MicDurationSpin"));
    if (!app.mic_duration_spin) fprintf(stderr, "Failed to load MicDurationSpin widget\n");
    app.gain_spin = GTK_SPIN_BUTTON(gtk_builder_get_object(builder, "GainSpin"));
    if (!app.gain_spin) fprintf(stderr, "Failed to load GainSpin widget\n");
    app.mic_gain_scale = GTK_SCALE(gtk_builder_get_object(builder, "MicGainScale"));
    if (!app.mic_gain_scale) fprintf(stderr, "Failed to load MicGainScale widget\n");
    app.vol_adjustment = GTK_ADJUSTMENT(gtk_builder_get_object(builder, "id_voladjustment"));
    if (!app.vol_adjustment) fprintf(stderr, "Failed to load id_voladjustment widget\n");
    app.gain_adjustment = GTK_ADJUSTMENT(gtk_builder_get_object(builder, "id_gainadjustment"));
    if (!app.gain_adjustment) fprintf(stderr, "Failed to load id_gainadjustment widget\n");
    app.mic_gain_adjustment = GTK_ADJUSTMENT(gtk_builder_get_object(builder, "id_micgainadjustment"));
    if (!app.mic_gain_adjustment) fprintf(stderr, "Failed to load id_micgainadjustment widget\n");
    app.mic_boost_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "MicBoostCheck"));
    if (!app.mic_boost_check) fprintf(stderr, "Failed to load MicBoostCheck widget\n");
    app.mic_xlr_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "MicXLRCheck"));
    if (!app.mic_xlr_check) fprintf(stderr, "Failed to load MicXLRCheck widget\n");
    app.mic_tip_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "MicTipCheck"));
    if (!app.mic_tip_check) fprintf(stderr, "Failed to load MicTipCheck widget\n");
    app.mic_bias_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "MicBiasCheck"));
    if (!app.mic_bias_check) fprintf(stderr, "Failed to load MicBiasCheck widget\n");
    app.line_check = GTK_TOGGLE_BUTTON(gtk_builder_get_object(builder, "LineCheck"));
    if (!app.line_check) fprintf(stderr, "Failed to load LineCheck widget\n");
    app.overload_label = GTK_LABEL(gtk_builder_get_object(builder, "overload_label"));
    if (!app.overload_label) fprintf(stderr, "Failed to load overload_label widget\n");
    app.near_peak_label = GTK_LABEL(gtk_builder_get_object(builder, "near_peak_label"));
    if (!app.near_peak_label) fprintf(stderr, "Failed to load near_peak_label widget\n");

    // Check for unexpected GainScale widget
    if (gtk_builder_get_object(builder, "GainScale")) 
    {
        fprintf(stderr, "Warning: Unexpected GainScale widget found in UI file\n");
    }

    // Ensure critical widgets are loaded before proceeding
    if (!app.window || !app.text_buffer) 
    {
        fprintf(stderr, "Critical widgets missing, exiting\n");
        g_object_unref(builder);
        return EXIT_FAILURE;
    }

    // Connect signals only if widgets are valid
    if (app.volume_scale) 
    {
        g_signal_connect(app.volume_scale, "value-changed", G_CALLBACK(on_volume_changed), NULL);
        printf("VolumeScale signal connected\n");
    }
    g_signal_connect(app.gain_spin, "value-changed", G_CALLBACK(on_line_gain_changed), &audio);
    g_signal_connect(app.mic_gain_scale, "value-changed", G_CALLBACK(on_mic_gain_changed), &audio);

    // Ensure GainSpin and MicGainScale are visible
    if (app.gain_spin) 
    {
        gtk_widget_show((GtkWidget *)app.gain_spin);
    }
    if (app.mic_gain_scale) 
    {
        gtk_widget_show((GtkWidget *)app.mic_gain_scale);
    }
    if (app.window) 
    {
        gtk_widget_show_all(app.window);
    }

    gtk_builder_add_callback_symbol(builder, "on_testL_button_clicked", G_CALLBACK(on_testL_button_clicked));
    gtk_builder_add_callback_symbol(builder, "on_testR_button_clicked", G_CALLBACK(on_testR_button_clicked));
    gtk_builder_add_callback_symbol(builder, "on_MicTestButton_clicked", G_CALLBACK(on_MicTestButton_clicked));
    gtk_builder_add_callback_symbol(builder, "on_window_main_destroy", G_CALLBACK(on_window_main_destroy));
    gtk_builder_add_callback_symbol(builder, "on_MicSettings_toggled", G_CALLBACK(on_MicSettings_Changed));
    gtk_builder_add_callback_symbol(builder, "on_close_button_clicked", G_CALLBACK(on_close_button_clicked));
    gtk_builder_connect_signals(builder, &audio);

    // Load the saved gain settings
    load_gains(&app);

    // Update text buffer with initial status
    if (app.text_buffer) 
    {
        gtk_text_buffer_insert_at_cursor(app.text_buffer,
            hardware_available ? "Application started. Use Line Gain spin button or Mic Gain slider.\n"
                              : "Application started in UI-only mode (hardware unavailable).\n",
            -1);
    }

    if (app.mic_activity_label) 
    {
        gtk_label_set_text(app.mic_activity_label, MIC_STATUS_IDLE);
    }
    if (app.ptt_label) 
    {
        gtk_label_set_text(app.ptt_label, "No PTT");
    }

    // Initialize CodecRegMutex since CodecWriteInit is not available
    if (sem_init(&CodecRegMutex, 0, 1) != 0) 
    {
        fprintf(stderr, "Failed to init CodecRegMutex: %s\n", strerror(errno));
        hardware_available = false;
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    else
    {
        printf("CodecRegMutex initialized\n");
    }

    printf("Initializing synchronization primitives...\n");
    if (sem_init(&DDCInSelMutex, 0, 1) != 0) 
    {
        fprintf(stderr, "Failed to init DDCInSelMutex: %s\n", strerror(errno));
        hardware_available = false;
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    else
    {
        printf("DDCInSelMutex initialized\n");
    }
    if (sem_init(&DDCResetFIFOMutex, 0, 1) != 0) 
    {
        fprintf(stderr, "Failed to init DDCResetFIFOMutex: %s\n", strerror(errno));
        hardware_available = false;
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    else
    {
        printf("DDCResetFIFOMutex initialized\n");
    }
    if (sem_init(&RFGPIOMutex, 0, 1) != 0) 
    {
        fprintf(stderr, "Failed to init RFGPIOMutex: %s\n", strerror(errno));
        hardware_available = false;
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }else
    {
        printf("RFGPIOMutex initialized\n");
    }
    if (pthread_mutex_init(&audio.mic_test_mutex, NULL) != 0)
    {
        fprintf(stderr, "Failed to init mic_test_mutex: %s\n", strerror(errno));
        hardware_available = false;
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    else
    {
        printf("mic_test_mutex initialized\n");
    }
    if (pthread_mutex_init(&audio.speaker_test_mutex, NULL) != 0)
    {
        fprintf(stderr, "Failed to init speaker_test_mutex: %s\n", strerror(errno));
        hardware_available = false;
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    else
    {
        printf("speaker_test_mutex initialized\n");
    }

    printf("Checking hardware availability...\n");
    if (!OpenXDMADriver(true)) 
    {
        fprintf(stderr, "Failed to open XDMA driver, proceeding without hardware\n");
        hardware_available = false;
        if (app.text_buffer) 
        {
            gtk_text_buffer_insert_at_cursor(app.text_buffer, "Hardware unavailable: running in UI-only mode\n", -1);
        }
    }
    else
    {
        printf("XDMA driver opened successfully\n");
        PrintVersionInfo();
        CodecInitialise(); // Treat as void, no return value check
        SetByteSwapping(false);
        SetSpkrMute(false);
        uint32_t codecReg = RegisterRead(VADDRCODECSPIREG);
        printf("Initial codec register value: 0x%08x\n", codecReg);
    }

    if (hardware_available)
    {
        if (posix_memalign((void **)&audio.write_buffer, ALIGNMENT, audio.buffer_size) != 0 ||
            (uintptr_t)audio.write_buffer % ALIGNMENT != 0 ||
            posix_memalign((void **)&audio.read_buffer, ALIGNMENT, audio.buffer_size) != 0 ||
            (uintptr_t)audio.read_buffer % ALIGNMENT != 0)
        {
            fprintf(stderr, "DMA buffer allocation failed\n");
            if (audio.write_buffer) free(audio.write_buffer);
            if (audio.read_buffer) free(audio.read_buffer);
            audio.write_buffer = NULL;
            audio.read_buffer = NULL;
            hardware_available = false;
            if (app.text_buffer)
            {
                gtk_text_buffer_insert_at_cursor(app.text_buffer, "DMA buffer allocation failed\n", -1);
            }
        }
        else
        {
            printf("DMA buffers allocated successfully\n");
            struct stat st;
            audio.dma_write_fd = open("/dev/xdma0_h2c_0", O_WRONLY | O_CLOEXEC);
            if (audio.dma_write_fd < 0 || (stat("/dev/xdma0_h2c_0", &st) == 0 && !S_ISCHR(st.st_mode))) 
            {
                fprintf(stderr, "Failed to open DMA write device\n");
                hardware_available = false;
                if (app.text_buffer)
                {
                    gtk_text_buffer_insert_at_cursor(app.text_buffer, "Failed to open DMA write device\n", -1);
                }
            }
            else
            {
                printf("DMA write device opened\n");
            }
            audio.dma_read_fd = open("/dev/xdma0_c2h_0", O_RDONLY | O_CLOEXEC);
            if (audio.dma_read_fd < 0 || (stat("/dev/xdma0_c2h_0", &st) == 0 && !S_ISCHR(st.st_mode)))
            {
                fprintf(stderr, "Failed to open DMA read device\n");
                hardware_available = false;
                if (app.text_buffer)
                {
                    gtk_text_buffer_insert_at_cursor(app.text_buffer, "Failed to open DMA read device\n", -1);
                }
            }
            else
            {
                printf("DMA read device opened\n");
            }
        }
    }

    if (!hardware_available)
    {
        if (app.mic_activity_label)
        {
            gtk_label_set_text(app.mic_activity_label, "Hardware unavailable");
        }
        if (app.ptt_label)
        {
            gtk_label_set_text(app.ptt_label, "PTT: Hardware unavailable");
        }
    }

    printf("Applying initial settings, hardware_available = %d...\n", hardware_available);
    if (hardware_available)
    {
        on_MicSettings_Changed(NULL, &audio);
    }
    if (app.mic_progress_bar)
    {
        gtk_progress_bar_set_fraction(app.mic_progress_bar, 0.0);
    }
    if (app.mic_level_bar)
    {
        gtk_progress_bar_set_fraction(app.mic_level_bar, 0.0);
    }
    if (app.overload_label)
    {
        gtk_label_set_text(app.overload_label, "Overload: Idle");
    }
    if (app.near_peak_label)
    {
        gtk_label_set_text(app.near_peak_label, "Near Peak: Idle");
    }

    printf("Starting threads...\n");
    if (pthread_create(&ptt_thread, NULL, CheckForPttPressed, &app) < 0)
    {
        fprintf(stderr, "Failed to create ptt_thread: %s\n", strerror(errno));
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    else
    {
        printf("PTT thread created\n");
    }
    if (pthread_create(&mic_test_thread, NULL, MicTest, thread_args) < 0) 
    {
        fprintf(stderr, "Failed to create mic_test_thread: %s\n", strerror(errno));
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    else
    {
        printf("Mic test thread created\n");
    }
    if (pthread_create(&speaker_test_thread, NULL, SpeakerTest, thread_args) < 0)
    {
        fprintf(stderr, "Failed to create speaker_test_thread: %s\n", strerror(errno));
        cleanup(&app, &audio);
        return EXIT_FAILURE;
    }
    else
    {
        printf("Speaker test thread created\n");
    }

    printf("Entering gtk_main()...\n");
    gtk_main();

    keep_running = false;
    pthread_join(ptt_thread, NULL);
    pthread_join(mic_test_thread, NULL);
    pthread_join(speaker_test_thread, NULL);
    cleanup(&app, &audio);
    return 0;
}
