package com.hmucustomer

import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.core.content.ContextCompat

class DriverArrivalActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setShowWhenLocked(true)
        setTurnScreenOn(true)

        val driverName = intent.getStringExtra(EXTRA_DRIVER_NAME)?.takeIf { it.isNotBlank() }
        val orderId = intent.getStringExtra(EXTRA_ORDER_ID).orEmpty()
        val serviceType = intent.getStringExtra(EXTRA_SERVICE_TYPE).orEmpty()
        val shortId = if (orderId.length <= 6) orderId.uppercase() else orderId.take(6).uppercase()

        DriverArrivalRingtonePlayer.start(this)

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 96, 48, 96)
            background = ContextCompat.getDrawable(
                this@DriverArrivalActivity,
                android.R.color.black
            )
        }

        val title = TextView(this).apply {
            text = driverName ?: if (serviceType == "delivery") "Your Driver" else "Order Ready"
            textSize = 28f
            setTextColor(ContextCompat.getColor(this@DriverArrivalActivity, android.R.color.white))
            gravity = Gravity.CENTER
        }

        val subtitle = TextView(this).apply {
            text = if (serviceType == "delivery") {
                if (driverName != null) {
                    "$driverName is here with your order. Attend your driver now."
                } else {
                    "Your order is here. Attend your driver now."
                }
            } else {
                "Your order is ready for pickup now."
            }
            textSize = 18f
            setTextColor(ContextCompat.getColor(this@DriverArrivalActivity, android.R.color.white))
            gravity = Gravity.CENTER
        }

        val orderText = TextView(this).apply {
            text = "Order #$shortId"
            textSize = 16f
            setTextColor(0xFFB8B8C2.toInt())
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 32)
        }

        val button = Button(this).apply {
            text = "I Am Coming"
            textSize = 18f
            setOnClickListener {
                DriverArrivalRingtonePlayer.stop()
                val launchIntent = Intent(this@DriverArrivalActivity, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra(EXTRA_EVENT_TYPE, "driver_arrival")
                    putExtra(EXTRA_ORDER_ID, orderId)
                    putExtra(EXTRA_DRIVER_NAME, driverName)
                    putExtra(EXTRA_SERVICE_TYPE, serviceType)
                    putExtra(EXTRA_ACKNOWLEDGE, true)
                }
                startActivity(launchIntent)
                finish()
            }
        }

        container.addView(title)
        container.addView(subtitle)
        container.addView(orderText)
        container.addView(button)

        setContentView(container)
    }

    override fun onDestroy() {
        DriverArrivalRingtonePlayer.stop()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_EVENT_TYPE = "eventType"
        const val EXTRA_ORDER_ID = "orderId"
        const val EXTRA_DRIVER_NAME = "driverName"
        const val EXTRA_SERVICE_TYPE = "serviceType"
        const val EXTRA_ACKNOWLEDGE = "acknowledge"
    }
}
