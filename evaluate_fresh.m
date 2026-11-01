function summary = evaluate_fresh()
%EVALUATE_FRESH Evaluate NEW saved audio, never reused for enrollment.
% Run collect_test_sample several times for each enrolled speaker and for
% never-enrolled people (label unknown). No automatic threshold changes.
root = fileparts(mfilename('fullpath'));
addpath(root);
entries = dir(fullfile(root, 'speaker_recordings', 'speaker_*'));
entries = entries([entries.isdir]);
names = {};
features = zeros(27, 5, 0);

for s = 1:numel(entries)
    sampleFeatures = zeros(27, 5);
    try
        for k = 1:5
            path = fullfile(entries(s).folder, entries(s).name, ...
                sprintf('sample_%03d.wav', k));
            [x, fs] = audioread(path);
            sampleFeatures(:, k) = sound_pattern(x, fs);
        end
    catch problem
        fprintf(2, 'Skipping enrollment %s: %s\n', ...
            entries(s).name, problem.message);
        continue;
    end
    names{end+1} = entries(s).name; %#ok<AGROW>
    features(:, :, end+1) = sampleFeatures; %#ok<AGROW>
end

if isempty(names)
    error('speaker:NoProfiles', 'No readable speaker enrollments found.');
end
testRoot = fullfile(root, 'test_recordings');
if ~isfolder(testRoot)
    fprintf('No independent tests yet. Run collect_test_sample first.\n');
    summary = struct('correct',0,'rejected_enrolled',0, ...
        'wrong_name',0,'rejected_unknown',0,'accepted_unknown',0);
    return;
end

summary = struct('correct',0, 'rejected_enrolled',0, ...
    'wrong_name',0, 'rejected_unknown',0, 'accepted_unknown',0);
directories = dir(testRoot);
directories = directories([directories.isdir]);
fprintf('\n=== Fresh, independent test recordings ===\n');
fprintf('These files must not also be in speaker_recordings.\n');
tested = 0;
for d = 1:numel(directories)
    label = directories(d).name;
    if strcmp(label, '.') || strcmp(label, '..')
        continue;
    end
    isUnknown = strcmp(label, 'unknown');
    trueSpeaker = find(strcmp(names, label), 1);
    if ~isUnknown && isempty(trueSpeaker)
        fprintf(2, 'Skipping test folder %s: not an enrolled name.\n', label);
        continue;
    end
    clips = dir(fullfile(testRoot, label, '*.wav'));
    for k = 1:numel(clips)
        file = fullfile(clips(k).folder, clips(k).name);
        try
            [x, fs] = audioread(file);
            pattern = sound_pattern(x, fs);
            r = speaker_match(features, pattern);
        catch problem
            fprintf(2, 'Skipping unreadable test %s: %s\n', file, problem.message);
            continue;
        end
        tested = tested + 1;
        if isUnknown
            if r.accepted
                summary.accepted_unknown = summary.accepted_unknown + 1;
                verdict = ['FALSE ACCEPT as ' names{r.winner}];
            else
                summary.rejected_unknown = summary.rejected_unknown + 1;
                verdict = 'Correct rejection';
            end
        elseif ~r.accepted
            summary.rejected_enrolled = summary.rejected_enrolled + 1;
            verdict = 'FALSE REJECTION';
        elseif r.winner == trueSpeaker
            summary.correct = summary.correct + 1;
            verdict = 'Correct identification';
        else
            summary.wrong_name = summary.wrong_name + 1;
            verdict = ['WRONG NAME: ' names{r.winner}];
        end
        fprintf('%s / %s: %s (score %.3f, candidate %s)\n', ...
            label, clips(k).name, verdict, r.scores(r.winner), names{r.winner});
    end
end

genuine = summary.correct + summary.rejected_enrolled + summary.wrong_name;
unknown = summary.rejected_unknown + summary.accepted_unknown;
fprintf('\nFresh registered tests: %d correct, %d false rejections, %d wrong-name accepts (of %d)\n', ...
    summary.correct, summary.rejected_enrolled, summary.wrong_name, genuine);
fprintf('Fresh unknown tests: %d correctly rejected, %d falsely accepted (of %d)\n', ...
    summary.rejected_unknown, summary.accepted_unknown, unknown);
if tested == 0
    fprintf('No readable independent test files found. Run collect_test_sample first.\n');
end
fprintf(['Use multiple speakers and new recording sessions. These counts are NOT\n' ...
    'proof of real-world accuracy. Do not tune thresholds from a tiny sample.\n']);
end
