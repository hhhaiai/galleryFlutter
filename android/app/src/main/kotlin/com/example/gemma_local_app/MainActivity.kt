package com.example.gemma_local_app

import android.Manifest
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import com.example.gemma_local_app.download.ModelDownloadRepository
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.ExperimentalFlags
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
  private val runtime = GemmaLiteRtRuntime()
  private val downloader by lazy { ModelDownloadRepository(applicationContext) }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      GemmaLiteRtRuntime.METHOD_CHANNEL,
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "initialize" -> runtime.initialize(call, result)
        "generate" -> runtime.generate(call, result)
        "stop" -> runtime.stop(result)
        "dispose" -> runtime.dispose(result)
        "getExternalFilesDir" -> result.success(applicationContext.getExternalFilesDir(null)?.absolutePath)
        else -> result.notImplemented()
      }
    }

    EventChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      GemmaLiteRtRuntime.EVENT_CHANNEL,
    ).setStreamHandler(runtime)

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      DOWNLOAD_METHOD_CHANNEL,
    ).setMethodCallHandler { call, result ->
      val args = (call.arguments as? Map<*, *>)?.mapKeys { it.key.toString() } ?: emptyMap()
      try {
        when (call.method) {
          "refreshStatus" -> result.success(downloader.refreshStatus(args))
          "requestNotificationPermission" -> result.success(ensureNotificationPermission())
          "download" -> {
            ensureNotificationPermission()
            downloader.download(args)
            result.success(null)
          }
          "cancel" -> {
            downloader.cancel(args)
            result.success(null)
          }
          "delete" -> result.success(downloader.delete(args))
          else -> result.notImplemented()
        }
      } catch (throwable: Throwable) {
        result.error("DOWNLOAD_ERROR", throwable.message, null)
      }
    }

    EventChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      DOWNLOAD_EVENT_CHANNEL,
    ).setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          downloader.setEventSink(events)
        }

        override fun onCancel(arguments: Any?) {
          downloader.setEventSink(null)
        }
      }
    )
  }

  private fun ensureNotificationPermission(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
    val granted = ContextCompat.checkSelfPermission(
      this,
      Manifest.permission.POST_NOTIFICATIONS,
    ) == PackageManager.PERMISSION_GRANTED
    if (!granted) {
      ActivityCompat.requestPermissions(
        this,
        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
        NOTIFICATION_PERMISSION_REQUEST_CODE,
      )
    }
    return granted
  }

  companion object {
    private const val DOWNLOAD_METHOD_CHANNEL = "com.example.gemma_local_app/model_download"
    private const val DOWNLOAD_EVENT_CHANNEL = "com.example.gemma_local_app/model_download_events"
    private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 44002
  }
}

private data class RuntimeInitArgs(
  val modelPath: String,
  val accelerator: String,
  val supportImage: Boolean,
  val supportAudio: Boolean,
  val topK: Int,
  val topP: Double,
  val temperature: Double,
  val maxTokens: Int,
  val systemPrompt: String?,
)

private class GemmaLiteRtRuntime : EventChannel.StreamHandler {
  private val executor = Executors.newSingleThreadExecutor()
  @Volatile private var engine: Engine? = null
  @Volatile private var conversation: Conversation? = null
  private var eventSink: EventChannel.EventSink? = null

  fun initialize(call: MethodCall, result: MethodChannel.Result) {
    val args = RuntimeInitArgs(
      modelPath = call.argument<String>("modelPath") ?: run {
        result.error("INITIALIZE_FAILED", "modelPath is required", null)
        return
      },
      accelerator = call.argument<String>("accelerator") ?: "cpu",
      supportImage = call.argument<Boolean>("supportImage") ?: false,
      supportAudio = call.argument<Boolean>("supportAudio") ?: false,
      topK = call.argument<Int>("topK") ?: 64,
      topP = call.argument<Double>("topP") ?: 0.95,
      temperature = call.argument<Double>("temperature") ?: 1.0,
      maxTokens = call.argument<Int>("maxTokens") ?: 4000,
      systemPrompt = call.argument<String>("systemPrompt")?.takeIf { it.isNotBlank() },
    )

    executor.execute {
      try {
        initializeBlocking(args)
        runOnMainThread { result.success(null) }
      } catch (throwable: Throwable) {
        Log.e(TAG, "initialize failed", throwable)
        runOnMainThread { result.error("INITIALIZE_FAILED", throwable.message, null) }
      }
    }
  }

