function filename = collect_test_sample()
%COLLECT_TEST_SAMPLE Record a NEW validation clip without altering enrollment.
% Choose an enrolled name or "unknown". Test files stay local (gitignored).
filename = '';
root = fileparts(mfilename('fullpath'));
entries = dir(fullfile(root, 'speaker_recordings', 'speaker_*'));
entries = entries([entries.isdir]);
speakerFolders = {entries.name};

answer = inputdlg(['Enter an enrolled name (e.g. Arnav or speaker_4) ' ...
    'or unknown for an unregistered person:'], ...
    'Independent recognition test', [1 65]);
if isempty(answer)
    return;
end
slug = lower(strtrim(answer{1}));
slug = regexprep(slug, '[^a-z0-9]+', '_');
slug = regexprep(slug, '^_|_$', '');
if isempty(slug)
    errordlg('Enter a speaker name or unknown.', 'Test recording');
    return;
end

if strcmp(slug, 'unknown')
    label = 'unknown';
else
    options = {slug, ['speaker_' slug]};
    selected = find(ismember(speakerFolders, options), 1);
    if isempty(selected)
        errordlg('The name is not enrolled. For an unregistered person, enter unknown.', ...
            'Test recording');
        return;
    end
    label = speakerFolders{selected};
end

fs = 16000;
phrase = 'This is my voice for identification.';
x = record_voice(fs, phrase, ['Fresh test: ' label]);
if isempty(x)
    return;
end
try
    sound_pattern(x, fs); % Reject incomplete/invalid speech before saving.
catch problem
    errordlg(problem.message, 'Test recording not saved');
    return;
end

target = fullfile(root, 'test_recordings', label);
if ~exist(target, 'dir')
    mkdir(target);
end
next = 1;
filename = fullfile(target, sprintf('test_%03d.wav', next));
while isfile(filename)
    next = next + 1;
    filename = fullfile(target, sprintf('test_%03d.wav', next));
end
audiowrite(filename, x, fs, 'BitsPerSample', 16);
fprintf('Saved independent test recording: %s\n', filename);
fprintf('This file was NOT added to speaker enrollment.\n');
end
