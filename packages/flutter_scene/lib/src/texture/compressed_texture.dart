// Uploads a flutter_scene KTX2 texture to the GPU. The CPU-heavy transcode runs
// off the main isolate; only the GPU calls stay on the main thread.
//
// The device may support a block-compressed family directly, in which case the
// block payload is transcoded to that format and uploaded compressed (less
// VRAM): BC1/ETC2-RGB for opaque textures, BC3/ETC2-RGBA8 when the texture
// is marked as carrying alpha, and ASTC either way (its blocks switch to the
// RGBA endpoint mode where needed). Otherwise the payload is decoded to
// rgba8 and uploaded uncompressed, which is always correct (alpha included)
// and the only path on web without the extensions.
//
// Either way, every mip level stored in the container is transcoded and
// uploaded (on backends that can sample hand-uploaded chains), so mipped KTX2
// textures sample with proper minification.

import 'package:flutter_scene/src/darkroom_trace.dart';
import 'dart:async';
import 'dart:isolate' show TransferableTypedData;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/mip_sampling_probe.dart';
import 'package:flutter_scene/src/texture/block/transcode_astc.dart';
import 'package:flutter_scene/src/texture/block/transcode_bc1.dart';
import 'package:flutter_scene/src/texture/block/transcode_bc3.dart';
import 'package:flutter_scene/src/texture/block/transcode_etc2.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';

/// The order in which compressed families are preferred when the device
/// supports more than one: ASTC (highest quality) > BC (desktop) > ETC2
/// (mobile/GLES3/web). ETC2 goes last because every GLES 3 context reports
/// it, including desktop drivers that decompress it to rgba8 on upload.
/// Reorder for testing a specific family on a device that supports several.
List<gpu.TextureCompressionFamily> compressionFamilyPreference = [
  gpu.TextureCompressionFamily.astc,
  gpu.TextureCompressionFamily.bc,
  gpu.TextureCompressionFamily.etc2,
];

// Transcode target, chosen on the main thread (from the device probe) and
// passed to the transcode isolate so it knows which format to produce.
const int _modeRgba8 = 0;
const int _modeBc1 = 1;
const int _modeEtc2 = 2;
const int _modeAstc = 3;
const int _modeBc3 = 4;
const int _modeEtc2Rgba = 5;

/// The transcoded mip levels (base first) ready for GPU upload. Plain data so
/// it can cross an isolate boundary (no GPU types).
typedef _Prepared = ({List<Uint8List> levels, int mode, int width, int height});

/// Reads a flutter_scene KTX2 file from [bytes], transcodes it on a background
/// isolate, and uploads the result. Use this from async load paths so large
/// textures do not block the UI.
Future<gpu.Texture> gpuTextureFromKtx2Async(Uint8List bytes) async {
  final handing = Stopwatch()..start();
  _logFamiliesOnce();
  final mode = _selectMode();
  final mips = uploadableMipChains;
  // DARKROOM PATCH: transcoded last launch? Straight up from the cache.
  final key = '${_hash(bytes)}-$mode-${mips ? 1 : 0}';
  final read = darkroomCacheRead;
  if (read != null) {
    try {
      final cached = await read(key);
      final p = cached == null ? null : _unpack(cached);
      if (p != null) return _upload(p);
    } catch (_) {}
  }
  // DARKROOM PATCH: [bytes] is usually a view into the whole scene file;
  // sent as is, Dart copies that entire file into each worker (nine textures:
  // nine copies of ~50 MB on the UI thread, ~500 ms on a Pixel 9 Pro). Only
  // this texture's bytes go, copied once and handed over without another.
  final handed = TransferableTypedData.fromList([bytes]);
  // DARKROOM PATCH: three textures' workers at a time. Workers share the
  // app's heap: nine at once made garbage collections that held the UI
  // thread ~280 ms together; one at a time cost 1.4 s of launch.
  while (_workers >= 3) {
    await _workerFreed.future;
  }
  _workers++;
  final preparing = compute(_prepareFromHanded, (ktx2: handed, mode: mode, mips: mips));
  if (handing.elapsedMilliseconds >= 3) {
    darkroomTrace?.call('texture handed over ${handing.elapsedMilliseconds} ms');
  }
  final _Prepared prepared;
  try {
    prepared = await preparing;
  } finally {
    _workers--;
    final freed = _workerFreed;
    _workerFreed = Completer<void>();
    freed.complete();
  }
  final texture = _upload(prepared);
  final write = darkroomCacheWrite;
  if (write != null) {
    try {
      write(key, _pack(prepared));
    } catch (_) {}
  }
  return texture;
}

