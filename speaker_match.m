function result = speaker_match(features, pattern)
%SPEAKER_MATCH Compare an utterance with enrolled speakers, with rejection.
% features: 27 x recordings x speakers (MFCC means, standard deviations, log2 pitch)
% pattern:  27 x 1 descriptor for the new recording
%
% This is a small-data educational matcher, NOT voice authentication.
% Thresholds are estimated from leave-one-out enrollment variation and
% limited by absolute caps. MFCC comparisons use bounded-influence Huber
% loss to avoid a single unstable cepstral coefficient dominating the score.
% Validate with fresh enrolled and unknown voices.

if size(features, 1) ~= 27 || size(features, 2) < 4 || ...
        ~isnumeric(pattern) || numel(pattern) ~= 27
    error('speaker:MatcherInput', 'Expected 27 features and at least four recordings per speaker.');
end
pattern = pattern(:);
if any(~isfinite(features(:))) || any(~isfinite(pattern))
    error('speaker:MatcherInput', 'Voice descriptors must be finite.');
end

n = size(features, 2);
count = size(features, 3);
centers = reshape(median(features, 2), 27, count);
residuals = reshape(features - reshape(centers, 27, 1, count), 27, []);
% Tiny estimated variability exaggerates ordinary differences. Use floors.
scale = max(1.4826 * median(abs(residuals), 2), ...
    [0.65 * ones(26, 1); 0.18]);

result.scores = zeros(1, count);
result.limits = zeros(1, count);
result.mfcc_limits = zeros(1, count);
result.pitch_limits = zeros(1, count);
result.support = zeros(1, count);
result.neighbor_scores = zeros(1, count);
result.neighbor_limits = zeros(1, count);
result.profile_valid = false(1, count);
result.bad_samples = cell(1, count);
mfccScores = zeros(1, count);
pitchDiffs = zeros(1, count);

for s = 1:count
    samples = features(:, :, s);
    reference = centers(:, s);
    delta = (pattern - reference) ./ scale;
    result.scores(s) = weighted_distance(delta);
    mfccScores(s) = mean(robust_mfcc_loss(delta(1:26)));
    pitchDiffs(s) = abs(pattern(27) - reference(27));

    % Leave-one-out distances measure how enrolled recordings vary naturally.
    loo = zeros(3, n);
    neighbors = zeros(1, n);
    for j = 1:n
        others = [1:j-1, j+1:n];
        heldOut = samples(:, j);
        leaveOneOutCenter = median(samples(:, others), 2);
        gap = (heldOut - leaveOneOutCenter) ./ scale;
        loo(:, j) = [weighted_distance(gap); ...
            mean(robust_mfcc_loss(gap(1:26))); ...
            abs(heldOut(27) - leaveOneOutCenter(27))];

        otherGaps = (samples(:, others) - heldOut) ./ scale;
        twoNearest = sort(weighted_distance(otherGaps));
        neighbors(j) = mean(twoNearest(1:2));
    end

    % Robust acceptance limits; absolute caps prevent arbitrary widening.
    result.limits(s) = robust_limit(loo(1, :), 1.4, 3.0);
    result.mfcc_limits(s) = robust_limit(loo(2, :), 1.2, 2.8);
    result.pitch_limits(s) = robust_limit(loo(3, :), 0.22, 0.32);
    result.neighbor_limits(s) = robust_limit(neighbors, 1.0, 3.0);

    % Compare the two most similar enrollment samples, rather than requiring
    % three recordings to cross one rigid per-clip cutoff.
    templateDistances = sort(weighted_distance((samples - pattern) ./ scale));
    result.neighbor_scores(s) = mean(templateDistances(1:2));
    result.support(s) = sum(templateDistances <= 1.15 * result.neighbor_limits(s));

    enrollmentDistances = weighted_distance((samples - reference) ./ scale);
    result.bad_samples{s} = find(loo(1, :) > result.limits(s));
    result.profile_valid(s) = sum(loo(1, :) <= result.limits(s)) >= 3 ...
        && sum(enrollmentDistances <= 1.5 * result.limits(s)) >= 3;
end

[ordered, indices] = sort(result.scores);
result.winner = indices(1);
result.margin = NaN;
if count > 1
    result.margin = (ordered(2) - ordered(1)) / max(ordered(2), eps);
end
winner = result.winner;
checks = [result.profile_valid(winner), ...
    result.scores(winner) <= result.limits(winner), ...
    mfccScores(winner) <= result.mfcc_limits(winner), ...
    pitchDiffs(winner) <= result.pitch_limits(winner), ...
    result.neighbor_scores(winner) <= result.neighbor_limits(winner) ...
        && result.support(winner) >= 2, ...
    count == 1 || result.margin >= 0.35];

reasons = {'Enrollment samples are inconsistent. Review this speaker.', ...
    'Voice is too far from the enrolled profile.', ...
    'Voice spectrum differs from the enrolled profile.', ...
    'Voice pitch differs from the enrolled profile.', ...
    'Too few enrollment recordings support the candidate.', ...
    'The closest two speakers are not sufficiently separated.'};
result.accepted = all(checks);
result.reason = 'Accepted';
if ~result.accepted
    result.reason = reasons{find(~checks, 1, 'first')};
end
end

function limit = robust_limit(values, floorValue, ceilingValue)
mid = median(values);
spread = 1.4826 * median(abs(values - mid));
limit = min(ceilingValue, max(floorValue, mid + 2.5 * spread));
end

function distance = weighted_distance(difference)
% A single anomalous MFCC mean must not dominate squared distance.
% Huber's loss is quadratic near a match and linear for large deviations.
% Apply the SAME loss to enrollment calibration and test comparisons.
distance = 0.85 * mean(robust_mfcc_loss(difference(1:26, :, :)), 1) + ...
    0.15 * difference(27, :, :).^2;
end

function loss = robust_mfcc_loss(delta)
% Huber loss with a knee at one normalized feature unit.
% A large number of mismatched features still produces a large distance.
knee = 1.0;
magnitude = abs(delta);
loss = magnitude.^2;
large = magnitude > knee;
loss(large) = 2 * knee * magnitude(large) - knee^2;
end
