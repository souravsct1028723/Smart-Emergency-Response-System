package com.example.guardian_alert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {

        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {

            Log.d(
                "GuardianAlert",
                "BOOT_COMPLETED received"
            )

            // The Flutter foreground service will be started
            // when the Guardian Alert Flutter engine is initialized.
        }
    }
}