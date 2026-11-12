/// Debug > Camera > Flash: how the digital cameras' back flash takes the
/// picture (a test of what feels most like a 2000s digicam's flash). Kept
/// until the app restarts.
///
/// * phone: the phone's own flash sequence (pre-flash, exposure and focus
///   settling, then the flash): slowest, best exposed.
/// * locked: the same flash with focus and exposure locked first (skips
///   some settling; the pre-flash stays).
/// * torch: the light on as a torch and the picture taken at once, with
///   the preview's exposure held: near-instant, weaker light.
///
/// Camera Log notes how long each photo took from the press.
enum DigitalFlash {
  phone,
  locked,
  torch;

  static DigitalFlash current = DigitalFlash.phone;
}
