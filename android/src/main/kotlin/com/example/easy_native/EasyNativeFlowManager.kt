package com.example.easy_native

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Looper

enum class NativeFlowState {
    IDLE,
    ACTIVE,
    CLOSING,
}

// Coordinates a native flow. It is not a stack manager; Android owns the real Activity stack.
object EasyNativeFlowManager {
    private val trackedActivities: MutableList<Activity> = mutableListOf()
    private var state: NativeFlowState = NativeFlowState.IDLE

    fun onActivityCreated(activity: Activity) {
        if (routeNameOf(activity) != null && !trackedActivities.contains(activity)) {
            trackedActivities.add(activity)
            if (state != NativeFlowState.CLOSING) {
                state = NativeFlowState.ACTIVE
            }
        }
    }

    fun onActivityDestroyed(activity: Activity) {
        trackedActivities.remove(activity)
        if (trackedActivities.isEmpty()) {
            state = NativeFlowState.IDLE
        }
    }

    fun hasActiveNativeFlow(): Boolean = state != NativeFlowState.IDLE || trackedActivities.isNotEmpty()

    fun push(context: Context, routeName: String, arguments: Any?): Map<String, Any?> {
        checkCanRoute("nativePush")?.let { return it }
        val intent = EasyNativeRouteRegistry.getNativeIntent(context, routeName, arguments)
            ?: return failure("Native route is not registered: $routeName", "nativePush")
        val hadActiveFlow = hasActiveNativeFlow()
        val startResult = start(context, intent, "nativePush")
        if (!startResult.success) return startResult.result
        applyPushAnimation(context)
        state = NativeFlowState.ACTIVE
        EasyNativeLogger.log(EasyNativeLogLevel.DEBUG, "native push $routeName")
        return success(if (hadActiveFlow) "nativePush" else "openNativeFlow")
    }

    fun present(context: Context, routeName: String, arguments: Any?): Map<String, Any?> {
        checkCanRoute("nativePresent")?.let { return it }
        val intent = EasyNativeRouteRegistry.getNativeIntent(context, routeName, arguments)
            ?: return failure("Native route is not registered: $routeName", "nativePresent")
        intent.putExtra(EasyNativeRouteRegistry.EXTRA_PRESENTED, true)
        val startResult = start(context, intent, "nativePresent")
        if (!startResult.success) return startResult.result
        applyPresentAnimation(context)
        state = NativeFlowState.ACTIVE
        EasyNativeLogger.log(EasyNativeLogLevel.DEBUG, "native present $routeName")
        return success("nativePresent")
    }

    fun replace(context: Context, routeName: String, arguments: Any?): Map<String, Any?> {
        checkCanRoute("nativeReplace")?.let { return it }
        val intent = EasyNativeRouteRegistry.getNativeIntent(context, routeName, arguments)
            ?: return failure("Native route is not registered: $routeName", "nativeReplace")
        val top = trackedActivities.lastOrNull()
        val startResult = start(context, intent, "nativeReplace")
        if (!startResult.success) return startResult.result
        applyPushAnimation(context)
        state = NativeFlowState.ACTIVE
        top?.finish()
        EasyNativeLogger.log(EasyNativeLogLevel.DEBUG, "native replace $routeName")
        return success("nativeReplace")
    }

    fun pop(): Map<String, Any?> {
        checkCanRoute("nativePop")?.let { return it }
        val top = trackedActivities.lastOrNull()
            ?: return failure("No active native flow", "nativePop")

        if (trackedActivities.size <= 1) {
            state = NativeFlowState.CLOSING
        }

        top.finish()
        applyCloseAnimation(top)
        EasyNativeLogger.log(EasyNativeLogLevel.DEBUG, "native pop")
        return success("nativePop")
    }

    fun popUntil(routeName: String): Map<String, Any?> {
        checkCanRoute("nativePopUntil")?.let { return it }
        val index = trackedActivities.indexOfLast { routeNameOf(it) == routeName }
        if (index < 0) {
            return failure("Route not found in native stack: $routeName", "nativePopUntil")
        }
        val toFinish = trackedActivities.drop(index + 1)
        toFinish.reversed().forEach {
            it.finish()
            applyCloseAnimation(it)
        }
        EasyNativeLogger.log(EasyNativeLogLevel.DEBUG, "native popUntil $routeName")
        return success("nativePopUntil")
    }

