package com.hmucustomer

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

object DriverArrivalRingtonePlayer {
    private const val TAG = "DriverRingtonePlayer"
    private var mediaPlayer: MediaPlayer? = null
    private var fallbackRingtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var isRingtoneActive = false

    @Synchronized
    fun start(context: Context) {
        stop()
        isRingtoneActive = true

        startVibration(context)

        val ringtoneUri = resolveAlertAudioUri(context)
        if (ringtoneUri != null) {
            playRingtoneUri(context, ringtoneUri)
        } else {
            Log.w(TAG, "No suitable system ringtone/audio URI found on device.")
        }
    }

    private fun resolveAlertAudioUri(context: Context): Uri? {
        // Priority: 1. Phone ringtone, 2. Alarm, 3. Notification
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
    }

    private fun playRingtoneUri(context: Context, uri: Uri) {
        // First try MediaPlayer for seamless looping and ringtone audio attributes
        try {
            val player = MediaPlayer().apply {
                try {
                    setDataSource(context, uri)
                } catch (e: Exception) {
                    context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                        setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    } ?: throw e
                }

                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                prepare()
                start()
            }
            mediaPlayer = player
            return
        } catch (e: Exception) {
            Log.w(TAG, "MediaPlayer failed to play ringtone uri: $uri. Falling back to Ringtone API.", e)
            mediaPlayer?.release()
            mediaPlayer = null
        }

        // Fallback: RingtoneManager
        try {
            val ringtone = RingtoneManager.getRingtone(context, uri)
            if (ringtone != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ringtone.isLooping = true
                }
                ringtone.play()
                fallbackRingtone = ringtone
            }
        } catch (e: Exception) {
            Log.e(TAG, "Fallback RingtoneManager also failed for uri: $uri", e)
        }
    }

    private fun startVibration(context: Context) {
        try {
            val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

            vibrator = v
            if (v != null && v.hasVibrator()) {
                val pattern = longArrayOf(0, 800, 800) // wait 0ms, vibrate 800ms, sleep 800ms
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createWaveform(pattern, 0)) // 0 means repeat
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(pattern, 0)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Vibration failed or permission missing", e)
        }
    }

    @Synchronized
    fun stop() {
        isRingtoneActive = false

        // Stop vibration
        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping vibrator", e)
        }
        vibrator = null

        // Stop MediaPlayer
        mediaPlayer?.runCatching {
            if (isPlaying) {
                stop()
            }
            reset()
            release()
        }
        mediaPlayer = null

        // Stop fallback Ringtone
        fallbackRingtone?.runCatching {
            if (isPlaying) {
                stop()
            }
        }
        fallbackRingtone = null
    }

    fun isPlaying(): Boolean {
        if (!isRingtoneActive) return false
        val mpPlaying = mediaPlayer?.runCatching { isPlaying }?.getOrDefault(false) ?: false
        val rtPlaying = fallbackRingtone?.runCatching { isPlaying }?.getOrDefault(false) ?: false
        return mpPlaying || rtPlaying || isRingtoneActive
    }
}
