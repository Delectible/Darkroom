// DARKROOM PATCH: the one physical lens the back camera streams from.

package io.flutter.plugins.camerax;

import androidx.annotation.Nullable;

/**
 * Set by the app (MainActivity's "pinLens") before it opens the camera: the id
 * of the physical lens inside the back logical camera that every stream comes
 * from (main, ultra-wide or telephoto). Pinned, the phone never changes lens
 * by itself (zoom, low light, close focus...). Null: the logical camera as
 * the plugin opens it, switching as the phone likes.
 */
public final class DarkroomLens {
  private DarkroomLens() {}

  public static volatile @Nullable String physicalId;
}
