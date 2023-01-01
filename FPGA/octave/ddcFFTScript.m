function ddcFFTScript()
  pkg load signal
  load('ddcdata.txt');
  data = ddcdata(109:8300,:);
  complexData = data(:,1) + i* data(:,2);
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
end
