package com.hmucustomer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class DriverArrivalMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data["eventType"] != "driver_arrival") {
            return
        }

        ensureChannel()

        val orderId = data["orderId"].orEmpty()
        val serviceType = data["serviceType"].orEmpty()
        val driverName = data["driverName"]
        val body = data["body"] ?: if (serviceType == "delivery") {
            if (!driverName.isNullOrBlank()) {
                "$driverName is here with your order. Attend your driver now."
            } else {
                "Your order is here. Attend your driver now."
            }
        } else {
            "Your order is ready for pickup now."
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(DriverArrivalActivity.EXTRA_EVENT_TYPE, "driver_arrival")
            putExtra(DriverArrivalActivity.EXTRA_ORDER_ID, orderId)
            putExtra(DriverArrivalActivity.EXTRA_DRIVER_NAME, driverName)
            putExtra(DriverArrivalActivity.EXTRA_SERVICE_TYPE, serviceType)
        }

        val contentPendingIntent = PendingIntent.getActivity(
            this,
            orderId.hashCode(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Your order is here")
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(contentPendingIntent)
            .build()

        NotificationManagerCompat.from(this).notify(orderId.hashCode(), notification)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Driver Arrival Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerts when an order has arrived"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            enableLights(true)
        }

        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "driver_arrival_alerts"
    }
}
