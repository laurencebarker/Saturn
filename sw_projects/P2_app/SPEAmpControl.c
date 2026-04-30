/////////////////////////////////////////////////////////////
//
// Saturn project: Artix7 FPGA + Raspberry Pi4 Compute Module
// PCI Express interface from linux on Raspberry pi
// this application uses C code to emulate HPSDR protocol 2
//
// copyright Laurence Barker November 2021
// licenced under GNU GPL3
//
// SPEAmpControl.c:
//
// Kenwood TS-2000 CAT emulation for SPE Expert linear amplifiers.
// Handles IF; and FA; queries on a serial tty using the current TX
// frequency from the DUC delta-phase word.
//
//////////////////////////////////////////////////////////////

#include "SPEAmpControl.h"
#include "serialport.h"

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <pthread.h>
#include <syscall.h>
#include <errno.h>


// default serial baud rate
#define SPE_DEFAULT_BAUD  B9600

// maximum length of an incoming CAT command (e.g. "IF;")
#define SPE_INBUF_SIZE    32

// TX frequency in Hz, updated by SetSPEAmpTXFrequency()
static uint32_t SPETXFreq_Hz = 0;

// scaling factor: DUC delta-phase word -> Hz (same as AriesATU.c)
// f_Hz = phase * (122880000 / 2^32) = phase * 0.028610229...
#define SPE_DELTAPHASE_TO_HZ  0.028610229

bool SPEAmpActive = false;

static pthread_t         SPEThread;
static bool              SPEThreadStarted = false;
static int               SPESerialFd = -1;
static bool              SPETXState = false;
static pthread_mutex_t   SPEStateMutex = PTHREAD_MUTEX_INITIALIZER;


// Send a TS-2000 IF response. Fields not tracked by p2app are set to
// neutral defaults; the SPE Expert only needs the frequency and TX/RX bit.
// Mode is hardcoded to USB for now.
static void SPESendIF(int fd, uint32_t freq_hz, bool is_tx)
{
    char buf[64];
    int len;

    len = snprintf(buf, sizeof(buf),
        "IF%011u"   // freq (11 digits)
        " 0000"     // step: 1 space + 4 digits (TS-2000 default step repr)
        "+0000"     // RIT sign + offset (4 digits)
        "00"        // RIT on, XIT on
        "00"        // memory channel (2 digits)
        "%c"        // TX/RX: '1' = TX, '0' = RX
        "2"         // mode: USB
        "0"         // VFO: A
        "0"         // scan: off
        "0"         // split: off
        "0"         // tone: off
        "00"        // tone number (2 digits)
        ";",
        freq_hz,
        is_tx ? '1' : '0');

    if (len > 0)
        write(fd, buf, (size_t)len);
}


//
// Build and send a Kenwood FA (VFO-A frequency) response.
// Format: FA[11-digit freq];
//
static void SPESendFA(int fd, uint32_t freq_hz)
{
    char buf[32];
    int len;

    len = snprintf(buf, sizeof(buf), "FA%011u;", freq_hz);
    if (len > 0)
        write(fd, buf, (size_t)len);
}


//
// Parse the command that arrived in cmd[] (null-terminated, without the
// trailing semicolon) and dispatch to the appropriate response sender.
//
static void SPEDispatch(int fd, const char *cmd)
{
    uint32_t freq;
    bool tx;

    pthread_mutex_lock(&SPEStateMutex);
    freq = SPETXFreq_Hz;
    tx = SPETXState;
    pthread_mutex_unlock(&SPEStateMutex);

    if (strcmp(cmd, "IF") == 0)
    {
        SPESendIF(fd, freq, tx);
    }
    else if (strcmp(cmd, "FA") == 0)
    {
        SPESendFA(fd, freq);
    }
    // All other commands are silently ignored; the amp will retry or
    // move on.  Adding responses for further commands (e.g. MD;, AI;)
    // is straightforward: extend this if/else chain.
}


//
// SPEAmpThreadFunction()
// Reads bytes from the serial port, assembles them into semicolon-terminated
// commands, and calls SPEDispatch() for each complete command.
//
static void* SPEAmpThreadFunction(__attribute__((unused)) void *arg)
{
    char inbuf[SPE_INBUF_SIZE];
    int  inptr = 0;
    char rawbuf[SPE_INBUF_SIZE];
    int  nread;
    int  i;
    char ch;

    printf("SPE amp CAT thread started, pid=%ld\n", syscall(SYS_gettid));

    while (true)
    {
        pthread_mutex_lock(&SPEStateMutex);
        if (!SPEAmpActive)
        {
            pthread_mutex_unlock(&SPEStateMutex);
            break;
        }
        pthread_mutex_unlock(&SPEStateMutex);

        nread = read(SPESerialFd, rawbuf, sizeof(rawbuf) - 1);
        if (nread <= 0)
        {
            if (nread < 0 && errno != EINTR)
                break;
            continue;
        }

        for (i = 0; i < nread; i++)
        {
            ch = rawbuf[i];

            if (ch == ';')
            {
                // end of command: null-terminate and dispatch
                inbuf[inptr] = '\0';
                if (inptr > 0)
                    SPEDispatch(SPESerialFd, inbuf);
                inptr = 0;
            }
            else if (ch >= ' ')
            {
                // accumulate printable characters only
                if (inptr < (SPE_INBUF_SIZE - 1))
                    inbuf[inptr++] = ch;
                else
                    inptr = 0;  // overflow: discard and restart
            }
            // control characters other than ';' are silently dropped
        }
    }

    printf("SPE amp CAT thread stopped\n");
    return NULL;
}


