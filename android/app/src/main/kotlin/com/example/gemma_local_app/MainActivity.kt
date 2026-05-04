package com.example.gemma_local_app

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.content.pm.PackageManager
import android.database.Cursor
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
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
import com.google.ai.edge.litertlm.Tool
import com.google.ai.edge.litertlm.ToolParam
import com.google.ai.edge.litertlm.ToolSet
import com.google.ai.edge.litertlm.tool
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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt
import org.json.JSONObject

class MainActivity : FlutterActivity() {
  private val runtime by lazy { GemmaLiteRtRuntime(this) }
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

    EventChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      AUDIO_EVENT_CHANNEL,
    ).setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          audioInput.setEventSink(events)
        }

        override fun onCancel(arguments: Any?) {
          audioInput.setEventSink(null)
        }
      }
    )

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
    private const val AUDIO_EVENT_CHANNEL = "com.example.gemma_local_app/audio_input_events"
    private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 44002
  }
}

private class AndroidAudioInput(private val activity: MainActivity) {
  private val mainHandler = Handler(Looper.getMainLooper())
  private var pendingPickResult: MethodChannel.Result? = null
  @Volatile private var audioEventSink: EventChannel.EventSink? = null
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
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    activity.startActivityForResult(intent, PICK_AUDIO_REQUEST_CODE)
  }

  fun setEventSink(events: EventChannel.EventSink?) {
    audioEventSink = events
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
    Thread {
      try {
        val destination = preparePickedAudioForGemma(data.data!!)
        val audioInfo = audioMap(destination, durationMs = readDurationMs(destination))
        mainHandler.post { result.success(audioInfo) }
      } catch (throwable: Throwable) {
        Log.e("AndroidAudioInput", "pick audio failed", throwable)
        mainHandler.post {
          result.error("PICK_AUDIO_FAILED", throwable.message, null)
        }
      }
    }.start()
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
      var lastMeterPushMs = 0L
      var stopState = "stopped"
      var stopReason = "manual"
      try {
        record.startRecording()
        emitAudioEvent(mapOf("type" to "recording", "state" to "started"))
        while (isRecording) {
          val read = record.read(buffer, 0, buffer.size)
          if (read > 0) {
            pcm.write(buffer, 0, read)
            val now = System.currentTimeMillis()
            if (now - lastMeterPushMs >= METER_PUSH_INTERVAL_MS) {
              lastMeterPushMs = now
              emitAudioEvent(
                mapOf(
                  "type" to "level",
                  "amplitude" to calculatePeakAmplitude(buffer, read).toDouble() / Short.MAX_VALUE.toDouble(),
                  "elapsedMs" to (now - recordingStartedAtMs).toInt().coerceAtLeast(0),
                )
              )
            }
          }
          val elapsedSec = (System.currentTimeMillis() - recordingStartedAtMs) / 1000
          if (elapsedSec >= MAX_AUDIO_SECONDS) {
            stopReason = "maxDuration"
            isRecording = false
          }
        }
        writeWavFile(file, pcm.toByteArray())
      } catch (throwable: Throwable) {
        stopState = "failed"
        Log.e("AndroidAudioInput", "recording failed", throwable)
      } finally {
        emitAudioEvent(mapOf("type" to "recording", "state" to stopState, "reason" to stopReason))
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
    emitAudioEvent(mapOf("type" to "recording", "state" to "stopped", "reason" to "manual"))
    result.success(audioMap(file, durationMs = durationMs))
  }

  fun cancelRecording(result: MethodChannel.Result) {
    isRecording = false
    recordingThread?.join(800)
    audioRecord = null
    recordingThread = null
    recordingFile?.delete()
    recordingFile = null
    emitAudioEvent(mapOf("type" to "recording", "state" to "cancelled"))
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

  private fun emitAudioEvent(event: Map<String, Any>) {
    mainHandler.post { audioEventSink?.success(event) }
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

  private fun resolvePickedAudioExtension(uri: Uri): String {
    val nameFromCursor = activity.contentResolver.query(
      uri,
      arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
      null,
      null,
      null,
    )?.use { cursor: Cursor ->
      if (cursor.moveToFirst()) {
        cursor.getString(0)
      } else {
        null
      }
    }
    val candidate = nameFromCursor ?: uri.lastPathSegment ?: ""
    val extension = candidate.substringAfterLast('.', "").lowercase()
    return extension.ifBlank { "audio" }
  }

  private fun calculatePeakAmplitude(buffer: ByteArray, bytesRead: Int): Int {
    if (bytesRead <= 1) return 0
    val shortBuffer = ByteBuffer.wrap(buffer, 0, bytesRead)
      .order(ByteOrder.LITTLE_ENDIAN)
      .asShortBuffer()
    var maxAmplitude = 0
    while (shortBuffer.hasRemaining()) {
      maxAmplitude = max(maxAmplitude, abs(shortBuffer.get().toInt()))
    }
    return maxAmplitude
  }

  private fun preparePickedAudioForGemma(uri: Uri): File {
    val extension = resolvePickedAudioExtension(uri)
    return if (isLikelyWav(uri, extension)) {
      val destination = File(activity.cacheDir, "picked_audio_${System.currentTimeMillis()}.wav")
      activity.contentResolver.openInputStream(uri)?.use { input ->
        destination.outputStream().use { output -> input.copyTo(output) }
      } ?: throw IllegalArgumentException("Unable to open selected audio")
      destination
    } else {
      val destination = File(activity.cacheDir, "picked_audio_${System.currentTimeMillis()}.wav")
      transcodeAudioUriToGemmaWav(uri, destination)
      destination
    }
  }

  private fun isLikelyWav(uri: Uri, extension: String): Boolean {
    if (extension == "wav" || extension == "wave") return true
    val mimeType = activity.contentResolver.getType(uri)?.lowercase() ?: return false
    return mimeType == "audio/wav" || mimeType == "audio/x-wav"
  }

  private fun transcodeAudioUriToGemmaWav(uri: Uri, destination: File) {
    val extractor = MediaExtractor()
    var codec: MediaCodec? = null
    var tempDecodeSource: File? = null
    var outputSampleRate = SAMPLE_RATE
    var outputChannels = 1
    val pcmBytes = ByteArrayOutputStream()
    try {
      val descriptor = activity.contentResolver.openAssetFileDescriptor(uri, "r")
        ?: throw IllegalArgumentException("Unable to open selected audio")
      descriptor.use {
        if (it.length >= 0) {
          extractor.setDataSource(it.fileDescriptor, it.startOffset, it.length)
        } else {
          // Some Android document providers return UNKNOWN_LENGTH for audio
          // streams. MediaExtractor can reject a negative length, so copy the
          // URI to a temp file and decode from a normal file path instead.
          tempDecodeSource = File(
            activity.cacheDir,
            "decode_source_${System.currentTimeMillis()}.${resolvePickedAudioExtension(uri)}",
          )
          activity.contentResolver.openInputStream(uri)?.use { input ->
            tempDecodeSource!!.outputStream().use { output -> input.copyTo(output) }
          } ?: throw IllegalArgumentException("Unable to read selected audio")
          extractor.setDataSource(tempDecodeSource!!.absolutePath)
        }
      }
      val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
        extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
      } ?: throw IllegalArgumentException("未找到可解码的音频轨道。")
      extractor.selectTrack(trackIndex)
      val inputFormat = extractor.getTrackFormat(trackIndex)
      val mime = inputFormat.getString(MediaFormat.KEY_MIME)
        ?: throw IllegalArgumentException("音频 MIME 类型缺失。")
      outputSampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
      outputChannels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
      codec = MediaCodec.createDecoderByType(mime)
      codec.configure(inputFormat, null, null, 0)
      codec.start()
      val bufferInfo = MediaCodec.BufferInfo()
      var inputDone = false
      var outputDone = false
      while (!outputDone) {
        if (!inputDone) {
          val inputIndex = codec.dequeueInputBuffer(CODEC_TIMEOUT_US)
          if (inputIndex >= 0) {
            val inputBuffer = codec.getInputBuffer(inputIndex)
              ?: throw IllegalStateException("音频输入 buffer 不可用。")
            val sampleSize = extractor.readSampleData(inputBuffer, 0)
            if (sampleSize < 0) {
              codec.queueInputBuffer(
                inputIndex,
                0,
                0,
                0L,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
              )
              inputDone = true
            } else {
              codec.queueInputBuffer(
                inputIndex,
                0,
                sampleSize,
                extractor.sampleTime,
                0,
              )
              extractor.advance()
            }
          }
        }

        when (val outputIndex = codec.dequeueOutputBuffer(bufferInfo, CODEC_TIMEOUT_US)) {
          MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
          MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
            val outputFormat = codec.outputFormat
            outputSampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            outputChannels = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            if (outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
              val pcmEncoding = outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
              if (pcmEncoding != AudioFormat.ENCODING_PCM_16BIT) {
                throw IllegalArgumentException("暂仅支持可解码为 16-bit PCM 的音频文件。")
              }
            }
          }
          else -> if (outputIndex >= 0) {
            if (bufferInfo.size > 0) {
              val outputBuffer = codec.getOutputBuffer(outputIndex)
                ?: throw IllegalStateException("音频输出 buffer 不可用。")
              outputBuffer.position(bufferInfo.offset)
              outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
              val chunk = ByteArray(bufferInfo.size)
              outputBuffer.get(chunk)
              pcmBytes.write(chunk)
            }
            codec.releaseOutputBuffer(outputIndex, false)
            if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
              outputDone = true
            }
          }
        }
      }
    } finally {
      try { codec?.stop() } catch (_: Throwable) {}
      try { codec?.release() } catch (_: Throwable) {}
      try { extractor.release() } catch (_: Throwable) {}
      try { tempDecodeSource?.delete() } catch (_: Throwable) {}
    }
    val normalizedPcm = normalizeDecodedPcmForGemma(
      pcmBytes.toByteArray(),
      outputSampleRate,
      outputChannels,
      MAX_AUDIO_SECONDS,
    )
    writeWavFile(destination, normalizedPcm)
  }

  private fun normalizeDecodedPcmForGemma(
    pcmBytes: ByteArray,
    sampleRate: Int,
    channels: Int,
    maxSeconds: Int,
  ): ByteArray {
    if (pcmBytes.isEmpty()) return pcmBytes
    val shortBuffer = ByteBuffer.wrap(pcmBytes)
      .order(ByteOrder.LITTLE_ENDIAN)
      .asShortBuffer()
    val inputSamples = ShortArray(shortBuffer.remaining()).also { shortBuffer.get(it) }
    val monoSamples = if (channels <= 1) {
      inputSamples
    } else {
      val frames = inputSamples.size / channels
      ShortArray(frames) { frame ->
        var sum = 0
        for (channel in 0 until channels) {
          sum += inputSamples[frame * channels + channel].toInt()
        }
        (sum / channels).toShort()
      }
    }
    val resampled = if (sampleRate == SAMPLE_RATE) {
      monoSamples
    } else {
      resampleMono(monoSamples, sampleRate, SAMPLE_RATE)
    }
    val trimmed = resampled.copyOfRange(0, minOf(resampled.size, SAMPLE_RATE * maxSeconds))
    return ByteBuffer.allocate(trimmed.size * 2)
      .order(ByteOrder.LITTLE_ENDIAN)
      .apply { for (sample in trimmed) putShort(sample) }
      .array()
  }

  private fun resampleMono(
    inputSamples: ShortArray,
    originalSampleRate: Int,
    targetSampleRate: Int,
  ): ShortArray {
    if (originalSampleRate <= 0 || originalSampleRate == targetSampleRate) {
      return inputSamples
    }
    val ratio = targetSampleRate.toDouble() / originalSampleRate.toDouble()
    val outputLength = max(1, (inputSamples.size * ratio).roundToInt())
    return ShortArray(outputLength) { index ->
      val position = index / ratio
      val left = position.toInt().coerceIn(0, inputSamples.lastIndex)
      val right = minOf(left + 1, inputSamples.lastIndex)
      val fraction = position - left
      (inputSamples[left] * (1.0 - fraction) + inputSamples[right] * fraction)
        .roundToInt()
        .toShort()
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
    val samples = readWavPcm16Samples(file.readBytes())
      ?: return List(18) { 0.28 + (it % 4) * 0.12 }
    if (samples.isEmpty()) return List(18) { 0.08 }
    val bucketCount = 24
    val bucketSize = max(1, samples.size / bucketCount)
    return (0 until bucketCount).map { bucket ->
      val start = bucket * bucketSize
      val end = minOf(samples.size, start + bucketSize)
      if (start >= end) return@map 0.08
      var sum = 0L
      for (i in start until end) sum += abs(samples[i].toInt()).toLong()
      ((sum.toDouble() / max(1, end - start)) / Short.MAX_VALUE.toDouble())
        .coerceIn(0.08, 1.0)
    }
  }

  private fun readWavPcm16Samples(bytes: ByteArray): ShortArray? {
    if (bytes.size < 44) return null
    if (bytes.copyOfRange(0, 4).toString(Charsets.US_ASCII) != "RIFF") return null
    if (bytes.copyOfRange(8, 12).toString(Charsets.US_ASCII) != "WAVE") return null
    var offset = 12
    var channels = 1
    var bitsPerSample = 16
    var audioFormat = 1
    var dataOffset = -1
    var dataSize = 0
    while (offset + 8 <= bytes.size) {
      val chunkId = bytes.copyOfRange(offset, offset + 4).toString(Charsets.US_ASCII)
      val chunkSize = ByteBuffer.wrap(bytes, offset + 4, 4).order(ByteOrder.LITTLE_ENDIAN).int
      val chunkDataOffset = offset + 8
      if (chunkSize < 0 || chunkDataOffset + chunkSize > bytes.size) break
      when (chunkId) {
        "fmt " -> {
          if (chunkSize < 16) return null
          val fmt = ByteBuffer.wrap(bytes, chunkDataOffset, chunkSize).order(ByteOrder.LITTLE_ENDIAN)
          audioFormat = fmt.short.toInt()
          channels = fmt.short.toInt().coerceAtLeast(1)
          fmt.int // sample rate
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
    if (audioFormat != 1 || bitsPerSample != 16 || dataOffset < 0 || dataSize <= 1) {
      return null
    }
    val shortBuffer = ByteBuffer.wrap(bytes, dataOffset, dataSize)
      .order(ByteOrder.LITTLE_ENDIAN)
      .asShortBuffer()
    val interleaved = ShortArray(shortBuffer.remaining()).also { shortBuffer.get(it) }
    if (channels == 1) return interleaved
    val frames = interleaved.size / channels
    return ShortArray(frames) { frame ->
      var sum = 0
      for (channel in 0 until channels) sum += interleaved[frame * channels + channel].toInt()
      (sum / channels).toShort()
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
    private const val METER_PUSH_INTERVAL_MS = 120L
    private const val CODEC_TIMEOUT_US = 10_000L
    private const val SAMPLE_RATE = 16000
    private const val MAX_AUDIO_SECONDS = 30
  }
}

private data class GemmaBuiltinSkill(
  val name: String,
  val description: String,
  val instructions: String,
)


private class AndroidSkillJsExecutor(private val activity: Activity) {
  private val mainHandler = Handler(Looper.getMainLooper())

  fun run(skillName: String, scriptName: String, data: String, secret: String = ""): String {
    if (Looper.myLooper() == Looper.getMainLooper()) {
      throw IllegalStateException("JS skill execution cannot block the Android main thread.")
    }
    val safeSkillName = skillName.trim()
    val safeScriptName = scriptName.trim().ifEmpty { "index.html" }
    validateAssetPath(safeSkillName, safeScriptName)
    val assetPath = "skills/$safeSkillName/scripts/$safeScriptName"
    activity.assets.open(assetPath).use { }

    val latch = CountDownLatch(1)
    val completed = AtomicBoolean(false)
    var resultText: String? = null
    var errorText: String? = null

    fun complete(result: String?, error: String?) {
      if (!completed.compareAndSet(false, true)) return
      resultText = result
      errorText = error
      latch.countDown()
    }

    mainHandler.post {
      var webView: WebView? = null
      lateinit var timeoutRunnable: Runnable
      fun cleanup() {
        mainHandler.removeCallbacks(timeoutRunnable)
        val view = webView
        webView = null
        view?.stopLoading()
        view?.removeJavascriptInterface("AiEdgeGallery")
        view?.destroy()
      }
      timeoutRunnable = Runnable {
        complete(null, "JS skill timed out after 30 seconds.")
        cleanup()
      }
      try {
        val bridge = object {
          @JavascriptInterface
          fun onResultReady(result: String?) {
            mainHandler.post {
              complete(result ?: "", null)
              cleanup()
            }
          }
        }
        webView = WebView(activity).apply {
          settings.javaScriptEnabled = true
          settings.domStorageEnabled = true
          settings.allowFileAccess = true
          settings.allowContentAccess = false
          webChromeClient = object : WebChromeClient() {}
          webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
              val safeData = JSONObject.quote(data.trim().ifEmpty { "{}" })
              val safeSecret = JSONObject.quote(secret)
              val script = """
                (async function() {
                  try {
                    var startTs = Date.now();
                    while (typeof ai_edge_gallery_get_result !== 'function' && Date.now() - startTs <= 10000) {
                      await new Promise(function(resolve) { setTimeout(resolve, 100); });
                    }
                    if (typeof ai_edge_gallery_get_result !== 'function') {
                      AiEdgeGallery.onResultReady(JSON.stringify({error: 'ai_edge_gallery_get_result is not defined by this skill script.'}));
                      return;
                    }
                    var result = await ai_edge_gallery_get_result($safeData, $safeSecret);
                    AiEdgeGallery.onResultReady(String(result || ''));
                  } catch (e) {
                    AiEdgeGallery.onResultReady(JSON.stringify({error: String(e && e.message ? e.message : e)}));
                  }
                })();
              """.trimIndent()
              view?.evaluateJavascript(script, null)
            }
          }
          addJavascriptInterface(bridge, "AiEdgeGallery")
        }
        mainHandler.postDelayed(timeoutRunnable, 30_000L)
        webView?.loadUrl("file:///android_asset/$assetPath")
      } catch (throwable: Throwable) {
        complete(null, throwable.message ?: "Unable to start JS skill WebView.")
        cleanup()
      }
    }

    if (!latch.await(35, TimeUnit.SECONDS)) {
      throw IllegalStateException("JS skill timed out before receiving a bridge result.")
    }
    errorText?.let { throw IllegalStateException(it) }
    return resultText ?: ""
  }

  private fun validateAssetPath(skillName: String, scriptName: String) {
    val skillNameOk = Regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{1,63}$").matches(skillName)
    if (!skillNameOk) throw IllegalArgumentException("Invalid skill name for bundled JS asset: $skillName")
    if (
      scriptName.isBlank() ||
        scriptName.startsWith("/") ||
        scriptName.contains("..") ||
        scriptName.contains("\\") ||
        !scriptName.endsWith(".html")
    ) {
      throw IllegalArgumentException("Invalid JS skill script name: $scriptName")
    }
  }
}

private class GemmaSkillToolSet(
  private val context: Activity,
  enabledSkillNames: List<String>,
  enabledSkillDetails: List<GemmaBuiltinSkill>,
  private val onToolResult: (Map<String, Any?>) -> Unit = {},
) : ToolSet {
  private val enabledSkills: List<GemmaBuiltinSkill> =
    if (enabledSkillDetails.isNotEmpty()) {
      enabledSkillDetails
    } else if (enabledSkillNames.isEmpty()) {
      BUILTIN_SKILLS
    } else {
      BUILTIN_SKILLS.filter { skill -> enabledSkillNames.contains(skill.name) }
    }

  @Tool(description = "Loads a skill by name and returns its full instructions.")
  fun loadSkill(
    @ToolParam(description = "The name of the skill to load.") skillName: String,
  ): Map<String, String> {
    val skill = enabledSkills.find { it.name == skillName.trim() }
      ?: return mapOf(
        "skill_name" to skillName,
        "status" to "failed",
        "error" to "Skill not found or not enabled.",
      )
    val skillContent = "---\nname: ${skill.name}\ndescription: ${skill.description}\n---\n\n${skill.instructions}"
    Log.d(TAG, "loadSkill: ${skill.name}")
    return mapOf(
      "skill_name" to skill.name,
      "skill_instructions" to skillContent,
      "status" to "succeeded",
    )
  }

  @Tool(description = "Runs a bundled JS skill in the Android local WebView sandbox.")
  fun runJs(
    @ToolParam(description = "The name of skill.") skillName: String,
    @ToolParam(description = "The script name to run. Use 'index.html' if not provided by user.") scriptName: String,
    @ToolParam(description = "The data JSON string to pass to the script.") data: String,
  ): Map<String, String> {
    Log.d(TAG, "runJs: skill=$skillName script=$scriptName data=$data")
    val skill = enabledSkills.find { it.name == skillName.trim() }
      ?: return mapOf(
        "skill_name" to skillName,
        "script_name" to scriptName,
        "status" to "failed",
        "error" to "Skill not found or not enabled.",
      )
    return runCatching {
      val result = AndroidSkillJsExecutor(context).run(
        skillName = skill.name,
        scriptName = scriptName,
        data = data,
      )
      normalizeJsResult(skill.name, scriptName, data, result)
    }.getOrElse { throwable ->
      Log.e(TAG, "runJs failed. skill=$skillName script=$scriptName", throwable)
      mapOf(
        "skill_name" to skill.name,
        "script_name" to scriptName.ifBlank { "index.html" },
        "status" to "failed",
        "error" to (throwable.message ?: "JS skill execution failed."),
      )
    }
  }

  private fun normalizeJsResult(
    skillName: String,
    scriptName: String,
    data: String,
    rawResult: String,
  ): Map<String, String> {
    val json = runCatching { JSONObject(rawResult.ifBlank { "{}" }) }.getOrNull()
      ?: return mapOf(
        "skill_name" to skillName,
        "script_name" to scriptName.ifBlank { "index.html" },
        "data" to data,
        "status" to "succeeded",
        "result" to rawResult,
      )
    val error = json.optString("error").takeIf { it.isNotBlank() && it != "null" }
    if (error != null) {
      return mapOf(
        "skill_name" to skillName,
        "script_name" to scriptName.ifBlank { "index.html" },
        "data" to data,
        "status" to "failed",
        "error" to error,
      )
    }
    val resultText = json.optString("result").takeIf { it.isNotBlank() && it != "null" }
    val image = json.optJSONObject("image")
    val webview = json.optJSONObject("webview")
    val displayNotes = mutableListOf<String>()
    val imagePath = image
      ?.optString("base64")
      ?.takeIf { it.isNotBlank() && it != "null" }
      ?.let { saveSkillImage(skillName, it) }
    if (imagePath != null) {
      displayNotes.add("JS skill produced image output; the generated image is attached below.")
    }
    val webviewUrl = webview?.optString("url")?.takeIf { it.isNotBlank() && it != "null" }
    if (webview != null) {
      displayNotes.add(
        if (webviewUrl != null) {
          "JS skill produced webview output: $webviewUrl. Flutter embedded webview rendering is pending."
        } else {
          "JS skill produced webview output; Flutter embedded webview rendering is pending."
        }
      )
    }
    val normalizedResult = listOfNotNull(resultText, displayNotes.takeIf { it.isNotEmpty() }?.joinToString(" "))
      .joinToString("\n")
      .ifBlank { json.toString() }
    if (imagePath != null || webviewUrl != null) {
      onToolResult(
        buildMap<String, Any?> {
          put("skill_name", skillName)
          put("script_name", scriptName.ifBlank { "index.html" })
          put("status", "succeeded")
          put("result", resultText ?: "")
          if (imagePath != null) put("image_path", imagePath)
          if (webviewUrl != null) put("webview_url", webviewUrl)
          put("webview", webview?.toString())
        }
      )
    }
    return mapOf(
      "skill_name" to skillName,
      "script_name" to scriptName.ifBlank { "index.html" },
      "data" to data,
      "status" to "succeeded",
      "result" to normalizedResult,
      *listOfNotNull(
        imagePath?.let { "image_path" to it },
        webviewUrl?.let { "webview_url" to it },
      ).toTypedArray(),
    )
  }

  private fun saveSkillImage(skillName: String, base64Value: String): String {
    val payload = base64Value.substringAfter(",", base64Value).trim()
    val extension = when {
      base64Value.startsWith("data:image/jpeg") -> "jpg"
      base64Value.startsWith("data:image/jpg") -> "jpg"
      base64Value.startsWith("data:image/webp") -> "webp"
      else -> "png"
    }
    val safeSkillName = skillName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
    val file = File(context.cacheDir, "skill_${safeSkillName}_${System.currentTimeMillis()}.$extension")
    file.writeBytes(Base64.decode(payload, Base64.DEFAULT))
    return file.absolutePath
  }

  @Tool(description = "Run an Android intent. It is used by skills to perform platform actions.")
  fun runIntent(
    @ToolParam(description = "The intent to run.") intent: String,
    @ToolParam(description = "A JSON string containing the parameter values required for the intent.") parameters: String,
  ): Map<String, String> {
    Log.d(TAG, "runIntent: intent=$intent parameters=$parameters")
    return when (intent.trim()) {
      "send_email" -> startSendEmailIntent(parameters)
      else -> mapOf(
        "action" to intent,
        "parameters" to parameters,
        "status" to "failed",
        "error" to "Unsupported intent in current Flutter extraction.",
      )
    }
  }

  private fun startSendEmailIntent(parameters: String): Map<String, String> {
    val json = runCatching { JSONObject(parameters.ifBlank { "{}" }) }.getOrNull()
    val email = json?.optString("extra_email")?.takeIf { it.isNotBlank() }
      ?: return mapOf("status" to "failed", "error" to "extra_email is required")
    val subject = json.optString("extra_subject")
    val body = json.optString("extra_text")
    val latch = CountDownLatch(1)
    var status = "started"
    var error = ""
    context.runOnUiThread {
      try {
        val emailIntent = Intent(Intent.ACTION_SENDTO).apply {
          data = Uri.parse("mailto:$email")
          putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
          putExtra(Intent.EXTRA_SUBJECT, subject)
          putExtra(Intent.EXTRA_TEXT, body)
        }
        context.startActivity(Intent.createChooser(emailIntent, "Send email"))
      } catch (throwable: ActivityNotFoundException) {
        status = "failed"
        error = throwable.message ?: "No email app found"
      } catch (throwable: Throwable) {
        status = "failed"
        error = throwable.message ?: "Unable to start email intent"
      } finally {
        latch.countDown()
      }
    }
    latch.await(2, TimeUnit.SECONDS)
    val result = mutableMapOf(
      "action" to "send_email",
      "status" to status,
      "extra_email" to email,
      "extra_subject" to subject,
      "extra_text" to body,
    )
    if (error.isNotBlank()) result["error"] = error
    return result
  }

  companion object {
    private const val TAG = "GemmaSkillToolSet"
    private val BUILTIN_SKILLS = listOf(
      GemmaBuiltinSkill(
        name = "calculate-hash",
        description = "Calculate the hash of a given text.",
        instructions = "Call the run_js tool with scriptName index.html and data JSON containing text, the text to calculate hash for.",
      ),
      GemmaBuiltinSkill(
        name = "query-wikipedia",
        description = "Query summary from Wikipedia for a given topic.",
        instructions = "Call the run_js tool with scriptName index.html and data JSON containing topic and lang. Extract only the primary entity/person/event as topic.",
      ),
      GemmaBuiltinSkill(
        name = "qr-code",
        description = "Generates a QR code for the given url.",
        instructions = "Call the run_js tool with data JSON containing url, the URL or text to encode.",
      ),
      GemmaBuiltinSkill(
        name = "send-email",
        description = "Send an email.",
        instructions = "Call the run_intent tool with intent send_email and parameters JSON containing extra_email, extra_subject, and extra_text.",
      ),
      GemmaBuiltinSkill(
        name = "text-spinner",
        description = "Spin the given text on my head.",
        instructions = "Call the run_js tool with data JSON containing label, the text string to spin.",
      ),
      GemmaBuiltinSkill(
        name = "interactive-map",
        description = "Show an interactive map view for the given location.",
        instructions = "Call the run_js tool with data JSON containing location, the location to show on the map.",
      ),
      GemmaBuiltinSkill(
        name = "mood-tracker",
        description = "A simple mood tracking skill that stores your daily mood and comments.",
        instructions = "Call the run_js tool with action JSON. Supported actions include log_mood, get_mood, get_history, delete_mood, export_data, and wipe_data.",
      ),
      GemmaBuiltinSkill(
        name = "kitchen-adventure",
        description = "Text adventure set in a world where everyone is a sentient kitchen appliance.",
        instructions = "Pure text skill. Act as Head Chef DM, use kitchen-scale world building, never write the player's actions, and format each turn with location, situation, and What do you do?",
      ),
    )
  }
}

private data class RuntimeInitArgs(
  val modelPath: String,
  val accelerator: String,
  val supportImage: Boolean,
  val supportAudio: Boolean,
  val supportSkills: Boolean,
  val topK: Int,
  val topP: Double,
  val temperature: Double,
  val maxTokens: Int,
  val systemPrompt: String?,
  val enabledSkillNames: List<String>,
  val enabledSkills: List<GemmaBuiltinSkill>,
)

private class GemmaLiteRtRuntime(private val activity: Activity) : EventChannel.StreamHandler {
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
      supportSkills = call.argument<Boolean>("supportSkills") ?: false,
      topK = call.argument<Int>("topK") ?: 64,
      topP = call.argument<Double>("topP") ?: 0.95,
      temperature = call.argument<Double>("temperature") ?: 1.0,
      maxTokens = call.argument<Int>("maxTokens") ?: 4000,
      systemPrompt = call.argument<String>("systemPrompt")?.takeIf { it.isNotBlank() },
      enabledSkillNames = call.argument<List<String>>("enabledSkillNames") ?: emptyList(),
      enabledSkills = parseEnabledSkills(call),
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

  private fun parseEnabledSkills(call: MethodCall): List<GemmaBuiltinSkill> {
    val rawSkills = call.argument<List<Any>>("enabledSkills") ?: return emptyList()
    return rawSkills.mapNotNull { raw ->
      val map = raw as? Map<*, *> ?: return@mapNotNull null
      val name = map["name"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        ?: return@mapNotNull null
      GemmaBuiltinSkill(
        name = name,
        description = map["description"]?.toString()?.trim().orEmpty(),
        instructions = map["instructions"]?.toString()?.trim().orEmpty(),
      )
    }
  }

  @OptIn(ExperimentalApi::class)
  private fun initializeBlocking(args: RuntimeInitArgs) {
    closeCurrentRuntime()
    val backend = createBackend(args.accelerator, args.supportImage, args.supportAudio)
    Log.d(
      TAG,
      "initializing runtime: backend=$backend, supportImage=${args.supportImage}, supportAudio=${args.supportAudio}, supportSkills=${args.supportSkills}",
    )
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

    ExperimentalFlags.enableConversationConstrainedDecoding = args.supportSkills
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
        tools = if (args.supportSkills) {
          listOf(
            tool(
              GemmaSkillToolSet(
                context = activity,
                enabledSkillNames = args.enabledSkillNames,
                enabledSkillDetails = args.enabledSkills,
                onToolResult = { toolResult ->
                  runOnMainThread {
                    eventSink?.success(mapOf("type" to "tool_result") + toolResult)
                  }
                },
              )
            )
          )
        } else {
          listOf()
        },
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

  private fun createBackend(accelerator: String, supportImage: Boolean, supportAudio: Boolean): Backend {
    val wantsMultimodal = supportImage || supportAudio
    return when (accelerator.lowercase()) {
      "cpu" -> Backend.CPU()
      "gpu" -> if (wantsMultimodal) Backend.GPU() else Backend.CPU()
      "npu", "tpu" -> Backend.NPU()
      else -> if (wantsMultimodal) Backend.GPU() else Backend.CPU()
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
    // Match Google AI Edge Gallery's Ask Audio data path: UI/playback keeps a
    // WAV file on disk, but Content.AudioBytes must receive raw 16k / mono /
    // 16-bit little-endian PCM bytes without a RIFF/WAVE header.
    return extractMono16BitPcm(bytes, MAX_AUDIO_SECONDS)
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
