package com.example.gemma_local_app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
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
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
  private val runtime = GemmaLiteRtRuntime()
  private val audioInput by lazy { AndroidAudioInput(this) }
  private val downloader by lazy { ModelDownloadRepository(applicationContext) }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (audioInput.onActivityResult(requestCode, resultCode, data)) return
    super.onActivityResult(requestCode, resultCode, data)
  }

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
      AUDIO_METHOD_CHANNEL,
    ).setMethodCallHandler { call, result ->
      try {
        when (call.method) {
          "pickAudioFile" -> audioInput.pickAudioFile(result)
          "startRecording" -> audioInput.startRecording(result)
          "stopRecording" -> audioInput.stopRecording(result)
          "cancelRecording" -> audioInput.cancelRecording(result)
          "playAudio" -> audioInput.playAudio(call, result)
          "stopPlayback" -> audioInput.stopPlayback(result)
          else -> result.notImplemented()
        }
      } catch (throwable: Throwable) {
        result.error("AUDIO_INPUT_ERROR", throwable.message, null)
      }
    }

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
    private const val AUDIO_METHOD_CHANNEL = "com.example.gemma_local_app/audio_input"
    private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 44002
  }
}

private class AndroidAudioInput(private val activity: MainActivity) {
  private var pendingPickResult: MethodChannel.Result? = null
  @Volatile private var audioRecord: AudioRecord? = null
  @Volatile private var recordingThread: Thread? = null
  @Volatile private var isRecording = false
  private var recordingFile: File? = null
  private var recordingStartedAtMs: Long = 0
  private var player: MediaPlayer? = null