  @OptIn(ExperimentalApi::class)
  private fun initializeBlocking(args: RuntimeInitArgs) {
    closeCurrentRuntime()
    val backend = createBackend(args.accelerator)
    val engineConfig = EngineConfig(
      modelPath = args.modelPath,
      backend = backend,
      // Match Google AI Edge Gallery for Gemma multimodal chat: main backend GPU + vision GPU.
      visionBackend = if (args.supportImage) Backend.GPU() else null,
      audioBackend = null,
      maxNumTokens = args.maxTokens,
    )

    val newEngine = Engine(engineConfig)
    newEngine.initialize()

    ExperimentalFlags.enableConversationConstrainedDecoding = false
    val newConversation = newEngine.createConversation(
      ConversationConfig(
        samplerConfig = if (backend is Backend.NPU) {
          null
        } else {
          SamplerConfig(
            topK = args.topK,
            topP = args.topP,
            temperature = args.temperature,
          )
        },
        systemInstruction = args.systemPrompt?.let {
          Contents.of(Content.Text(it))
        },
        tools = listOf(),
      )
    )
    ExperimentalFlags.enableConversationConstrainedDecoding = false

    engine = newEngine
    conversation = newConversation
  }

  fun generate(call: MethodCall, result: MethodChannel.Result) {
    val prompt = call.argument<String>("prompt") ?: ""
    val imagePaths = call.argument<List<String>>("imagePaths") ?: emptyList()
    if (prompt.isBlank() && imagePaths.isEmpty()) {
      result.error("EMPTY_PROMPT", "prompt is empty.", null)
      return
    }

    executor.execute {
      val currentConversation = conversation
      if (currentConversation == null) {
        runOnMainThread { result.error("NOT_INITIALIZED", "LiteRT-LM runtime is not initialized.", null) }
        return@execute
      }

      try {
        val contents = mutableListOf<Content>()
        for (imagePath in imagePaths.take(1)) {
          val bitmap = decodeGalleryStyleBitmap(imagePath)
          val imageBytes = bitmap.toPngByteArray()
          Log.d(TAG, "image input ready: ${bitmap.width}x${bitmap.height}, pngBytes=${imageBytes.size}")
          contents.add(Content.ImageBytes(imageBytes))
        }
        if (prompt.trim().isNotEmpty()) {
          contents.add(Content.Text(prompt))
        }

        currentConversation.sendMessageAsync(
          Contents.of(contents),
          object : MessageCallback {
            override fun onMessage(message: Message) {
              runOnMainThread {
                eventSink?.success(
                  mapOf(
                    "type" to "token",
                    "text" to message.toString(),
                    "thought" to message.channels["thought"],
                  )
                )
              }
            }

            override fun onDone() {
              runOnMainThread { eventSink?.success(mapOf("type" to "done")) }
            }

            override fun onError(throwable: Throwable) {
              if (throwable is CancellationException) {
                runOnMainThread { eventSink?.success(mapOf("type" to "done")) }
              } else {
                Log.e(TAG, "generate failed", throwable)
                runOnMainThread {
                  eventSink?.success(
                    mapOf(
                      "type" to "error",
                      "message" to (throwable.message ?: "Unknown inference error"),
                    )
                  )
                }
              }
            }
          },
          emptyMap(),
        )
        runOnMainThread { result.success(null) }
      } catch (throwable: Throwable) {
        Log.e(TAG, "generate start failed", throwable)
        runOnMainThread { result.error("GENERATE_FAILED", throwable.message, null) }
      }
    }
  }

  fun stop(result: MethodChannel.Result) {
    try {
      conversation?.cancelProcess()
      result.success(null)
    } catch (throwable: Throwable) {
      result.error("STOP_FAILED", throwable.message, null)
    }
  }

