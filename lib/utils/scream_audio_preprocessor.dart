
import 'dart:math' as math;

import 'package:fftea/fftea.dart';

class ScreamAudioPreprocessor {
  static const int sampleRate = 16000;
  static const int fftSize = 1024;
  static const int hopLength = 256;
  static const int melBands = 64;
  static const int audioSamples = 160000;
  static const int expectedFrames = 626;

  final FFT _fft = FFT(fftSize);
  late final List<List<double>> _melFilters = _createMelFilters();

  /// Converts 10 seconds of mono, 16 kHz audio into
  /// [melBands, expectedFrames, 1] model-ready values.
  ///
  /// Audio samples must be normalized to [-1, 1].
  List<List<List<double>>> process(List<double> audio) {
    if (audio.length != audioSamples) {
      throw ArgumentError(
        'Expected $audioSamples samples, got ${audio.length}.',
      );
    }

    final frameCount = expectedFrames;
    final melSpectrogram = List.generate(
      melBands,
      (_) => List<double>.filled(frameCount, 0.0),
    );

    // librosa.stft uses centered frames by default:
    // 512 zero samples are added at both ends.
    final padded = List<double>.filled(
      audioSamples + fftSize,
      0.0,
    );
    for (int i = 0; i < audio.length; i++) {
      padded[i + fftSize ~/ 2] = audio[i];
    }

    final powerSpectrogram = List.generate(
      fftSize ~/ 2 + 1,
      (_) => List<double>.filled(frameCount, 0.0),
    );

    for (int frame = 0; frame < frameCount; frame++) {
      final start = frame * hopLength;
      final windowed = List<double>.filled(fftSize, 0.0);

      for (int i = 0; i < fftSize; i++) {
        final hann = 0.5 -
            0.5 * math.cos(2 * math.pi * i / fftSize);
        windowed[i] = padded[start + i] * hann;
      }

      final spectrum = _fft.realFft(windowed);

      for (int bin = 0; bin <= fftSize ~/ 2; bin++) {
        final real = spectrum[bin].x;
        final imaginary = spectrum[bin].y;
        powerSpectrogram[bin][frame] =
            real * real + imaginary * imaginary;
      }
    }

    double maxMelPower = 0.0;

    for (int mel = 0; mel < melBands; mel++) {
      for (int frame = 0; frame < frameCount; frame++) {
        double energy = 0.0;

        for (int bin = 0; bin <= fftSize ~/ 2; bin++) {
          energy += _melFilters[mel][bin] *
              powerSpectrogram[bin][frame];
        }

        melSpectrogram[mel][frame] = energy;

        if (energy > maxMelPower) {
          maxMelPower = energy;
        }
      }
    }

    // Approximate librosa.power_to_db(ref=np.max), then
    // clip to [-80, 0], divide by 80, and add 1.
    final reference = math.max(maxMelPower, 1e-10);

    final output = List.generate(
      melBands,
      (mel) => List.generate(
        frameCount,
        (frame) {
          final energy = math.max(
            melSpectrogram[mel][frame],
            1e-10,
          );

          final db = 10 * math.log(energy / reference) /
              math.ln10;

          final clipped = db.clamp(-80.0, 0.0);
          return clipped / 80.0 + 1.0;
        },
      ),
    );

    // Add the final channel dimension: [64, 626, 1].
    return List.generate(
      melBands,
      (mel) => List.generate(
        frameCount,
        (frame) => [output[mel][frame]],
      ),
    );
  }

  List<List<double>> _createMelFilters() {
    const fftBins = fftSize ~/ 2 + 1;

    double hzToMel(double hz) {
      const fSp = 200.0 / 3.0;
      if (hz < 1000.0) {
        return hz / fSp;
      }
      const minLogHz = 1000.0;
      const minLogMel = minLogHz / fSp;
      final logStep = math.log(6.4) / 27.0;
      return minLogMel + math.log(hz / minLogHz) / logStep;
    }

    double melToHz(double mel) {
      const fSp = 200.0 / 3.0;
      const minLogHz = 1000.0;
      const minLogMel = minLogHz / fSp;
      final logStep = math.log(6.4) / 27.0;

      if (mel < minLogMel) {
        return mel * fSp;
      }
      return minLogHz * math.exp(logStep * (mel - minLogMel));
    }

    final minMel = hzToMel(0.0);
    final maxMel = hzToMel(sampleRate / 2.0);

    final melPoints = List.generate(
      melBands + 2,
      (i) => melToHz(
        minMel + (maxMel - minMel) * i / (melBands + 1),
      ),
    );

    final filters = List.generate(
      melBands,
      (_) => List<double>.filled(fftBins, 0.0),
    );

    for (int mel = 0; mel < melBands; mel++) {
      final left = melPoints[mel];
      final center = melPoints[mel + 1];
      final right = melPoints[mel + 2];

      for (int bin = 0; bin < fftBins; bin++) {
        final frequency = bin * sampleRate / fftSize;

        final lower = (frequency - left) / (center - left);
        final upper = (right - frequency) / (right - center);
        final triangle = math.max(
          0.0,
          math.min(lower, upper),
        );

        // Slaney-style area normalization.
        filters[mel][bin] =
            triangle * 2.0 / (right - left);
      }
    }

    return filters;
  }
}