/// DARKROOM PATCH: names a texture's bytes for the cache: its length and an
/// FNV-1a over its first 64 KB and 4 KB samples through the rest (cheap on
/// the UI thread; textures differ long before that).
String _hash(Uint8List b) {
  var h = 0x811c9dc5;
  void add(int v) => h = ((h ^ v) * 0x01000193) & 0xffffffff;
  final head = math.min(b.length, 65536);
  for (var i = 0; i < head; i++) {
    add(b[i]);
  }
  for (var i = head; i < b.length; i += 4096) {
    final end = math.min(b.length, i + 64);
    for (var j = i; j < end; j++) {
      add(b[j]);
    }
  }
  return '${b.length.toRadixString(16)}${h.toRadixString(16).padLeft(8, '0')}';
}

const int _packMagic = 0x44524b31; // "DRK1"

/// [p] as one block of bytes: magic, mode, width, height, level count, each
/// level's length, then the levels.
Uint8List _pack(_Prepared p) {
  final head = 5 + p.levels.length;
  var size = head * 4;
  for (final l in p.levels) {
    size += l.length;
  }
  final out = Uint8List(size);
  final d = ByteData.sublistView(out);
  d.setUint32(0, _packMagic);
  d.setUint32(4, p.mode);
  d.setUint32(8, p.width);
  d.setUint32(12, p.height);
  d.setUint32(16, p.levels.length);
  var at = head * 4;
  for (var i = 0; i < p.levels.length; i++) {
    d.setUint32(20 + i * 4, p.levels[i].length);
    out.setRange(at, at + p.levels[i].length, p.levels[i]);
    at += p.levels[i].length;
  }
  return out;
}

/// The other way; null if [b] isn't whole.
_Prepared? _unpack(Uint8List b) {
  if (b.length < 20) return null;
  final d = ByteData.sublistView(b);
  if (d.getUint32(0) != _packMagic) return null;
  final n = d.getUint32(16);
  if (n < 1 || n > 20 || b.length < (5 + n) * 4) return null;
  var at = (5 + n) * 4;
  final levels = <Uint8List>[];
  for (var i = 0; i < n; i++) {
    final len = d.getUint32(20 + i * 4);
    if (at + len > b.length) return null;
    levels.add(Uint8List.sublistView(b, at, at + len));
    at += len;
  }
  if (at != b.length) return null;
  return (levels: levels, mode: d.getUint32(4), width: d.getUint32(8), height: d.getUint32(12));
}

/// Synchronous variant: transcodes on the calling (usually main) thread. Heavy
/// for large textures; prefer [gpuTextureFromKtx2Async]. Kept for the sync
/// realize path.
gpu.Texture gpuTextureFromKtx2(Uint8List bytes) => gpuTextureFromKtx2Texture(readKtx2(bytes));

/// As [gpuTextureFromKtx2], for an already-parsed [texture].
gpu.Texture gpuTextureFromKtx2Texture(Ktx2Texture texture) {
  _logFamiliesOnce();
  return _upload(_prepare(texture, _selectMode(), mips: uploadableMipChains));
}

/// Whether a hand-uploaded mip chain is worth transcoding and uploading: the
/// backend must accept one, and the device must actually sample it.
bool get uploadableMipChains => gpu.gpuContext.doesSupportManuallyMippedTextures && mipChainsAreSampled;

/// Picks the transcode target for the current device.
int _selectMode() {
  for (final family in compressionFamilyPreference) {
    if (!gpu.gpuContext.supportsTextureCompression(family)) continue;
    switch (family) {
      case gpu.TextureCompressionFamily.astc:
        return _modeAstc;
      case gpu.TextureCompressionFamily.bc:
        return _modeBc1;
      case gpu.TextureCompressionFamily.etc2:
        return _modeEtc2;
      case gpu.TextureCompressionFamily.astcHdr:
        // The transcoder emits LDR formats only; HDR ASTC is not a
        // transcode target, so skip to the next preferred family.
        break;
    }
  }
  return _modeRgba8;
}

/// Isolate entry point: parse and transcode. Pure Dart, no GPU.
int _workers = 0;
Completer<void> _workerFreed = Completer<void>();

_Prepared _prepareFromHanded(({TransferableTypedData ktx2, int mode, bool mips}) input) =>
    _prepare(readKtx2(input.ktx2.materialize().asUint8List()), input.mode, mips: input.mips);

/// DARKROOM PATCH: big textures load at half size where they can't be
/// compressed on the GPU (the rgba8 fallback).
bool halfSizeUncompressed = true;

