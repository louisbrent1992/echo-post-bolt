package com.example.echopost

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.echo_post.NativeVideoPlayerPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the native video player plugin
        flutterEngine.plugins.add(NativeVideoPlayerPlugin())
    }
}
