% Identify a speaker using the WAV files in speaker_recordings/speaker_<name>.
fs = 16000;
phrase = 'This is my voice for identification.';
folder = fileparts(mfilename('fullpath'));
addpath(folder);
uiwait(warndlg(sprintf([ ...
    'IMPORTANT - MATCH YOUR ENROLLMENT VOICE\n\n' ...
    'Do NOT change your voice tone, pitch, pace, or volume.\n' ...
    'Speak the exact same phrase and in the same way as your enrollment recordings.\n' ...
    'Record in a quiet place WITHOUT background noise, and keep a similar microphone distance.\n\n' ...
    'A different speaking style or recording environment can cause a rejection.' ...
    ]), 'IMPORTANT - Before speaker identification', 'modal'));
speakers = dir(fullfile(folder, 'speaker_recordings', 'speaker_*'));
speakers = speakers([speakers.isdir]);
if isempty(speakers)
    errordlg('No speakers enrolled. Run train_my_voice.m first.', 'Speaker identification');
    return;
end

% One unreadable or incomplete enrollment must not disable every speaker.
names = {};
features = zeros(27, 5, 0);
validSpeakers = speakers([]);
for speakerNumber = 1:numel(speakers)
    entry = speakers(speakerNumber);
    name = strrep(entry.name(9:end), '_', ' ');
    if isempty(strtrim(name))
        fprintf(2, 'Skipping unnamed speaker folder: %s\n', entry.name);
        continue;
    end
    name(1) = upper(name(1));
    sampleFeatures = zeros(27, 5);
    try
        for example = 1:5
            filename = fullfile(entry.folder, entry.name, ...
                sprintf('sample_%03d.wav', example));
            [sample, rate] = audioread(filename);
            sampleFeatures(:, example) = sound_pattern(sample, rate);
        end
    catch problem
        fprintf(2, 'Skipping %s: %s\n', entry.name, problem.message);
        fprintf(2, '  Inspect or re-enroll this speaker; the other profiles remain available.\n');
        continue;
    end
    names{end+1} = name; %#ok<AGROW>
    features(:, :, end+1) = sampleFeatures; %#ok<AGROW>
    validSpeakers(end+1) = entry; %#ok<AGROW>
    fprintf('Loaded %s: 5 valid recordings\n', name);
end
speakers = validSpeakers;
if isempty(speakers)
    errordlg('No valid speaker profiles. Check the Command Window for skipped recordings.', ...
        'Speaker identification');
    return;
end

x = record_voice(fs, phrase, 'Live speaker identification');
if isempty(x)
    return;
end

try
    [pattern, filteredSound, details] = sound_pattern(x, fs);
catch problem
    errordlg(problem.message, 'Speaker identification');
    return;
end
result = speaker_match(features, pattern);
result.names = names;
result.phrase = phrase;
result.pitch_hz = details.pitch_hz;
result.uncertain = ~result.accepted;
scores = result.scores;
speakerMeans = reshape(mean(features(1:13, :, :), 2), 13, []);
for speakerNumber = 1:numel(speakers)
    if ~isempty(result.bad_samples{speakerNumber})
        fprintf('Check %s enrollment sample(s) %s: inconsistent with this speaker.\n', ...
            names{speakerNumber}, mat2str(result.bad_samples{speakerNumber}));
    end
end
if ~result.accepted
    result.name = 'Unknown';
    message = sprintf([ ...
        'Unknown / rejected.\nClosest candidate (not verified): %s\n%s\n\n' ...
        'IMPORTANT - VOICE NOT VERIFIED:\n' ...
        'If you are enrolled, speak the same phrase in the SAME tone, pitch, pace, and volume\n' ...
        'as your original recordings. Avoid background noise and keep a similar microphone distance.' ...
        ], names{result.winner}, result.reason);
    plotTitle = 'Unknown / rejected';
elseif isscalar(speakers)
    result.name = names{result.winner};
    message = sprintf('Voice matches enrollment: %s\nOnly one speaker enrolled; no comparison with other people.', result.name);
    plotTitle = ['Enrollment match: ' result.name];
else
    result.name = names{result.winner};
    message = sprintf('Identified speaker: %s', result.name);
    plotTitle = message;
end
fprintf('%s\n', message);
fprintf('Estimated voiced pitch: %.1f Hz\n', details.pitch_hz);
fprintf('Selected speech: %.2f s; voiced frames: %.2f s\n', ...
    details.speech_seconds, details.voiced_seconds);