/// Transcodes the stored mip levels of [texture] to [mode]. Pure Dart, no GPU.
/// When [mips] is false (the backend cannot sample hand-uploaded mip chains),
/// only the base level is produced.
_Prepared _prepare(Ktx2Texture texture, int mode, {required bool mips}) {
  final width = texture.pixelWidth;
  final height = math.max(1, texture.pixelHeight);
  // The container may carry fewer levels than the allocator's chain (a
  // base-only file) or more (a chain reaching 1x1); clamp to what
  // `createTexture(mipLevelCount:)` accepts.
  final levelCount = mips ? math.min(texture.levels.length, engineMipLevelCount(width, height)) : 1;
  // A texture marked as carrying alpha upgrades to the family's alpha
  // format. ASTC needs no upgrade: its transcoder switches non-opaque blocks
  // to the RGBA color endpoint mode within the same 16-byte format.
  if (ktx2HasAlpha(texture)) {
    mode = switch (mode) {
      _modeBc1 => _modeBc3,
      _modeEtc2 => _modeEtc2Rgba,
      _ => mode,
    };
  }
  if (mode == _modeRgba8) {
    // DARKROOM PATCH (see packages/flutter_scene/DARKROOM.md): uncompressed,
    // a big texture starts at its half-size mip, a quarter of the memory
    // (a Pixel 9 Pro took 192 MB a 3D camera at full size).
    final skip = halfSizeUncompressed && texture.levels.length > 1 && width >= 1024 ? 1 : 0;
    final count = mips ? levelCount - skip : 1;
    final levels = [
      for (var level = skip; level < skip + count; level++) decodeKtx2Level(texture, level: level).rgba,
    ];
    final base = mipSize(width, height, skip);
    return (levels: levels, mode: _modeRgba8, width: base.width, height: base.height);
  }
  final levels = <Uint8List>[];
  for (var level = 0; level < levelCount; level++) {
    final size = mipSize(width, height, level);
    final blocks = ktx2LevelBlocks(texture, level);
    final blockCount = ((size.width + 3) ~/ 4) * ((size.height + 3) ~/ 4);
    levels.add(switch (mode) {
      _modeBc1 => transcodeUniversalToBc1(blocks, blockCount),
      _modeBc3 => transcodeUniversalToBc3(blocks, blockCount),
      _modeEtc2 => transcodeUniversalToEtc2Rgb(blocks, blockCount),
      _modeEtc2Rgba => transcodeUniversalToEtc2Rgba(blocks, blockCount),
      _ => transcodeUniversalToAstc4x4(blocks, blockCount),
    });
  }
  return (levels: levels, mode: mode, width: width, height: height);
}

/// Uploads prepared level bytes to a GPU texture. Must run on the main thread.
gpu.Texture _upload(_Prepared p) {
  final uploading = Stopwatch()..start();
  final texture = _uploadNow(p);
  if (uploading.elapsedMilliseconds >= 5) {
    darkroomTrace?.call('texture upload ${uploading.elapsedMilliseconds} ms (${p.width}x${p.height})');
  }
  return texture;
}

gpu.Texture _uploadNow(_Prepared p) {
  final gpu.Texture texture;
  if (p.mode == _modeRgba8) {
    texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      p.width,
      p.height,
      mipLevelCount: p.levels.length,
    );
  } else {
    final format = switch (p.mode) {
      _modeBc1 => gpu.PixelFormat.bc1RGBAUNormInt,
      _modeBc3 => gpu.PixelFormat.bc3RGBAUNormInt,
      _modeEtc2 => gpu.PixelFormat.etc2RGB8UNormInt,
      _modeEtc2Rgba => gpu.PixelFormat.etc2RGBA8UNormInt,
      _ => gpu.PixelFormat.astc4x4LDR,
    };
    texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      p.width,
      p.height,
      format: format,
      mipLevelCount: p.levels.length,
      enableRenderTargetUsage: false,
      enableShaderWriteUsage: false,
    );
  }
  for (var level = 0; level < p.levels.length; level++) {
    texture.overwrite(ByteData.sublistView(p.levels[level]), mipLevel: level);
  }
  return texture;
}

bool _logged = false;

/// Logs the device's block-compression family support once. This doubles as the
/// device probe: running an app that loads a KTX2 texture reports which
/// families are available and therefore which upload path is taken.
void _logFamiliesOnce() {
  if (_logged) return;
  _logged = true;
  final context = gpu.gpuContext;
  debugPrint(
    'flutter_scene texture compression support: '
    'bc=${context.supportsTextureCompression(gpu.TextureCompressionFamily.bc)} '
    'etc2=${context.supportsTextureCompression(gpu.TextureCompressionFamily.etc2)} '
    'astc=${context.supportsTextureCompression(gpu.TextureCompressionFamily.astc)} '
    '(transcode runs off the main isolate; rgba8 fallback otherwise)',
  );
}
