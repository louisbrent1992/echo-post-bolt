package com.example.echopost

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.io.File

/// NativeVideoPlayerPlugin: ExoPlayer-based single instance video player
/// 
/// Maintains one ExoPlayer instance across all video switches to eliminate
/// memory leaks and buffer overflow issues from VideoPlayerController disposal.
/// Uses conservative buffer settings (3-10s) to keep memory under 50MB.
class NativeVideoPlayerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var textureRegistry: TextureRegistry
    private lateinit var context: Context
    
    // Single ExoPlayer instance - never dispose, only reuse
    private var exoPlayer: ExoPlayer? = null
    private var surface: Surface? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    
    // Main thread handler for ExoPlayer operations
    private val mainHandler = Handler(Looper.getMainLooper())
    
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "echo_post/video_player")
        channel.setMethodCallHandler(this)
        textureRegistry = flutterPluginBinding.textureRegistry
        // Fixed: Use application context to prevent memory leaks
        context = flutterPluginBinding.applicationContext
    }
    
    // Fixed: Proper cleanup on detach
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        
        // Clean up native resources on main thread
        mainHandler.post {
            cleanupResources()
        }
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        // Fixed: Ensure all ExoPlayer operations run on main thread
        mainHandler.post {
            when (call.method) {
                "initializePlayer" -> initializePlayer(result)
                "switchVideo" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        switchVideo(path, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Video path is required", null)
                    }
                }
                "pause" -> pauseVideo(result)
                "play" -> playVideo(result)
                "setVolume" -> {
                    val volume = call.argument<Double>("volume")
                    if (volume != null) {
                        setVolume(volume, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Volume is required", null)
                    }
                }
                "getVideoSize" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        getVideoSize(path, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Video path is required", null)
                    }
                }
                "dispose" -> disposePlayer(result)
                else -> result.notImplemented()
            }
        }
    }
    
    private fun initializePlayer(result: Result) {
        try {
            if (exoPlayer != null) {
                // Already initialized - return existing texture
                result.success(mapOf("textureId" to textureEntry?.id()))
                return
            }
            
            // Create texture for video rendering
            textureEntry = textureRegistry.createSurfaceTexture()
            surface = Surface(textureEntry!!.surfaceTexture())
            
            // Enhanced: More conservative buffer settings for memory efficiency
            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(
                    3_000,   // 3s min buffer (very conservative)
                    10_000,  // 10s max buffer (reduced from 15s)
                    1_500,   // 1.5s playback buffer
                    3_000    // 3s rebuffer
                )
                .build()
            
            // Create single ExoPlayer instance with optimized settings
            exoPlayer = ExoPlayer.Builder(context)
                .setLoadControl(loadControl)
                .build()
                .apply {
                    setVideoSurface(surface)
                    playWhenReady = false
                    volume = 1.0f
                }
            
            val textureId = textureEntry!!.id()
            result.success(mapOf("textureId" to textureId))
            
        } catch (e: Exception) {
            result.error("INIT_ERROR", "Failed to initialize player: ${e.message}", null)
        }
    }
    
    private fun switchVideo(path: String, result: Result) {
        val player = exoPlayer
        if (player == null) {
            result.error("NOT_INITIALIZED", "Player not initialized", null)
            return
        }
        
        try {
            // Enhanced: More aggressive cleanup before switch
            player.stop()
            player.clearMediaItems()
            
            // Small delay to ensure cleanup completes
            mainHandler.postDelayed({
                try {
                    val file = File(path)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "Video file does not exist: $path", null)
                        return@postDelayed
                    }
                    
                    val mediaItem = MediaItem.fromUri(file.toURI().toString())
                    player.setMediaItem(mediaItem)
                    player.prepare()
                    
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SWITCH_ERROR", "Failed to switch video: ${e.message}", null)
                }
            }, 50) // 50ms delay for cleanup
            
        } catch (e: Exception) {
            result.error("SWITCH_ERROR", "Failed to prepare video switch: ${e.message}", null)
        }
    }
    
    private fun playVideo(result: Result) {
        val player = exoPlayer
        if (player == null) {
            result.error("NOT_INITIALIZED", "Player not initialized", null)
            return
        }
        
        try {
            player.play()
            result.success(null)
        } catch (e: Exception) {
            result.error("PLAY_ERROR", "Failed to play video: ${e.message}", null)
        }
    }
    
    private fun pauseVideo(result: Result) {
        val player = exoPlayer
        if (player == null) {
            result.error("NOT_INITIALIZED", "Player not initialized", null)
            return
        }
        
        try {
            player.pause()
            result.success(null)
        } catch (e: Exception) {
            result.error("PAUSE_ERROR", "Failed to pause video: ${e.message}", null)
        }
    }
    
    private fun setVolume(volume: Double, result: Result) {
        val player = exoPlayer
        if (player == null) {
            result.error("NOT_INITIALIZED", "Player not initialized", null)
            return
        }
        
        try {
            val clampedVolume = volume.coerceIn(0.0, 1.0).toFloat()
            player.volume = clampedVolume
            result.success(null)
        } catch (e: Exception) {
            result.error("VOLUME_ERROR", "Failed to set volume: ${e.message}", null)
        }
    }
    
    private fun getVideoSize(path: String, result: Result) {
        try {
            // Use MediaMetadataRetriever to read width/height
            val retriever = MediaMetadataRetriever().apply {
                setDataSource(path)
            }
            val width = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
            )!!.toInt()
            val height = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
            )!!.toInt()
            retriever.release()

            result.success(mapOf("width" to width, "height" to height))
        } catch (e: Exception) {
            result.error("SIZE_ERROR", "Failed to get video size: ${e.message}", null)
        }
    }
    
    // Enhanced: Explicit disposal method for clean shutdown
    private fun disposePlayer(result: Result) {
        try {
            cleanupResources()
            result.success(null)
        } catch (e: Exception) {
            result.error("DISPOSE_ERROR", "Failed to dispose player: ${e.message}", null)
        }
    }
    
    // Centralized resource cleanup
    private fun cleanupResources() {
        try {
            exoPlayer?.release()
            surface?.release()
            textureEntry?.release()
            
            exoPlayer = null
            surface = null
            textureEntry = null
            
        } catch (e: Exception) {
            // Log error but don't crash during cleanup
            println("Warning: Error during resource cleanup: ${e.message}")
        }
    }
} 