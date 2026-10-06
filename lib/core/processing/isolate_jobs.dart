import 'dart:isolate';
import 'dart:typed_data';

import 'film/film_lut.dart';
import 'film/film_profile.dart';
import 'film/grain_field.dart';
import 'photo_pipeline.dart';
import 'video_plan.dart';

// Isolate entry points.
//
// These MUST stay top-level functions whose only captured variables are their
// parameters. Dart sends a closure to the new isolate together with its whole
// *context* — every variable captured by any closure in the enclosing scope.
// Calling `Isolate.run(() => PhotoPipeline.run(job))` from inside an instance
// method that also has a closure capturing `this` drags the processor, its
// repositories and (through Riverpod) the entire app state into the message,
// which fails with "Illegal argument in isolate message" (dart:ui objects are
// not sendable). That was the cause of shots being marked ruined.

/// Renders one still in a fresh isolate.
Future<PhotoResult> renderPhotoInIsolate(PhotoJob job) =>
    Isolate.run(() => PhotoPipeline.run(job), debugName: 'photo-${job.id}');

/// Plans one video (crop, filtergraph, OSD frames) in a fresh isolate.
Future<VideoPlan> planVideoInIsolate(VideoJob job, int probeWidth, int probeHeight) => Isolate.run(
  () => VideoPlanner.prepare(job, probeWidth: probeWidth, probeHeight: probeHeight),
  debugName: 'video-plan-${job.id}',
);

/// RGBA strip of a stock's 3D LUT for the live shader.
Future<Uint8List> filmLutPixelsInIsolate(String stockId) =>
    Isolate.run(() => FilmLut.build(FilmProfile.forStock(stockId)!).toRgbaStrip(), debugName: 'lut-$stockId');

/// RGBA8 grain tile for the live shader.
Future<Uint8List> grainPixelsInIsolate() =>
    Isolate.run(() => GrainField.generate().toRgba8(), debugName: 'grain');
