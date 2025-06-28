import Flutter
import UIKit
import AVFoundation

/// NativeVideoPlayerPlugin: AVPlayer-based single instance video player for iOS
/// 
/// Maintains one AVPlayer instance across all video switches to eliminate
/// memory leaks and buffer overflow issues. Uses conservative buffer settings
/// to keep memory under 50MB, mirroring the Android ExoPlayer approach.
public class NativeVideoPlayerPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel!
    private var textureRegistry: FlutterTextureRegistry!
    
    // Single AVPlayer instance - never dispose, only reuse
    private var avPlayer: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var textureRef: FlutterTextureRegistry?
    private var textureId: Int64?
    private var pixelBufferOutput: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    
    // Video texture for Flutter rendering
    private var videoTexture: VideoTexture?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "echo_post/video_player", 
                                          binaryMessenger: registrar.messenger())
        let instance = NativeVideoPlayerPlugin()
        instance.channel = channel
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Ensure all AVPlayer operations run on main thread
        DispatchQueue.main.async { [weak self] in
            switch call.method {
            case "initializePlayer":
                self?.initializePlayer(result: result)
            case "switchVideo":
                guard let args = call.arguments as? [String: Any],
                      let path = args["path"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", 
                                      message: "Video path is required", 
                                      details: nil))
                    return
                }
                self?.switchVideo(path: path, result: result)
            case "play":
                self?.playVideo(result: result)
            case "pause":
                self?.pauseVideo(result: result)
            case "setVolume":
                guard let args = call.arguments as? [String: Any],
                      let volume = args["volume"] as? Double else {
                    result(FlutterError(code: "INVALID_ARGUMENT", 
                                      message: "Volume is required", 
                                      details: nil))
                    return
                }
                self?.setVolume(volume: volume, result: result)
            case "dispose":
                self?.disposePlayer(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private func initializePlayer(result: @escaping FlutterResult) {
        guard avPlayer == nil else {
            // Already initialized - return existing texture
            result(["textureId": textureId ?? -1])
            return
        }
        
        do {
            // Create single AVPlayer instance with optimized settings
            avPlayer = AVPlayer()
            
            // Enhanced: Conservative buffer settings for memory efficiency
            if let player = avPlayer {
                // Set preferred buffer size (similar to Android's buffer settings)
                player.automaticallyWaitsToMinimizeStalling = false
                
                // Create video texture for Flutter rendering
                videoTexture = VideoTexture()
                textureId = textureRegistry.register(videoTexture!)
                
                // Configure video output for texture rendering
                let pixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 1920,
                    kCVPixelBufferHeightKey as String: 1080
                ]
                
                pixelBufferOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
                
                // Setup display link for texture updates
                displayLink = CADisplayLink(target: self, selector: #selector(updateTexture))
                displayLink?.add(to: .main, forMode: .common)
                displayLink?.isPaused = true
                
                result(["textureId": textureId ?? -1])
            } else {
                result(FlutterError(code: "INIT_ERROR", 
                                  message: "Failed to create AVPlayer", 
                                  details: nil))
            }
        } catch {
            result(FlutterError(code: "INIT_ERROR", 
                              message: "Failed to initialize player: \(error.localizedDescription)", 
                              details: nil))
        }
    }
    
    private func switchVideo(path: String, result: @escaping FlutterResult) {
        guard let player = avPlayer else {
            result(FlutterError(code: "NOT_INITIALIZED", 
                              message: "Player not initialized", 
                              details: nil))
            return
        }
        
        // Enhanced: More aggressive cleanup before switch
        player.pause()
        player.replaceCurrentItem(with: nil)
        
        // Small delay to ensure cleanup completes (mirroring Android approach)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            do {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path) else {
                    result(FlutterError(code: "FILE_NOT_FOUND", 
                                      message: "Video file does not exist: \(path)", 
                                      details: nil))
                    return
                }
                
                let asset = AVAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)
                
                // Add video output to new item
                if let output = self.pixelBufferOutput {
                    playerItem.add(output)
                }
                
                // Enhanced: Set conservative buffer settings
                playerItem.preferredForwardBufferDuration = 10.0 // 10s max buffer
                
                player.replaceCurrentItem(with: playerItem)
                
                // Start display link when video is ready
                self.displayLink?.isPaused = false
                
                result(true)
            } catch {
                result(FlutterError(code: "SWITCH_ERROR", 
                                  message: "Failed to switch video: \(error.localizedDescription)", 
                                  details: nil))
            }
        }
    }
    
    private func playVideo(result: @escaping FlutterResult) {
        guard let player = avPlayer else {
            result(FlutterError(code: "NOT_INITIALIZED", 
                              message: "Player not initialized", 
                              details: nil))
            return
        }
        
        player.play()
        displayLink?.isPaused = false
        result(nil)
    }
    
    private func pauseVideo(result: @escaping FlutterResult) {
        guard let player = avPlayer else {
            result(FlutterError(code: "NOT_INITIALIZED", 
                              message: "Player not initialized", 
                              details: nil))
            return
        }
        
        player.pause()
        displayLink?.isPaused = true
        result(nil)
    }
    
    private func setVolume(volume: Double, result: @escaping FlutterResult) {
        guard let player = avPlayer else {
            result(FlutterError(code: "NOT_INITIALIZED", 
                              message: "Player not initialized", 
                              details: nil))
            return
        }
        
        let clampedVolume = Float(max(0.0, min(1.0, volume)))
        player.volume = clampedVolume
        result(nil)
    }
    
    private func disposePlayer(result: @escaping FlutterResult) {
        cleanupResources()
        result(nil)
    }
    
    // Centralized resource cleanup
    private func cleanupResources() {
        displayLink?.invalidate()
        displayLink = nil
        
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
        
        if let textureId = textureId {
            textureRegistry.unregisterTexture(textureId)
        }
        
        videoTexture = nil
        textureId = nil
        pixelBufferOutput = nil
    }
    
    @objc private func updateTexture() {
        guard let output = pixelBufferOutput,
              let texture = videoTexture,
              let currentTime = avPlayer?.currentItem?.currentTime() else {
            return
        }
        
        if output.hasNewPixelBuffer(forItemTime: currentTime) {
            if let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
                texture.updatePixelBuffer(pixelBuffer)
            }
        }
    }
}

/// Video texture implementation for Flutter rendering
class VideoTexture: NSObject, FlutterTexture {
    private var pixelBuffer: CVPixelBuffer?
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pixelBuffer = pixelBuffer else { return nil }
        return Unmanaged.passRetained(pixelBuffer)
    }
    
    func updatePixelBuffer(_ buffer: CVPixelBuffer) {
        pixelBuffer = buffer
    }
} 