package com.hmucustomer

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingAlertPayload: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.hmucustomer/driver_alerts"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingAlertPayload" -> result.success(pendingAlertPayload)
                "clearPendingAlertPayload" -> {
                    pendingAlertPayload = null
                    result.success(null)
                }
                "startRingtone" -> {
                    DriverArrivalRingtonePlayer.start(this)
                    result.success(true)
                }
                "stopRingtone" -> {
                    DriverArrivalRingtonePlayer.stop()
                    result.success(true)
                }
                "isRingtonePlaying" -> {
                    result.success(DriverArrivalRingtonePlayer.isPlaying())
                }
                else -> result.notImplemented()
            }
        }

        cacheAlertPayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        cacheAlertPayload(intent)
    }

    private fun cacheAlertPayload(intent: Intent?) {
        if (intent == null) {
            return
        }

        val eventType = intent.getStringExtra(DriverArrivalActivity.EXTRA_EVENT_TYPE) ?: return
        if (eventType != "driver_arrival") {
            return
        }

        pendingAlertPayload = mapOf(
            "eventType" to eventType,
            "orderId" to intent.getStringExtra(DriverArrivalActivity.EXTRA_ORDER_ID),
            "driverName" to intent.getStringExtra(DriverArrivalActivity.EXTRA_DRIVER_NAME),
            "serviceType" to intent.getStringExtra(DriverArrivalActivity.EXTRA_SERVICE_TYPE),
            "acknowledge" to intent.getBooleanExtra(DriverArrivalActivity.EXTRA_ACKNOWLEDGE, false),
        )
    }

    override fun onDestroy() {
        DriverArrivalRingtonePlayer.stop()
        super.onDestroy()
    }
}
