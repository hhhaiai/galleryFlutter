package com.example.gemma_local_app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors

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
      visionBackend = null,
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
    if (prompt.isBlank()) {
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
        currentConversation.sendMessageAsync(
          Contents.of(Content.Text(prompt)),
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