for speakerNumber = 1:numel(names)
    fprintf('  %s: distance %.4f / limit %.4f; matching samples %d of %d\n', ...
        names{speakerNumber}, scores(speakerNumber), result.limits(speakerNumber), ...
        result.support(speakerNumber), size(features, 2));
    fprintf('    two-nearest distance %.4f / limit %.4f\n', ...
        result.neighbor_scores(speakerNumber), result.neighbor_limits(speakerNumber));
    fprintf('    MFCC score %.4f / limit %.4f; pitch delta %.4f / limit %.4f octave\n', ...
        result.mfcc_scores(speakerNumber), result.mfcc_limits(speakerNumber), ...
        result.pitch_differences(speakerNumber), result.pitch_limits(speakerNumber));
end
if ~result.accepted
    warndlg(message, 'Voice not verified');
else
    msgbox(message, 'Speaker identification result');
end
drawnow;

if isvector(x)
    x = x(:);
else
    x = mean(x, 2);
end
time = (0:length(x)-1)'/fs;
signalFigure = figure('Name', 'Speaker identification', 'Color', 'w', 'WindowStyle', 'docked');
subplot(4,1,1); plot(time, x); grid on;
title('Recorded speech'); xlabel('Time (s)'); ylabel('Amplitude');
subplot(4,1,2);
plot(details.fft_frequency, 20*log10(max(details.fft_input, 1e-12)), ...
    details.fft_frequency, 20*log10(max(details.fft_filtered, 1e-12)));
grid on; xlim([0 fs/2]);
title('Full-record FFT before and after filtering'); xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
legend('Before filtering', 'After filtering', 'Location', 'best');
subplot(4,1,3); imagesc(details.cepstra); axis xy;
title('MFCCs of selected speech frames'); xlabel('Selected speech frame'); ylabel('Coefficient');
colorbar('Color', 'k');
subplot(4,1,4); distanceBars = bar(scores); hold on;
limitMarkers = plot(1:numel(names), result.limits, 'ro', 'MarkerFaceColor', 'r');
grid on;
legend([distanceBars limitMarkers], 'Test distance', 'Enrollment distance limit', 'Location', 'best');
set(gca, 'XTick', 1:numel(names), 'XTickLabel', names, 'TickLabelInterpreter', 'none');
title(plotTitle, 'Interpreter', 'none'); ylabel('Distance (lower is closer)');
set(findall(gcf, 'Type', 'axes'), 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
set(findall(gcf, 'Type', 'text'), 'Color', 'k');
set(findall(gcf, 'Type', 'legend'), 'Color', 'w', 'TextColor', 'k');

coefficients = 1:13;
colors = lines(numel(speakers));
meanDifferences = pattern(1:13)-speakerMeans;
meanFigure = figure('Name', 'Speaker mean comparison', 'Color', 'w', 'WindowStyle', 'docked');
subplot(2,1,1);
plot(coefficients, pattern(1:13), '-ko', 'LineWidth', 2); hold on;
for speakerNumber = 1:numel(speakers)
    plot(coefficients, speakerMeans(:, speakerNumber), '-o', ...
        'Color', colors(speakerNumber, :), 'LineWidth', 1.2);
end
grid on; xlim([1 13]); xticks(coefficients);
title('Current voice and enrolled speaker means'); xlabel('MFCC coefficient'); ylabel('Mean MFCC value');
legend([{'Current voice'} names], 'Interpreter', 'none', 'Location', 'best');
subplot(2,1,2);
bars = bar(coefficients, meanDifferences, 'grouped');
for speakerNumber = 1:numel(speakers)
    bars(speakerNumber).FaceColor = colors(speakerNumber, :);
end
grid on; xticks(coefficients); yline(0, 'k-');
title('Current mean minus each enrolled speaker mean'); xlabel('MFCC coefficient'); ylabel('Signed difference');
legend(bars, names, 'Interpreter', 'none', 'Location', 'best');
set(findall(gcf, 'Type', 'axes'), 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
set(findall(gcf, 'Type', 'text'), 'Color', 'k');
set(findall(gcf, 'Type', 'legend'), 'Color', 'w', 'TextColor', 'k');

drawnow;
exportgraphics(signalFigure, fullfile(folder, 'test_signal.png'), 'Resolution', 150);
exportgraphics(meanFigure, fullfile(folder, 'test_comparison.png'), 'Resolution', 150);
fprintf('Saved latest test figures: test_signal.png and test_comparison.png\n');
