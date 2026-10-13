package com.vscodroid.util

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.Settings
import java.io.File
import java.io.IOException

/**
 * The user's workspace on public external storage (`/storage/emulated/0/vscodroid`).
 *
 * Everything here uses plain [java.io.File]. Nothing is inserted into MediaStore,
 * because that is what pushes project files into the system "Recent" list.
 * Instead every workspace root carries an empty `.nomedia` file, which tells the
 * media scanner to skip that folder and everything under it. A file manager
 * still lists the files normally.
 *
 * Reading and writing here needs "All files access" (MANAGE_EXTERNAL_STORAGE).
 * Without it the app falls back to its private folder until the user grants it.
 *
 * The runtime itself (server, node, python, git, extensions) stays in the app's
 * private storage on purpose: executables cannot run from public storage.
 */
object PublicStorage {

    const val ROOT_NAME = "vscodroid"
    const val NOMEDIA = ".nomedia"

    /** Top-level shared folders where a `.nomedia` would hide the user's own media. */
    private val MEDIA_DIRS = setOf(
        "DCIM", "Pictures", "Movies", "Music", "Podcasts",
        "Ringtones", "Alarms", "Notifications", "Audiobooks", "Recordings",
    )

    /** Whether the user has granted All files access. False off a device. */
    fun hasAccess(): Boolean =
        runCatching { android.os.Environment.isExternalStorageManager() }.getOrDefault(false)

    /** `/storage/emulated/0/vscodroid`. */
    fun rootDir(): File =
        File(android.os.Environment.getExternalStorageDirectory(), ROOT_NAME)

    /** The system screen where the user turns All files access on for this app. */
    fun accessSettingsIntent(context: Context): Intent =
        Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Fallback when the per-app screen is missing (some OEM builds). */
    fun accessSettingsFallbackIntent(): Intent =
        Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * Creates [dir] if needed and puts an empty `.nomedia` in it.
     *
     * Skipped for folders under the shared media directories (Pictures, DCIM and
     * so on): hiding those from the gallery would be a worse surprise than a
     * project showing up in a search.
     *
     * @return true if the marker is there afterwards.
     */
    fun ensureNoMedia(dir: File): Boolean {
        if (isUnderMediaDir(dir)) return false
        return try {
            if (!dir.isDirectory && !dir.mkdirs()) return false
            val marker = File(dir, NOMEDIA)
            marker.isFile || marker.createNewFile()
        } catch (e: IOException) {
            Logger.w("PublicStorage", "Could not write $NOMEDIA", e)
            false
        } catch (e: SecurityException) {
            Logger.w("PublicStorage", "Not allowed to write $NOMEDIA", e)
            false
        }
    }

    /** Creates the workspace root and marks it. Safe to call on every launch. */
    fun ensureRoot(): File? {
        if (!hasAccess()) return null
        val root = rootDir()
        if (!root.isDirectory && !root.mkdirs()) return null
        ensureNoMedia(root)
        return root
    }

    fun isUnderPublicStorage(path: String): Boolean {
        val base = android.os.Environment.getExternalStorageDirectory().absolutePath
        return path == base || path.startsWith("$base/")
    }

    private fun isUnderMediaDir(dir: File): Boolean {
        val base = android.os.Environment.getExternalStorageDirectory().absolutePath
        val rel = dir.absolutePath.removePrefix(base).trimStart('/')
        val top = rel.substringBefore('/')
        return top in MEDIA_DIRS
    }

    /**
     * Turns a folder the system picker returned (a `content://` tree URI) into the
     * real path of that folder, or null when it is not a plain local folder
     * (cloud providers and the like have no path).
     */
    fun pathFromTreeUri(uri: Uri): String? {
        val docId = runCatching { DocumentsContract.getTreeDocumentId(uri) }.getOrNull()
            ?: return null
        val volume = docId.substringBefore(':', "")
        val rel = docId.substringAfter(':', "")
        val base = when {
            volume.equals("primary", ignoreCase = true) ->
                android.os.Environment.getExternalStorageDirectory()
            volume.isNotEmpty() -> File("/storage/$volume")
            else -> return null
        }
        val dir = if (rel.isEmpty()) base else File(base, rel)
        return dir.takeIf { it.isDirectory && it.canRead() }?.absolutePath
    }

    /**
     * What the interface shows instead of a long path: the folder's own name.
     * The root itself reads "vscodroid".
     */
    fun displayLabel(path: String): String {
        val name = File(path).name
        return name.ifEmpty { ROOT_NAME }
    }
}
