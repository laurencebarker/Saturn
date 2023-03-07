pkg load signal

% load file; find length & sample rate
load('ddcdata.txt');
complexData = ddcdata(:,1) + i* ddcdata(:,2);

fs=1536;
N=length(complexData);

%get X range, zero centred FFT
fshift = (-N/2:N/2-1)*(fs/N);


%convert datas to complex, window it and FFT
window = blackmanharris(N);
windoweddata = window.*complexData;
result = fft(windoweddata);
result = fftshift(result);

%convert to dB, 0dB=top
absolute = abs(result);
largest=max(absolute);
dB = 20*log10(absolute/largest);

%plot
plot(fshift, dB);
yticks(-200:10:0);
xticks(-800:100:800);
xlim([-768 768]);
ylim([-150 0]);
xlabel("frequency (KHz)");
ylabel("amplitude (dB)");
title('DDC passband, 48 bit arithmetic in CIC, 24 bit input, 32 bits out, FIR 18 bit coeff / 25 bits in');
grid on;
