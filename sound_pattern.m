function [pattern, filteredSound, details] = sound_pattern(x, fs)
% Summarize speech using stable, trimmed MFCC statistics and log-pitch.
% Enrollment AND test audio use the same processing, so no re-recording
% is required when this file changes.

if fs ~= 16000
    error('speaker:SampleRate', 'Audio must be recorded at 16000 Hz.');
end
if ~isnumeric(x) || ~isreal(x) || isempty(x) || ~ismatrix(x) || any(~isfinite(x(:)))
    error('speaker:InvalidAudio', 'Audio must contain finite, real sample values.');
end
if isvector(x)
    x = x(:);
else
    x = mean(x, 2);
end
if length(x) < round(0.75*fs)
    error('speaker:ShortAudio', 'Record at least 0.75 seconds, including initial silence.');
end
x = double(x);
x = x - mean(x);

fftSize = 2^nextpow2(length(x));
frequency = (0:fftSize-1)' * fs / fftSize;
spectrum = fft(x, fftSize);
positiveBins = 1:fftSize/2+1;
details.fft_frequency = frequency(positiveBins);
details.fft_input = abs(spectrum(positiveBins))/length(x);
keep = (frequency >= 80 & frequency <= 7600) | ...
       (frequency >= fs-7600 & frequency <= fs-80);
spectrum(~keep) = 0;
details.fft_filtered = abs(spectrum(positiveBins))/length(x);
% Double the positive-frequency amplitudes, excluding DC and Nyquist.
details.fft_input(2:end-1) = 2*details.fft_input(2:end-1);
details.fft_filtered(2:end-1) = 2*details.fft_filtered(2:end-1);
filteredSound = real(ifft(spectrum));
filteredSound = filteredSound(1:length(x));

frameLength = round(0.025*fs);
hopLength = round(0.010*fs);
starts = 1:hopLength:(length(x)-frameLength+1);
indices = (0:frameLength-1)' + starts;
frames = filteredSound(indices);
energy = mean(frames.^2, 1);
% Estimate noise from the intended initial quiet period. The median is less
% affected by a short click/cough than the previous mean-energy threshold.
quietFrameCount = max(1, sum(starts + frameLength - 1 <= round(0.25*fs)));
quietEnergy = median(energy(1:quietFrameCount));
sortedEnergy = sort(energy);
upperEnergy = sortedEnergy(max(1, ceil(0.90*numel(sortedEnergy))));
threshold = max([4*quietEnergy, 0.02*upperEnergy, 1e-8]);

% Smooth isolated on/off decisions over five frames (about 50 ms).
% Keep actual energetic frames: do not turn the gaps between words into speech.
rawSpeech = energy > threshold;
speechFrames = (conv(double(rawSpeech), ones(1, 5), 'same') >= 3) ...
    & (energy > 0.5*threshold);
if sum(speechFrames)*hopLength/fs < 0.5
    error('speaker:NoSpeech', ...
        'Insufficient speech. Stay quiet first and speak the full phrase clearly.');
end

emphasized = filter([1 -0.97], 1, filteredSound);
window = 0.54 - 0.46*cos(2*pi*(0:frameLength-1)'/(frameLength-1));
frames = emphasized(indices(:, speechFrames)) .* window;
frameFftSize = 512;
powerSpectrum = abs(fft(frames, frameFftSize)).^2 / frameFftSize;
powerSpectrum = powerSpectrum(1:frameFftSize/2+1, :);

melEdges = linspace(2595*log10(1+80/700), 2595*log10(1+7600/700), 28);
hzEdges = 700*(10.^(melEdges/2595)-1);
hz = (0:frameFftSize/2) * fs/frameFftSize;
filterBank = zeros(26, length(hz));
for band = 1:26
    rising = (hz-hzEdges(band))/(hzEdges(band+1)-hzEdges(band));
    falling = (hzEdges(band+2)-hz)/(hzEdges(band+2)-hzEdges(band+1));
    filterBank(band, :) = max(0, min(rising, falling));
end
logPower = log(max(filterBank*powerSpectrum, 1e-12));
% Exclude coefficient zero to reduce sensitivity to overall recording level.
dctBasis = sqrt(2/26)*cos(pi*(1:13)'*((0:25)+0.5)/26);
cepstra = dctBasis*logPower;
% Trim the 10 percent most extreme frames from EACH coefficient before
% pooling. This reduces the effects of plosives, breath/noise bursts and
% uncertain speech boundaries, without discarding entire spoken words.
sortedCepstra = sort(cepstra, 2);
trim = floor(0.10 * size(sortedCepstra, 2));
if 2*trim >= size(sortedCepstra, 2) - 1
    trim = 0;
end
stableCepstra = sortedCepstra(:, 1+trim:end-trim);
pattern = [mean(stableCepstra, 2); std(stableCepstra, 0, 2)];
details.cepstra = cepstra;
details.frame_times = (starts(speechFrames)-1+frameLength/2)/fs;
details.speech_seconds = sum(speechFrames)*hopLength/fs;
details.speech_frames = sum(speechFrames);
details.noise_energy = quietEnergy;

% Periodicity supplies a voice-source cue alongside the spectral MFCCs.
pitchLength = round(0.040*fs);
pitchStarts = starts(speechFrames);
pitchStarts = pitchStarts(pitchStarts+pitchLength-1 <= length(filteredSound));
pitchFrames = filteredSound((0:pitchLength-1)' + pitchStarts);
pitchFrames = pitchFrames-mean(pitchFrames, 1);
correlation = real(ifft(abs(fft(pitchFrames, 2048)).^2));
lags = ceil(fs/400):floor(fs/70);
normalized = zeros(numel(lags), numel(pitchStarts));
for lagNumber = 1:numel(lags)
    lag = lags(lagNumber);
    denominator = sqrt(sum(pitchFrames(1:end-lag, :).^2, 1).* ...
        sum(pitchFrames(1+lag:end, :).^2, 1));
    normalized(lagNumber, :) = correlation(lag+1, :)./max(denominator, eps);
end
pitches = zeros(1, numel(pitchStarts));
for frameNumber = 1:numel(pitchStarts)
    strength = normalized(:, frameNumber);
    peaks = find(strength(2:end-1) > strength(1:end-2) & ...
        strength(2:end-1) >= strength(3:end))+1;
    if isempty(peaks) || max(strength(peaks)) < 0.65
        continue;
    end
    % Prefer the first strong peak to reduce pitch-halving errors.
    peak = peaks(find(strength(peaks) >= max(0.65, 0.9*max(strength(peaks))), 1));
    pitches(frameNumber) = fs/lags(peak);
end
pitches = pitches(pitches > 0);
if numel(pitches)*hopLength/fs < 0.15
    error('speaker:NoVoice', 'Not enough voiced speech. Stay quiet first, then speak the complete phrase in your normal voice.');
end
details.pitch_hz = median(pitches);
details.voiced_seconds = numel(pitches)*hopLength/fs;
pattern = [pattern; log2(details.pitch_hz)];
end