    fun pushAndRemoveUntil(
        context: Context,
        routeName: String,
        arguments: Any?,
        untilRoute: String?,
    ): Map<String, Any?> {
        checkCanRoute("nativePushAndRemoveUntil")?.let { return it }
        val index = untilRoute?.let { target ->
            trackedActivities.indexOfLast { routeNameOf(it) == target }
        } ?: -1
        val toFinish = if (index >= 0) trackedActivities.drop(index + 1) else trackedActivities.toList()
        val intent = EasyNativeRouteRegistry.getNativeIntent(context, routeName, arguments)
            ?: return failure("Native route is not registered: $routeName", "nativePushAndRemoveUntil")
        val startResult = start(context, intent, "nativePushAndRemoveUntil")
        if (!startResult.success) return startResult.result
        applyPushAnimation(context)
        state = NativeFlowState.ACTIVE
        toFinish.reversed().forEach {
            it.finish()
            applyCloseAnimation(it)
        }
        EasyNativeLogger.log(EasyNativeLogLevel.DEBUG, "native pushAndRemoveUntil $routeName")
        return success("nativePushAndRemoveUntil")
    }

    fun closeAll(): Map<String, Any?> {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            return failure("Must be called from main thread", "closeNativeFlow")
        }
        if (trackedActivities.isEmpty()) {
            state = NativeFlowState.IDLE
            return success("noActiveNativeFlow")
        }
        if (state == NativeFlowState.CLOSING) {
            return success("nativeFlowAlreadyClosing")
        }
        state = NativeFlowState.CLOSING
        trackedActivities.toList().reversed().forEach {
            it.finish()
            applyCloseAnimation(it)
        }
        EasyNativeLogger.log(EasyNativeLogLevel.DEBUG, "close native flow")
        return success("closeNativeFlow")
    }

    private fun start(context: Context, intent: Intent, action: String): StartResult {
        return try {
            if (context !is Activity) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            StartResult(true, success(action))
        } catch (throwable: Throwable) {
            EasyNativeLogger.log(EasyNativeLogLevel.ERROR, "startActivity failed", throwable)
            StartResult(false, failure("Failed to start native route: ${throwable.message}", action))
        }
    }

    private data class StartResult(
        val success: Boolean,
        val result: Map<String, Any?>,
    )

    private fun applyPushAnimation(context: Context) {
        (context as? Activity)?.overridePendingTransition(
            R.anim.easy_native_slide_in_right,
            R.anim.easy_native_hold,
        )
    }

    private fun applyPresentAnimation(context: Context) {
        (context as? Activity)?.overridePendingTransition(
            R.anim.easy_native_slide_in_bottom,
            R.anim.easy_native_hold,
        )
    }

    private fun applyCloseAnimation(activity: Activity) {
        if (activity.intent.getBooleanExtra(EasyNativeRouteRegistry.EXTRA_PRESENTED, false)) {
            applyDismissAnimation(activity)
        } else {
            applyPopAnimation(activity)
        }
    }

    private fun applyPopAnimation(activity: Activity) {
        activity.overridePendingTransition(
            R.anim.easy_native_hold,
            R.anim.easy_native_slide_out_right,
        )
    }

    private fun applyDismissAnimation(activity: Activity) {
        activity.overridePendingTransition(
            R.anim.easy_native_hold,
            R.anim.easy_native_slide_out_bottom,
        )
    }

    private fun routeNameOf(activity: Activity): String? {
        return activity.intent.getStringExtra(EasyNativeRouteRegistry.EXTRA_ROUTE_NAME)
    }

    private fun success(action: String, data: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        return mapOf(
            "success" to true,
            "action" to action,
            "data" to data,
        )
    }

    private fun failure(message: String, action: String): Map<String, Any?> {
        return mapOf(
            "success" to false,
            "action" to action,
            "message" to message,
        )
    }

    private fun checkCanRoute(action: String): Map<String, Any?>? {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            return failure("Must be called from main thread", action)
        }
        if (state == NativeFlowState.CLOSING) {
            EasyNativeLogger.log(EasyNativeLogLevel.WARNING, "reject $action while native flow is closing")
            return failure("Native flow is closing", action)
        }
        return null
    }
}
