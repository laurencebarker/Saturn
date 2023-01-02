pkg load signal
load('ddcdebdata.txt');
complexData = ddcdebdata(:,1) + i* ddcdebdata(:,2);
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
