package com.example.easy_native

import android.content.Context
import android.content.Intent

object EasyNativeRouteRegistry {
    const val EXTRA_ROUTE_NAME = "easy_native.route_name"
    const val EXTRA_PRESENTED = "easy_native.presented"

    private val nativeRoutes: MutableMap<String, (Context, Any?) -> Intent?> = mutableMapOf()

    fun registerNativeRoute(name: String, factory: (Context, Any?) -> Intent?) {
        val routeName = name.trim()
        if (routeName.isBlank()) {
            EasyNativeLogger.log(EasyNativeLogLevel.WARNING, "ignore empty native route registration")
            return
        }
        if (nativeRoutes.containsKey(routeName)) {
            EasyNativeLogger.log(EasyNativeLogLevel.WARNING, "override native route registration $routeName")
        } else {
            EasyNativeLogger.log(EasyNativeLogLevel.INFO, "register native route $routeName")
        }
        nativeRoutes[routeName] = factory
    }

    fun isNativeRoute(name: String): Boolean = nativeRoutes.containsKey(name)

    fun getNativeIntent(context: Context, name: String, args: Any?): Intent? {
        return nativeRoutes[name]?.invoke(context, args)?.apply {
            putExtra(EXTRA_ROUTE_NAME, name)
        }
    }
}
