% EVALUATE_ENROLLMENT: repeatable, microphone-free development checks.
% Five-fold leave-one-out on the SAME saved recordings; NOT a measurement
% of real-world speaker recognition accuracy on independent test audio.
folder = fileparts(mfilename('fullpath'));
addpath(folder);
entries = dir(fullfile(folder, 'speaker_recordings', 'speaker_*'));
entries = entries([entries.isdir]);
names = {};
allFeatures = zeros(27, 5, 0);

for s = 1:numel(entries)
    samples = zeros(27, 5);
    try
        for k = 1:5
            path = fullfile(entries(s).folder, entries(s).name, ...
                sprintf('sample_%03d.wav', k));
            [x, fs] = audioread(path);
            samples(:, k) = sound_pattern(x, fs);
        end
    catch err
        fprintf(2, 'Skipping %s: %s\n', entries(s).name, err.message);
        continue;
    end
    names{end+1} = entries(s).name; %#ok<AGROW>
    allFeatures(:, :, end+1) = samples; %#ok<AGROW>
end

count = numel(names);
if count == 0
    error('speaker:NoProfiles', 'No valid five-recording speaker profiles were found.');
end

acceptedCorrect = 0;
acceptedWrong = 0;
rejectedGenuine = 0;
falseAcceptUnknown = 0;
unknownChecks = 0;
fprintf('\n=== Five-fold, same-recording development check ===\n');
fprintf('This cannot establish live accuracy or true unknown-speaker rejection.\n\n');

for s = 1:count
    correct = 0;
    wrong = 0;
    rejected = 0;
    for k = 1:5
        kept = [1:k-1, k+1:5];
        training = allFeatures(:, kept, :);
        testPattern = allFeatures(:, k, s);
        result = speaker_match(training, testPattern);
        if result.accepted && result.winner == s
            correct = correct + 1;
        elseif result.accepted
            wrong = wrong + 1;
        else
            rejected = rejected + 1;
        end

        % Known-other proxy: remove the correct speaker from the gallery.
        % Other registered speakers are NOT truly unseen people.
        if count > 1
            other = [1:s-1, s+1:count];
            withoutCorrectSpeaker = speaker_match(training(:, :, other), testPattern);
            falseAcceptUnknown = falseAcceptUnknown + double(withoutCorrectSpeaker.accepted);
            unknownChecks = unknownChecks + 1;
        end
    end
    fprintf('%-25s  correct %d/5, wrong %d/5, rejected %d/5\n', ...
        names{s}, correct, wrong, rejected);
    acceptedCorrect = acceptedCorrect + correct;
    acceptedWrong = acceptedWrong + wrong;
    rejectedGenuine = rejectedGenuine + rejected;
end
fprintf('\nHeld-out enrollment samples: %d correct, %d wrong, %d rejected (of %d).\n', ...
    acceptedCorrect, acceptedWrong, rejectedGenuine, 5*count);
if unknownChecks > 0
    fprintf('Known-other proxy checks: %d wrongly accepted (of %d).\n', ...
        falseAcceptUnknown, unknownChecks);
end
fprintf(['For real evaluation, collect fresh test samples per speaker AND\n' ...
    'new voices that were never included in enrollment.\n']);
