package com.example.easy_native

import android.app.Activity
import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class EasyNativePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    companion object {
        private var routerChannelRef: MethodChannel? = null
        private var eventChannel: MethodChannel? = null
        private var methodChannel: MethodChannel? = null

        fun emitToFlutter(type: String, data: Any? = null) {
            eventChannel?.invokeMethod(
                "emitToFlutter",
                mapOf("type" to type, "data" to data),
            )
        }

        fun invokeFlutter(method: String, data: Any? = null, result: Result? = null) {
            methodChannel?.invokeMethod(
                "invokeFlutter",
                mapOf("method" to method, "data" to data),
                result,
            )
        }

        fun completeRoute(
            requestId: String,
            resultValue: Any? = null,
            action: String = "nativeRouteComplete",
        ) {
            routerChannelRef?.invokeMethod(
                "completeRoute",
                mapOf(
                    "requestId" to requestId,
                    "result" to resultValue,
                    "success" to true,
                    "action" to action,
                ),
            )
        }
    }

    private lateinit var routerChannel: MethodChannel
    private var activity: Activity? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        routerChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "easy_native/router")
        routerChannel.setMethodCallHandler(this)
        routerChannelRef = routerChannel

        eventChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "easy_native/event_bus")
        eventChannel?.setMethodCallHandler(this)

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "easy_native/methods")
        methodChannel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        EasyNativeLogger.log(EasyNativeLogLevel.DEBUG, "method call ${call.method}")
        when (call.method) {
            "isNativeRoute" -> {
                val routeName = call.argument<String>("routeName").orEmpty()
                result.success(EasyNativeRouteRegistry.isNativeRoute(routeName))
            }
            "hasActiveNativeFlow" -> result.success(EasyNativeFlowManager.hasActiveNativeFlow())
            "push" -> result.success(route(call, "push"))
            "replace" -> result.success(route(call, "replace"))
            "present" -> result.success(route(call, "present"))
            "pushAndRemoveUntil" -> result.success(route(call, "pushAndRemoveUntil"))
            "pop" -> result.success(EasyNativeFlowManager.pop(call.argument<Any?>("result")))
            "popUntil" -> {
                val routeName = call.argument<String>("routeName").orEmpty()
                result.success(EasyNativeFlowManager.popUntil(routeName))
            }
            "closeAll" -> result.success(EasyNativeFlowManager.closeAll(call.argument<Any?>("result")))
            "emitToNative" -> {
                val type = call.argument<String>("type").orEmpty()
                val data = call.argument<Any?>("data")
                EasyNative.handleNativeEvent(type, data)
                result.success(true)
            }
            "invokeNative" -> {
                val method = call.argument<String>("method").orEmpty().trim()
                val data = call.argument<Any?>("data")
                if (!EasyNative.handleNativeMethod(method, data, result)) {
                    result.notImplemented()
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        routerChannel.setMethodCallHandler(null)
        routerChannelRef = null
        eventChannel?.setMethodCallHandler(null)
        methodChannel?.setMethodCallHandler(null)
        eventChannel = null
        methodChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        EasyNative.setup(binding.activity.applicationContext)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        EasyNative.setup(binding.activity.applicationContext)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun route(call: MethodCall, action: String): Map<String, Any?> {
        val routeName = call.argument<String>("routeName").orEmpty()
        val arguments = call.argument<Any?>("arguments")
        val requestId = call.argument<String>("requestId")
        val context = currentContext()
            ?: return mapOf(
                "success" to false,
                "action" to action,
                "message" to "No Android context is available",
            )

        return when (action) {
            "push" -> EasyNativeFlowManager.push(context, routeName, arguments, requestId)
            "replace" -> {
                if (EasyNativeFlowManager.hasActiveNativeFlow()) {
                    EasyNativeFlowManager.replace(
                        context,
                        routeName,
                        arguments,
                        call.argument<Any?>("result"),
                        requestId,
                    )
                } else {
                    EasyNativeFlowManager.push(context, routeName, arguments, requestId)
                }
            }
            "present" -> EasyNativeFlowManager.present(context, routeName, arguments, requestId)
            "pushAndRemoveUntil" -> EasyNativeFlowManager.pushAndRemoveUntil(
                context,
                routeName,
                arguments,
                call.argument<String>("untilRoute"),
                requestId,
            )
            else -> mapOf(
                "success" to false,
                "action" to action,
                "message" to "Unknown route action",
            )
        }
    }

    private fun currentContext(): Context? {
        return activity
    }
}
