package com.darkroom.darkroom

import android.content.res.AssetFileDescriptor
import android.graphics.Bitmap
import android.graphics.Point
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.core.content.FileProvider
import java.io.File

/**
 * Replaces share_plus's FileProvider (same authority, see AndroidManifest.xml)
 * so the Android share sheet can show a picture for videos.
 *
 * The sheet asks the provider for an image version of each shared file.
 * A plain FileProvider can only answer that for images, so videos showed up
 * as a bare file name. Here a video answers with a JPEG of its first frame.
 */
class ShareThumbnailProvider : FileProvider() {

    override fun openTypedAssetFile(uri: Uri, mimeTypeFilter: String, opts: Bundle?): AssetFileDescriptor? {
        val type = getType(uri)
        if (type != null && type.startsWith("video/") && mimeTypeFilter.startsWith("image/")) {
            try {
                videoThumbnail(uri, opts)?.let { return it }
            } catch (e: Exception) {
                // Fall through: no preview is better than a failed share.
            }
        }
        return super.openTypedAssetFile(uri, mimeTypeFilter, opts)
    }

    private fun videoThumbnail(uri: Uri, opts: Bundle?): AssetFileDescriptor? {
        val ctx = context ?: return null
        val pfd = openFile(uri, "r") ?: return null
        val frame = pfd.use { fd ->
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(fd.fileDescriptor)
                retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } finally {
                retriever.release()
            }
        } ?: return null

        // ContentResolver.EXTRA_SIZE (API 29+): the size the sheet wants.
        @Suppress("DEPRECATION")
        val want = opts?.getParcelable<Point>("android.content.extra.SIZE")
        val longEdge = maxOf(want?.x ?: 512, want?.y ?: 512).coerceIn(96, 1024)
        val scale = longEdge.toFloat() / maxOf(frame.width, frame.height)
        val thumb = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                frame,
                (frame.width * scale).toInt().coerceAtLeast(1),
                (frame.height * scale).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            frame
        }

        val dir = File(ctx.cacheDir, "share_thumbs").apply { mkdirs() }
        val out = File(dir, "${uri.toString().hashCode()}.jpg")
        out.outputStream().use { thumb.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        return AssetFileDescriptor(
            ParcelFileDescriptor.open(out, ParcelFileDescriptor.MODE_READ_ONLY),
            0,
            AssetFileDescriptor.UNKNOWN_LENGTH,
        )
    }
}
