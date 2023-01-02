pkg load signal
load('ddcdata.txt');
complexData = ddcdata(:,1) + i* ddcdata(:,2);
window = blackmanharris(length(complexData));
windoweddata = window.*complexData;
result = fft(windoweddata);
result = fftshift(result);
absolute = abs(result);
dB = 20*log10(absolute);
plot(dB);
xlabel("frequency");
ylabel("amplitude");
grid on;
