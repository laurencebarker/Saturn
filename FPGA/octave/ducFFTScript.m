pkg load signal
load('ducdata.txt');
window = blackmanharris(length(ducdata));
windoweddata = window.*ducdata;
result = fft(windoweddata);
result = fftshift(result);
absolute = abs(result);
dB = 20*log10(absolute);
plot(dB);
xlabel("frequency");
ylabel("amplitude");
grid on;
