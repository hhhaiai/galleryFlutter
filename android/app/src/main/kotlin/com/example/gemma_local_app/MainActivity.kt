package com.example.gemma_local_app

import android.util.Log
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

class MainActivity : FlutterActivity() {
  private val runtime = GemmaLiteRtRuntime()

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
        else -> result.notImplemented()
      }
    }

    EventChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      GemmaLiteRtRuntime.EVENT_CHANNEL,
    ).setStreamHandler(runtime)
  }
}

private class GemmaLiteRtRuntime : EventChannel.StreamHandler {
  private var engine: Engine? = null
  private var conversation: Conversation? = null
  private var eventSink: EventChannel.EventSink? = null

  @OptIn(ExperimentalApi::class)
  fun initialize(call: MethodCall, result: MethodChannel.Result) {
    try {
      closeCurrentRuntime()

      val modelPath = call.argument<String>("modelPath") ?: error("modelPath is required")
      val accelerator = call.argument<String>("accelerator") ?: "gpu"
      val supportImage = call.argument<Boolean>("supportImage") ?: false
      val supportAudio = call.argument<Boolean>("supportAudio") ?: false
      val topK = call.argument<Int>("topK") ?: 64
      val topP = call.argument<Double>("topP") ?: 0.95
      val temperature = call.argument<Double>("temperature") ?: 1.0
      val maxTokens = call.argument<Int>("maxTokens") ?: 4000
      val systemPrompt = call.argument<String>("systemPrompt")?.takeIf { it.isNotBlank() }

      val backend = createBackend(accelerator)
      val engineConfig = EngineConfig(
        modelPath = modelPath,
        backend = backend,
        visionBackend = if (supportImage) Backend.GPU() else null,
        audioBackend = if (supportAudio) Backend.CPU() else null,
        maxNumTokens = maxTokens,
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
              topK = topK,
              topP = topP,
              temperature = temperature,
            )
          },
          systemInstruction = systemPrompt?.let {
            Contents.of(Content.Text(it))
          },
          tools = listOf(),
        )
      )
      ExperimentalFlags.enableConversationConstrainedDecoding = false

      engine = newEngine
      conversation = newConversation
      result.success(null)
    } catch (throwable: Throwable) {
      Log.e(TAG, "initialize failed", throwable)
      result.error("INITIALIZE_FAILED", throwable.message, null)
    }
  }

  fun generate(call: MethodCall, result: MethodChannel.Result) {
    val currentConversation = conversation
    if (currentConversation == null) {
      result.error("NOT_INITIALIZED", "LiteRT-LM runtime is not initialized.", null)
      return
    }

    val prompt = call.argument<String>("prompt") ?: ""
    if (prompt.isBlank()) {
      result.error("EMPTY_PROMPT", "prompt is empty.", null)
      return
    }

    try {
      currentConversation.sendMessageAsync(
        Contents.of(Content.Text(prompt)),
        object : MessageCallback {
          override fun onMessage(message: Message) {
            eventSink?.success(
              mapOf(
                "type" to "token",
                "text" to message.toString(),
                "thought" to message.channels["thought"],
              )
            )
          }

          override fun onDone() {
            eventSink?.success(mapOf("type" to "done"))
          }

          override fun onError(throwable: Throwable) {
            if (throwable is CancellationException) {
              eventSink?.success(mapOf("type" to "done"))
            } else {
              Log.e(TAG, "generate failed", throwable)
              eventSink?.success(
                mapOf(
                  "type" to "error",
                  "message" to (throwable.message ?: "Unknown inference error"),
                )
              )
            }
          }
        },
        emptyMap(),
      )
      result.success(null)
    } catch (throwable: Throwable) {
      Log.e(TAG, "generate start failed", throwable)
      result.error("GENERATE_FAILED", throwable.message, null)
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
