package com.lucifax.Lucifax_PFS

import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.lucifax.pfs/sound"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "playCihuy") {
                try {
                    val flutterLoader = io.flutter.FlutterInjector.instance().flutterLoader()
                    var afd: AssetFileDescriptor? = null

                    val candidates = listOf(
                        "assets/notifications/cihuy.mp3",
                        "notifications/cihuy.mp3"
                    )

                    for (candidate in candidates) {
                        try {
                            val key = flutterLoader.getLookupKeyForAsset(candidate)
                            afd = context.assets.openFd(key)
                            if (afd != null) break
                        } catch (e: Exception) {
                            // continue trying next candidate
                        }
                    }

                    if (afd != null) {
                        mediaPlayer?.release()
                        mediaPlayer = MediaPlayer().apply {
                            setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                                    .build()
                            )
                            setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                            prepare()
                            start()
                            setOnCompletionListener {
                                it.release()
                                mediaPlayer = null
                            }
                        }
                        result.success(true)
                    } else {
                        result.error("FILE_NOT_FOUND", "cihuy.mp3 not found in assets", null)
                    }
                } catch (e: Exception) {
                    result.error("AUDIO_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        mediaPlayer?.release()
        mediaPlayer = null
        super.onDestroy()
    }
}
