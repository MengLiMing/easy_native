package com.example.easy_native

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.plugin.common.MethodChannel

object EasyNative {
    var applicationContext: Context? = null
        private set

    private var lifecycleRegistered = false
    private val nativeMethodHandlers:
        MutableMap<String, (Any?, MethodChannel.Result) -> Unit> = mutableMapOf()
    private val nativeEventHandlers: MutableList<(String, Any?) -> Unit> = mutableListOf()

    fun setup(context: Context) {
        EasyNativeLogger.log(EasyNativeLogLevel.INFO, "setup")
        applicationContext = context.applicationContext
        val application = context.applicationContext as? Application ?: return
        if (lifecycleRegistered) return
        lifecycleRegistered = true
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                EasyNativeFlowManager.onActivityCreated(activity)
            }

            override fun onActivityDestroyed(activity: Activity) {
                EasyNativeFlowManager.onActivityDestroyed(activity)
            }

            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        })
    }

    fun registerNativeRoute(name: String, factory: (Context, Any?) -> Intent?) {
        EasyNativeRouteRegistry.registerNativeRoute(name, factory)
    }

    fun setLogProvider(provider: ((EasyNativeLogLevel, String, Throwable?) -> Unit)?) {
        EasyNativeLogger.provider = provider
    }

    fun registerNativeMethod(method: String, handler: (Any?, MethodChannel.Result) -> Unit) {
        val methodName = method.trim()
        if (methodName.isBlank()) {
            EasyNativeLogger.log(EasyNativeLogLevel.WARNING, "ignore empty native method registration")
            return
        }
        if (nativeMethodHandlers.containsKey(methodName)) {
            EasyNativeLogger.log(EasyNativeLogLevel.WARNING, "override native method registration $methodName")
        }
        nativeMethodHandlers[methodName] = handler
    }

    fun registerNativeEventHandler(handler: (String, Any?) -> Unit) {
        nativeEventHandlers.add(handler)
    }

    internal fun handleNativeMethod(method: String, data: Any?, result: MethodChannel.Result): Boolean {
        val handler = nativeMethodHandlers[method] ?: return false
        handler(data, result)
        return true
    }

    internal fun handleNativeEvent(type: String, data: Any?) {
        nativeEventHandlers.forEach { it(type, data) }
    }

    fun emitToFlutter(type: String, data: Any? = null) {
        EasyNativePlugin.emitToFlutter(type, data)
    }

    fun invokeFlutter(method: String, data: Any? = null, result: MethodChannel.Result? = null) {
        EasyNativePlugin.invokeFlutter(method, data, result)
    }

    fun push(context: Context, routeName: String, arguments: Any? = null): Map<String, Any?> {
        return EasyNativeFlowManager.push(context, routeName, arguments)
    }

    fun replace(context: Context, routeName: String, arguments: Any? = null): Map<String, Any?> {
        return EasyNativeFlowManager.replace(context, routeName, arguments)
    }

    fun present(context: Context, routeName: String, arguments: Any? = null): Map<String, Any?> {
        return EasyNativeFlowManager.present(context, routeName, arguments)
    }

    fun pop(): Map<String, Any?> = EasyNativeFlowManager.pop()

    fun popUntil(routeName: String): Map<String, Any?> = EasyNativeFlowManager.popUntil(routeName)

    fun closeAll(): Map<String, Any?> = EasyNativeFlowManager.closeAll()
}
