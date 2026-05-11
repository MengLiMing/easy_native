package com.example.easy_native

enum class EasyNativeLogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR,
}

object EasyNativeLogger {
    var provider: ((EasyNativeLogLevel, String, Throwable?) -> Unit)? = null
    var enabled: Boolean = true

    fun log(level: EasyNativeLogLevel, message: String, throwable: Throwable? = null) {
        if (!enabled) return
        provider?.invoke(level, message, throwable) ?: run {
            val suffix = throwable?.let { " error=$it" }.orEmpty()
            println("[EasyNative][${level.name.lowercase()}] $message$suffix")
        }
    }
}
