import 'dart:typed_data';

/// DARKROOM PATCH (diagnostics): the app hears the scene loader's steps (its
/// Performance Report lines them up with the stalls). Null: silent.
void Function(String message)? darkroomTrace;

/// DARKROOM PATCH (texture cache): textures as they were transcoded for
/// this GPU, kept by the app between launches ([key] names the texture's
/// bytes and the format). A launch that finds them uploads them straight
/// away: no workers, no transcoding. Null: always transcoded.
Future<Uint8List?> Function(String key)? darkroomCacheRead;
void Function(String key, Uint8List bytes)? darkroomCacheWrite;
