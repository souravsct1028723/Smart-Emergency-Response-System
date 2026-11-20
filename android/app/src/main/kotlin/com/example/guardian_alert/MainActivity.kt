package com.example.guardian_alert

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.telephony.SmsManager.RESULT_ERROR_GENERIC_FAILURE
import android.telephony.SmsManager.RESULT_ERROR_NO_SERVICE
import android.telephony.SmsManager.RESULT_ERROR_NULL_PDU
import android.telephony.SmsManager.RESULT_ERROR_RADIO_OFF
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "guardian_alert/sms"
    private val SMS_PERMISSION_REQUEST_CODE = 1001

    private val smsSentReceiver = object : BroadcastReceiver() {

        override fun onReceive(context: Context?, intent: Intent?) {

            when (resultCode) {

                RESULT_OK -> {
                    println("SMS STATUS: SMS_SENT = SUCCESS")
                }

                RESULT_ERROR_GENERIC_FAILURE -> {
                    println("SMS STATUS: SMS_SENT = GENERIC_FAILURE")
                }

                RESULT_ERROR_NO_SERVICE -> {
                    println("SMS STATUS: SMS_SENT = NO_SERVICE")
                }

                RESULT_ERROR_NULL_PDU -> {
                    println("SMS STATUS: SMS_SENT = NULL_PDU")
                }

                RESULT_ERROR_RADIO_OFF -> {
                    println("SMS STATUS: SMS_SENT = RADIO_OFF")
                }

                else -> {
                    println(
                        "SMS STATUS: SMS_SENT = UNKNOWN ($resultCode)"
                    )
                }
            }
        }
    }

    private val smsDeliveredReceiver = object : BroadcastReceiver() {

        override fun onReceive(context: Context?, intent: Intent?) {

            if (resultCode == RESULT_OK) {
                println("SMS STATUS: SMS_DELIVERED = SUCCESS")
            } else {
                println(
                    "SMS STATUS: SMS_DELIVERED = FAILED ($resultCode)"
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        // Allow Guardian Alert to appear over the lock screen
        if (android.os.Build.VERSION.SDK_INT >=
            android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        registerReceiver(
            smsSentReceiver,
            IntentFilter("GUARDIAN_SMS_SENT"),
            Context.RECEIVER_NOT_EXPORTED
        )

        registerReceiver(
            smsDeliveredReceiver,
            IntentFilter("GUARDIAN_SMS_DELIVERED"),
            Context.RECEIVER_NOT_EXPORTED
        )
    }
    
    override fun onDestroy() {

        unregisterReceiver(smsSentReceiver)
        unregisterReceiver(smsDeliveredReceiver)

        super.onDestroy()
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "sendSms" -> {

                    val phoneNumber =
                        call.argument<String>("phoneNumber")

                    val message =
                        call.argument<String>("message")

                    if (phoneNumber == null || message == null) {

                        result.error(
                            "INVALID_ARGUMENT",
                            "Phone number or message is missing",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    if (
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.SEND_SMS
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {

                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.SEND_SMS),
                            SMS_PERMISSION_REQUEST_CODE
                        )

                        result.error(
                            "PERMISSION_REQUIRED",
                            "SMS permission required",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    try {

                        val smsManager = SmsManager.getDefault()

                        val sentIntent = PendingIntent.getBroadcast(
                            this,
                            1001,
                            Intent("GUARDIAN_SMS_SENT"),
                            PendingIntent.FLAG_UPDATE_CURRENT or
                                    PendingIntent.FLAG_IMMUTABLE
                        )

                        val deliveredIntent = PendingIntent.getBroadcast(
                            this,
                            1002,
                            Intent("GUARDIAN_SMS_DELIVERED"),
                            PendingIntent.FLAG_UPDATE_CURRENT or
                                    PendingIntent.FLAG_IMMUTABLE
                        )

                        smsManager.sendTextMessage(
                            phoneNumber,
                            null,
                            message,
                            sentIntent,
                            deliveredIntent
                        )

                        println(
                            "SMS SERVICE: SMS request submitted to $phoneNumber"
                        )

                        result.success(true)

                    } catch (e: Exception) {

                        println(
                            "SMS SERVICE ERROR: ${e.message}"
                        )

                        result.error(
                            "SMS_FAILED",
                            e.message,
                            null
                        )
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}