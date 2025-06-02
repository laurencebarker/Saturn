pkg load signal
clear all;
close all;
clc;


% load file; find length & sample rate
% file is now offset binary to read the DAC output dats
load('ducoffbindata.txt');
N=length(ducoffbindata);
offset = 32768*ones(N,1);
ducdata = ducoffbindata-offset;

%get X range, zero centred FFT
%freqvalues is the freq in MHz of each FFT bin
fs=122880000;
freqvalues = (-N/2:N/2-1)*(fs/N)*1e-6;

%window and FFT the data
window = nuttallwin(N);
%window = hanning(N);
windoweddata = window.*ducdata;
result = fft(windoweddata);
result = fftshift(result);

%convert to dB, 0dB=top
absolute = abs(result);

% get a 1 sided vector, stareting at DC
absolute1sided=absolute(N/2:N-1);
freqvalues1sided=freqvalues(N/2:N-1);
[largest, index]=max(absolute1sided);
ampl_dB = 20*log10(absolute1sided/largest);
freqoflargest=freqvalues1sided(index);

%plot result
figure(1);
plot(freqvalues1sided, ampl_dB);
yticks(-200:10:0);

xlabel("frequency");
ylabel("amplitude");
xticks (0:10:50);
yticks (-160:20:0);
xlim([0 52]);
ylim([-160 0]);
xlabel("frequency (MHz)");
ylabel("amplitude (dB)");
title('DUC passband, V12+random rounding');
text(30, -10,sprintf("freq=%f MHz", freqoflargest));
grid on;

% now work out a zoomed in view +/-XKHz either side of largest
% extent = amount either side, in Hz
fftbinwidth = fs/N;
extent = 100000;
extent_bins=extent/fftbinwidth;
freq_zoomed = (freqvalues1sided(index-extent_bins:index+extent_bins) - freqoflargest)*1000;
ampl_dB_zoomed = ampl_dB(index-extent_bins:index+extent_bins);

%plot zoomed result
figure(2);
plot(freq_zoomed, ampl_dB_zoomed);
yticks(-200:10:0);

xlabel("frequency");
ylabel("amplitude");
xticks (-100:20:100);
yticks (-160:20:0);
ylim([-160 0]);
xlabel("frequency (KHz)");
ylabel("amplitude (dB)");
title('zoomed in DUC passband, baseline FW V12');
text(30, -10,sprintf("freq=%f MHz", freqoflargest));
grid on;