  fun pickAudioFile(result: MethodChannel.Result) {
    if (pendingPickResult != null) {
      result.error("PICK_IN_PROGRESS", "Another audio picker is already open.", null)
      return
    }
    pendingPickResult = result
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
      addCategory(Intent.CATEGORY_OPENABLE)
      type = "audio/*"
    }
    activity.startActivityForResult(intent, PICK_AUDIO_REQUEST_CODE)
  }

  fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != PICK_AUDIO_REQUEST_CODE) return false
    val result = pendingPickResult
    pendingPickResult = null
    if (result == null) return true
    if (resultCode != Activity.RESULT_OK || data?.data == null) {
      result.success(null)
      return true
    }
    try {
      val uri = data.data!!
      val destination = File(activity.cacheDir, "picked_audio_${System.currentTimeMillis()}.wav")
      activity.contentResolver.openInputStream(uri)?.use { input ->
        destination.outputStream().use { output -> input.copyTo(output) }
      } ?: throw IllegalArgumentException("Unable to open selected audio")
      result.success(audioMap(destination, durationMs = readDurationMs(destination)))
    } catch (throwable: Throwable) {
      result.error("PICK_AUDIO_FAILED", throwable.message, null)
    }
    return true
  }

  fun startRecording(result: MethodChannel.Result) {
    if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.RECORD_AUDIO), RECORD_AUDIO_REQUEST_CODE)
      result.error("MIC_PERMISSION_REQUIRED", "请授权麦克风权限后重试。", null)
      return
    }
    if (audioRecord != null || isRecording) {
      result.error("ALREADY_RECORDING", "Audio recording is already running.", null)
      return
    }
    val minBuffer = AudioRecord.getMinBufferSize(
      SAMPLE_RATE,
      AudioFormat.CHANNEL_IN_MONO,
      AudioFormat.ENCODING_PCM_16BIT,
    )
    val bufferSize = max(minBuffer, SAMPLE_RATE * 2)
    val record = AudioRecord(
      MediaRecorder.AudioSource.MIC,
      SAMPLE_RATE,
      AudioFormat.CHANNEL_IN_MONO,
      AudioFormat.ENCODING_PCM_16BIT,
      bufferSize,
    )
    if (record.state != AudioRecord.STATE_INITIALIZED) {
      record.release()
      result.error("RECORD_INIT_FAILED", "AudioRecord 初始化失败。", null)
      return
    }
    val file = File(activity.cacheDir, "voice_${System.currentTimeMillis()}.wav")
    val thread = Thread {
      val pcm = ByteArrayOutputStream()
      val buffer = ByteArray(bufferSize)
      try {
        record.startRecording()
        while (isRecording) {
          val read = record.read(buffer, 0, buffer.size)
          if (read > 0) pcm.write(buffer, 0, read)
          val elapsedSec = (System.currentTimeMillis() - recordingStartedAtMs) / 1000
          if (elapsedSec >= MAX_AUDIO_SECONDS) isRecording = false
        }
        writeWavFile(file, pcm.toByteArray())
      } catch (throwable: Throwable) {
        Log.e("AndroidAudioInput", "recording failed", throwable)
      } finally {
        try { record.stop() } catch (_: Throwable) {}
        record.release()
      }
    }
    audioRecord = record
    recordingFile = file
    recordingStartedAtMs = System.currentTimeMillis()
    isRecording = true
    recordingThread = thread
    thread.start()
    result.success(null)
  }

  fun stopRecording(result: MethodChannel.Result) {
    val file = recordingFile
    if (file == null || audioRecord == null) {
      result.success(null)
      return
    }
    isRecording = false
    recordingThread?.join(1200)
    audioRecord = null
    recordingThread = null
    recordingFile = null
    val durationMs = (System.currentTimeMillis() - recordingStartedAtMs).toInt().coerceAtLeast(1000)
    result.success(audioMap(file, durationMs = durationMs))
  }

  fun cancelRecording(result: MethodChannel.Result) {
    isRecording = false
    recordingThread?.join(800)
    audioRecord = null
    recordingThread = null
    recordingFile?.delete()
    recordingFile = null
    result.success(null)
  }

  fun playAudio(call: MethodCall, result: MethodChannel.Result) {
    val path = call.argument<String>("path") ?: run {
      result.error("PATH_REQUIRED", "path is required", null)
      return
    }
    stopPlaybackInternal()
    player = MediaPlayer().apply {
      setDataSource(path)
      setOnCompletionListener { stopPlaybackInternal() }
      prepare()
      start()
    }
    result.success(null)
  }

  fun stopPlayback(result: MethodChannel.Result) {
    stopPlaybackInternal()
    result.success(null)
  }

  private fun stopPlaybackInternal() {
    try {
      player?.stop()
    } catch (_: Throwable) {
    }
    player?.release()
    player = null
  }

  private fun readDurationMs(file: File): Int {
    val probe = MediaPlayer()
    return try {
      probe.setDataSource(file.absolutePath)
      probe.prepare()
      probe.duration
    } catch (_: Throwable) {
      0
    } finally {
      probe.release()
    }
  }

  private fun audioMap(file: File, durationMs: Int): Map<String, Any> {
    return mapOf(
      "path" to file.absolutePath,
      "durationMs" to durationMs,
      "waveform" to estimateWaveform(file),
    )
  }

  private fun estimateWaveform(file: File): List<Double> {
    val bytes = file.readBytes()
    if (bytes.isEmpty()) return List(18) { 0.28 + (it % 4) * 0.12 }
    val bucketCount = 24
    val bucketSize = max(1, bytes.size / bucketCount)
    return (0 until bucketCount).map { bucket ->
      val start = bucket * bucketSize
      val end = minOf(bytes.size, start + bucketSize)
      var sum = 0L
      for (i in start until end) sum += kotlin.math.abs(bytes[i].toInt())
      ((sum.toDouble() / max(1, end - start)) / 128.0).coerceIn(0.08, 1.0)
    }
  }

  private fun writeWavFile(file: File, pcmBytes: ByteArray) {
    RandomAccessFile(file, "rw").use { wav ->
      wav.setLength(0)
      wav.writeBytes("RIFF")
      wav.writeIntLE(36 + pcmBytes.size)
      wav.writeBytes("WAVE")
      wav.writeBytes("fmt ")
      wav.writeIntLE(16)
      wav.writeShortLE(1)
      wav.writeShortLE(1)
      wav.writeIntLE(SAMPLE_RATE)
      wav.writeIntLE(SAMPLE_RATE * 2)
      wav.writeShortLE(2)
      wav.writeShortLE(16)
      wav.writeBytes("data")
      wav.writeIntLE(pcmBytes.size)
      wav.write(pcmBytes)
    }
  }

  private fun RandomAccessFile.writeIntLE(value: Int) {
    write(byteArrayOf(
      (value and 0xFF).toByte(),
      ((value shr 8) and 0xFF).toByte(),
      ((value shr 16) and 0xFF).toByte(),
      ((value shr 24) and 0xFF).toByte(),
    ))
  }

  private fun RandomAccessFile.writeShortLE(value: Int) {
    write(byteArrayOf(
      (value and 0xFF).toByte(),
      ((value shr 8) and 0xFF).toByte(),
    ))
  }

  companion object {
    private const val PICK_AUDIO_REQUEST_CODE = 55001
    private const val RECORD_AUDIO_REQUEST_CODE = 55002
    private const val SAMPLE_RATE = 16000
    private const val MAX_AUDIO_SECONDS = 30
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
  @Volatile private var initArgs: RuntimeInitArgs? = null

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
    val backend = createBackend(args.accelerator, args.supportImage)
    Log.d(TAG, "initializing runtime: backend=$backend, supportImage=${args.supportImage}, supportAudio=${args.supportAudio}")
    val engineConfig = EngineConfig(
      modelPath = args.modelPath,
      backend = backend,
      visionBackend = if (args.supportImage) Backend.GPU() else null,
      // Match Google AI Edge Gallery: audio backend is CPU-only and enabled
      // only for explicit audio requests. Text stays CPU-only; image stays GPU vision.
      audioBackend = if (args.supportAudio) Backend.CPU() else null,
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
    initArgs = args
  }

  fun generate(call: MethodCall, result: MethodChannel.Result) {
    val prompt = call.argument<String>("prompt") ?: ""
    val imagePaths = call.argument<List<String>>("imagePaths") ?: emptyList()
    val audioPaths = call.argument<List<String>>("audioPaths") ?: emptyList()
    if (prompt.isBlank() && imagePaths.isEmpty() && audioPaths.isEmpty()) {
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
        for (audioPath in audioPaths.take(1)) {
          val audioBytes = readAudioForGemma(audioPath)
          Log.d(TAG, "audio input ready: wavBytes=${audioBytes.size}")
          contents.add(Content.AudioBytes(audioBytes))
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

  private fun createBackend(accelerator: String, supportImage: Boolean): Backend {
    return when (accelerator.lowercase()) {
      "cpu" -> Backend.CPU()
      "gpu" -> if (supportImage) Backend.GPU() else Backend.CPU()
      "npu", "tpu" -> Backend.NPU()
      else -> if (supportImage) Backend.GPU() else Backend.CPU()
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

  private fun readAudioForGemma(audioPath: String): ByteArray {
    val audioFile = File(audioPath)
    if (!audioFile.exists()) {
      throw IllegalArgumentException("Audio file not found: $audioPath")
    }
    val bytes = audioFile.readBytes()
    if (bytes.size < 44 || bytes.copyOfRange(0, 4).toString(Charsets.US_ASCII) != "RIFF") {
      throw IllegalArgumentException("Gemma audio requires a WAV file. Please record in-app or pick a WAV file.")
    }
    // LiteRT-LM Android Content.AudioBytes is decoded by miniaudio. The native
    // decoder needs a valid audio container, otherwise nativeSendMessageAsync
    // fails with miniaudio error -10 and Flutter stays in the streaming state.
    // Normalize to model-friendly 16 kHz mono 16-bit PCM, then wrap it back in
    // a minimal WAV container.
    return normalizeWavForGemma(bytes, MAX_AUDIO_SECONDS)
  }

  private fun extractMono16BitPcm(wavBytes: ByteArray, maxSeconds: Int): ByteArray {
    val riff = wavBytes.copyOfRange(0, 4).toString(Charsets.US_ASCII)
    val wave = wavBytes.copyOfRange(8, 12).toString(Charsets.US_ASCII)
    if (riff != "RIFF" || wave != "WAVE") {
      throw IllegalArgumentException("Invalid WAV header")
    }
    var offset = 12
    var channels = 1
    var sampleRate = SAMPLE_RATE
    var bitsPerSample = 16
    var dataOffset = -1
    var dataSize = 0
    while (offset + 8 <= wavBytes.size) {
      val chunkId = wavBytes.copyOfRange(offset, offset + 4).toString(Charsets.US_ASCII)
      val chunkSize = ByteBuffer.wrap(wavBytes, offset + 4, 4).order(ByteOrder.LITTLE_ENDIAN).int
      val chunkDataOffset = offset + 8
      if (chunkDataOffset + chunkSize > wavBytes.size) break
      when (chunkId) {
        "fmt " -> {
          val fmt = ByteBuffer.wrap(wavBytes, chunkDataOffset, chunkSize).order(ByteOrder.LITTLE_ENDIAN)
          val audioFormat = fmt.short.toInt()
          if (audioFormat != 1) throw IllegalArgumentException("Only PCM WAV is supported for Gemma audio")
          channels = fmt.short.toInt()
          sampleRate = fmt.int
          fmt.int // byte rate
          fmt.short // block align
          bitsPerSample = fmt.short.toInt()
        }
        "data" -> {
          dataOffset = chunkDataOffset
          dataSize = chunkSize
          break
        }
      }
      offset = chunkDataOffset + chunkSize + (chunkSize and 1)
    }
    if (dataOffset < 0 || dataSize <= 0) throw IllegalArgumentException("WAV data chunk not found")

    val rawData = wavBytes.copyOfRange(dataOffset, dataOffset + dataSize)
    val pcmSamples = when (bitsPerSample) {
      8 -> ShortArray(rawData.size) { i -> (((rawData[i].toInt() and 0xFF) - 128) * 256).toShort() }
      16 -> {
        val shortBuffer = ByteBuffer.wrap(rawData).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        ShortArray(shortBuffer.remaining()).also { shortBuffer.get(it) }
      }
      else -> throw IllegalArgumentException("Only 8/16-bit PCM WAV is supported for Gemma audio")
    }

    val monoSamples = if (channels == 1) {
      pcmSamples
    } else {
      val frames = pcmSamples.size / channels
      ShortArray(frames) { frame ->
        var sum = 0
        for (channel in 0 until channels) sum += pcmSamples[frame * channels + channel].toInt()
        (sum / channels).toShort()
      }
    }

    val normalizedSamples = if (sampleRate == SAMPLE_RATE) {
      monoSamples
    } else {
      resampleMono(monoSamples, sampleRate, SAMPLE_RATE)
    }
    val trimmedSamples = normalizedSamples.copyOfRange(
      0,
      minOf(normalizedSamples.size, SAMPLE_RATE * maxSeconds),
    )
    val output = ByteBuffer.allocate(trimmedSamples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
    for (sample in trimmedSamples) output.putShort(sample)
    return output.array()
  }

  private fun normalizeWavForGemma(wavBytes: ByteArray, maxSeconds: Int): ByteArray {
    val pcmBytes = extractMono16BitPcm(wavBytes, maxSeconds)
    val output = ByteArrayOutputStream()
    output.write("RIFF".toByteArray(Charsets.US_ASCII))
    output.writeIntLE(36 + pcmBytes.size)
    output.write("WAVE".toByteArray(Charsets.US_ASCII))
    output.write("fmt ".toByteArray(Charsets.US_ASCII))
    output.writeIntLE(16)
    output.writeShortLE(1)
    output.writeShortLE(1)
    output.writeIntLE(SAMPLE_RATE)
    output.writeIntLE(SAMPLE_RATE * 2)
    output.writeShortLE(2)
    output.writeShortLE(16)
    output.write("data".toByteArray(Charsets.US_ASCII))
    output.writeIntLE(pcmBytes.size)
    output.write(pcmBytes)
    return output.toByteArray()
  }

  private fun ByteArrayOutputStream.writeIntLE(value: Int) {
    write(byteArrayOf(
      (value and 0xFF).toByte(),
      ((value shr 8) and 0xFF).toByte(),
      ((value shr 16) and 0xFF).toByte(),
      ((value shr 24) and 0xFF).toByte(),
    ))
  }

  private fun ByteArrayOutputStream.writeShortLE(value: Int) {
    write(byteArrayOf(
      (value and 0xFF).toByte(),
      ((value shr 8) and 0xFF).toByte(),
    ))
  }

  private fun resampleMono(inputSamples: ShortArray, originalSampleRate: Int, targetSampleRate: Int): ShortArray {
    if (originalSampleRate <= 0 || originalSampleRate == targetSampleRate) return inputSamples
    val ratio = targetSampleRate.toDouble() / originalSampleRate.toDouble()
    val outputLength = max(1, (inputSamples.size * ratio).roundToInt())
    return ShortArray(outputLength) { index ->
      val position = index / ratio
      val left = position.toInt().coerceIn(0, inputSamples.lastIndex)
      val right = minOf(left + 1, inputSamples.lastIndex)
      val fraction = position - left
      (inputSamples[left] * (1.0 - fraction) + inputSamples[right] * fraction).roundToInt().toShort()
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
    initArgs = null
  }

  companion object {
    const val METHOD_CHANNEL = "com.example.gemma_local_app/runtime"
    const val EVENT_CHANNEL = "com.example.gemma_local_app/runtime_events"
    private const val TAG = "GemmaLiteRtRuntime"
    private const val SAMPLE_RATE = 16000
    private const val MAX_AUDIO_SECONDS = 30
  }
}