  fun dispose(result: MethodChannel.Result) {
    try {
      closeCurrentRuntime()
      result.success(null)
    } catch (throwable: Throwable) {
      result.error("DISPOSE_FAILED", throwable.message, null)
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  private fun createBackend(accelerator: String): Backend {
    return when (accelerator.lowercase()) {
      "cpu" -> Backend.CPU()
      "gpu" -> Backend.GPU()
      "npu", "tpu" -> Backend.NPU()
      else -> Backend.GPU()
    }
  }

  private fun runOnMainThread(block: () -> Unit) {
    Handler(Looper.getMainLooper()).post(block)
  }

  private fun decodeGalleryStyleBitmap(imagePath: String): Bitmap {
    val imageFile = File(imagePath)
    if (!imageFile.exists()) {
      throw IllegalArgumentException("Image file not found: $imagePath")
    }
    val uri = Uri.fromFile(imageFile)
    val orientation = try {
      FileInputStream(imageFile).use { inputStream ->
        ExifInterface(inputStream).getAttributeInt(
          ExifInterface.TAG_ORIENTATION,
          ExifInterface.ORIENTATION_NORMAL,
        )
      }
    } catch (throwable: Throwable) {
      Log.w(TAG, "failed to read EXIF orientation for $imagePath", throwable)
      ExifInterface.ORIENTATION_NORMAL
    }

    val decoded = decodeSampledBitmapFromUri(uri, 1024, 1024)
      ?: throw IllegalArgumentException("Unable to decode image: $imagePath")
    return rotateBitmap(decoded, orientation)
  }

  private fun decodeSampledBitmapFromUri(uri: Uri, reqWidth: Int, reqHeight: Int): Bitmap? {
    val path = uri.path ?: return null
    val options = BitmapFactory.Options().apply {
      inJustDecodeBounds = true
      FileInputStream(path).use { BitmapFactory.decodeStream(it, null, this) }
      inSampleSize = calculateInSampleSize(this, reqWidth, reqHeight)
      inJustDecodeBounds = false
    }
    return FileInputStream(path).use { BitmapFactory.decodeStream(it, null, options) }
  }

  private fun calculateInSampleSize(
    options: BitmapFactory.Options,
    reqWidth: Int,
    reqHeight: Int,
  ): Int {
    val height = options.outHeight
    val width = options.outWidth
    var inSampleSize = 1
    if (height > reqHeight || width > reqWidth) {
      val heightRatio = (height.toFloat() / reqHeight.toFloat()).roundToInt()
      val widthRatio = (width.toFloat() / reqWidth.toFloat()).roundToInt()
      inSampleSize = max(heightRatio, widthRatio)
    }
    return inSampleSize
  }

  private fun rotateBitmap(bitmap: Bitmap, orientation: Int): Bitmap {
    val matrix = Matrix()
    when (orientation) {
      ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
      ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
      ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
      ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1.0f, 1.0f)
      ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1.0f, -1.0f)
      ExifInterface.ORIENTATION_TRANSPOSE -> {
        matrix.postRotate(90f)
        matrix.preScale(-1.0f, 1.0f)
      }
      ExifInterface.ORIENTATION_TRANSVERSE -> {
        matrix.postRotate(270f)
        matrix.preScale(-1.0f, 1.0f)
      }
      ExifInterface.ORIENTATION_NORMAL -> return bitmap
      else -> return bitmap
    }
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
  }

  private fun Bitmap.toPngByteArray(): ByteArray {
    val stream = ByteArrayOutputStream()
    compress(Bitmap.CompressFormat.PNG, 100, stream)
    return stream.toByteArray()
  }

  private fun closeCurrentRuntime() {
    try {
      conversation?.close()
    } catch (throwable: Throwable) {
      Log.w(TAG, "conversation close failed", throwable)
    }
    try {
      engine?.close()
    } catch (throwable: Throwable) {
      Log.w(TAG, "engine close failed", throwable)
    }
    conversation = null
    engine = null
  }

  companion object {
    const val METHOD_CHANNEL = "com.example.gemma_local_app/runtime"
    const val EVENT_CHANNEL = "com.example.gemma_local_app/runtime_events"
    private const val TAG = "GemmaLiteRtRuntime"
  }
}
