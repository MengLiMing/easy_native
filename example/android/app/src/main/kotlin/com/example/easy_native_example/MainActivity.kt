package com.example.easy_native_example

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.example.easy_native.EasyNative
import com.example.easy_native.EasyNativeRouteRegistry
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        EasyNative.setup(applicationContext)

        listOf("/native/a", "/native/b", "/native/c").forEach { route ->
            EasyNative.registerNativeRoute(route) { context, args ->
                Intent(context, NativeDemoActivity::class.java)
                    .putExtra("args", args?.toString() ?: "null")
            }
        }
    }
}

class NativeDemoActivity : Activity() {
    private val routeName: String
        get() = intent.getStringExtra("easy_native.route_name") ?: "unknown"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val args = intent.getStringExtra("args") ?: "empty"

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 80, 32, 32)
            setBackgroundColor(backgroundColor())
        }

        content.addView(TextView(this).apply {
            text = "Android native page\n$routeName\nargs: $args"
            textSize = 22f
            setTextColor(Color.BLACK)
            setPadding(0, 0, 0, 24)
        })

        content.addButton("push /native/b") {
            EasyNative.push(this, "/native/b", mapOf("from" to routeName))
        }
        content.addButton("replace /native/c") {
            EasyNative.replace(this, "/native/c", mapOf("from" to routeName))
        }
        content.addButton("present /native/c") {
            EasyNative.present(this, "/native/c", mapOf("from" to routeName))
        }
        content.addButton("popUntil /native/a") {
            EasyNative.popUntil("/native/a")
        }
        content.addButton("emit event: replace native c") {
            EasyNative.emitToFlutter("replaceNativeC", mapOf("from" to routeName))
        }
        content.addButton("emit event: replace flutter profile") {
            EasyNative.emitToFlutter("replaceFlutterProfile", mapOf("from" to routeName))
        }
        content.addButton("emit event: push flutter profile") {
            EasyNative.emitToFlutter("pushFlutterProfile", mapOf("from" to routeName))
        }
        content.addButton("emit event: popUntil flutter home") {
            EasyNative.emitToFlutter("popUntilFlutterHome", mapOf("from" to routeName))
        }
        content.addButton("pop") {
            EasyNative.pop()
        }
        content.addButton("pop with result") {
            EasyNative.pop("Android result from $routeName")
        }
        content.addButton("pop result int") {
            EasyNative.pop(7)
        }
        content.addButton("pop result bool") {
            EasyNative.pop(true)
        }
        content.addButton("pop result list") {
            EasyNative.pop(listOf("android", routeName, 1, true))
        }
        content.addButton("pop result map") {
            EasyNative.pop(
                mapOf(
                    "platform" to "android",
                    "route" to routeName,
                    "nested" to mapOf("ok" to true),
                    "items" to listOf(1, 2, 3),
                ),
            )
        }
        content.addButton("close all native") {
            EasyNative.closeAll()
        }
        content.addButton("close all native with result") {
            EasyNative.closeAll("Android closeAll result from $routeName")
        }
        content.addButton("close all native with map result") {
            EasyNative.closeAll(
                mapOf(
                    "platform" to "android",
                    "route" to routeName,
                    "action" to "closeAll",
                    "items" to listOf("a", 1, true),
                ),
            )
        }

        setContentView(ScrollView(this).apply {
            addView(content)
        })
    }

    private fun backgroundColor(): Int {
        return when (routeName) {
            "/native/a" -> Color.rgb(210, 245, 255)
            "/native/b" -> Color.rgb(220, 255, 220)
            else -> Color.rgb(255, 235, 210)
        }
    }

    private fun LinearLayout.addButton(label: String, onClick: () -> Unit) {
        addView(Button(context).apply {
            text = label
            setOnClickListener { onClick() }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
    }

    override fun finish() {
        super.finish()
        val exitAnimation = if (intent.getBooleanExtra(EasyNativeRouteRegistry.EXTRA_PRESENTED, false)) {
            com.example.easy_native.R.anim.easy_native_slide_out_bottom
        } else {
            com.example.easy_native.R.anim.easy_native_slide_out_right
        }
        overridePendingTransition(
            com.example.easy_native.R.anim.easy_native_hold,
            exitAnimation,
        )
    }
}