//
// Parse optional ":baudrate" suffix from PathAndBaud, open the port,
// and translate the integer baud to a termios speed constant.
//
static unsigned int ParseBaud(const char *baudstr)
{
    int b = atoi(baudstr);
    switch (b)
    {
        case 1200:   return B1200;
        case 2400:   return B2400;
        case 4800:   return B4800;
        case 9600:   return B9600;
        case 19200:  return B19200;
        case 38400:  return B38400;
        case 57600:  return B57600;
        case 115200: return B115200;
        default:
            printf("SPEAmpControl: unrecognised baud rate %d, using 9600\n", b);
            return B9600;
    }
}


//
// InitialiseSPEAmpHandler()
// Parse PathAndBaud, open the serial port, start the listener thread.
// Returns true on success.
//
bool InitialiseSPEAmpHandler(const char *PathAndBaud)
{
    char        path[160];
    unsigned int baud = SPE_DEFAULT_BAUD;
    const char *colon;
    int result;

    // split "path:baud" or plain "path"
    colon = strchr(PathAndBaud, ':');
    if (colon != NULL)
    {
        size_t pathlen = (size_t)(colon - PathAndBaud);
        if (pathlen >= sizeof(path))
            pathlen = sizeof(path) - 1;
        strncpy(path, PathAndBaud, pathlen);
        path[pathlen] = '\0';
        baud = ParseBaud(colon + 1);
    }
    else
    {
        strncpy(path, PathAndBaud, sizeof(path) - 1);
        path[sizeof(path) - 1] = '\0';
    }

    SPESerialFd = OpenSerialPort(path, baud);
    if (SPESerialFd == -1)
    {
        printf("SPE amp CAT: failed to open serial port %s\n", path);
        return false;
    }

    pthread_mutex_lock(&SPEStateMutex);
    SPEAmpActive = true;
    SPEThreadStarted = false;
    pthread_mutex_unlock(&SPEStateMutex);

    result = pthread_create(&SPEThread, NULL, SPEAmpThreadFunction, NULL);
    if (result != 0)
    {
        errno = result;
        perror("pthread_create SPE amp CAT thread");
        pthread_mutex_lock(&SPEStateMutex);
        SPEAmpActive = false;
        pthread_mutex_unlock(&SPEStateMutex);
        close(SPESerialFd);
        SPESerialFd = -1;
        return false;
    }
    SPEThreadStarted = true;

    printf("SPE amp CAT handler active on %s\n", path);
    return true;
}


//
// ShutdownSPEAmpHandler()
// Signal the thread to stop, wait briefly for it to exit, then close
// the serial port.
//
void ShutdownSPEAmpHandler(void)
{
    if (!SPEAmpActive)
        return;

    pthread_mutex_lock(&SPEStateMutex);
    SPEAmpActive = false;
    pthread_mutex_unlock(&SPEStateMutex);

    if (SPESerialFd != -1)
        close(SPESerialFd);

    if (SPEThreadStarted)
    {
        pthread_join(SPEThread, NULL);
        SPEThreadStarted = false;
    }

    SPESerialFd = -1;
}


//
// SetSPEAmpTXFrequency()
// Convert the DUC delta-phase word to Hz and cache it for the response thread.
// Called from InHighPriority.c alongside SetAriesTXFrequency().
//
void SetSPEAmpTXFrequency(uint32_t NewFreqDeltaPhase)
{
    uint32_t freq_hz;

    if(!SPEAmpActive)
        return;

    freq_hz = (uint32_t)((double)NewFreqDeltaPhase * SPE_DELTAPHASE_TO_HZ + 0.5);
    pthread_mutex_lock(&SPEStateMutex);
    SPETXFreq_Hz = freq_hz;
    pthread_mutex_unlock(&SPEStateMutex);
}


void SetSPEAmpTXState(bool IsTX)
{
    if(!SPEAmpActive)
        return;

    pthread_mutex_lock(&SPEStateMutex);
    SPETXState = IsTX;
    pthread_mutex_unlock(&SPEStateMutex);
}
