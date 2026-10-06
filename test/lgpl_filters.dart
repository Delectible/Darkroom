/// Filters that need --enable-gpl or an external library, i.e. that are NOT
/// in FFmpegKit's LGPL "min" build. Using any of them makes the whole
/// filtergraph fail with "Error initializing complex filters".
/// (From FFmpeg's configure: *_filter_deps="gpl" plus external-lib filters.)
const notInMinBuild = {
  'blackframe', 'boxblur', 'colormatrix', 'cover_rect', 'cropdetect', 'delogo', 'eq', 'find_rect', //
  'fspp', 'histeq', 'hqdn3d', 'interlace', 'kerndeint', 'mcdeint', 'mpdecimate', 'mptestsrc', 'nnedi',
  'owdenoise', 'perspective', 'phase', 'pp', 'pp7', 'pullup', 'repeatfields', 'sab', 'signature',
  'smartblur', 'spp', 'stereo3d', 'super2xsai', 'tinterlace', 'uspp', 'vaguedenoiser', 'vidstabdetect',
  'vidstabtransform', 'drawtext', 'subtitles', 'ass', 'zscale', 'frei0r', 'ocr', 'libplacebo', 'zmq',
};
