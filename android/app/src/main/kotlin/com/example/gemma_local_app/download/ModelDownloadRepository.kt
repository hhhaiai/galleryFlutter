package com.example.gemma_local_app.download

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class ModelDownloadRepository(private val context: Context) {
  private val downloadManager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
  private val prefs = context.getSharedPreferences("model_downloads", Context.MODE_PRIVATE)
  private val mainHandler = Handler(Looper.getMainLooper())
  private val scheduler = Executors.newSingleThreadScheduledExecutor()
  private var eventSink: EventChannel.EventSink? = null
  private var progressTicker: ScheduledFuture<*>? = null
  private var activeArgs: Map<String, Any?>? = null
  private var completionReceiverRegistered = false

  fun setEventSink(sink: EventChannel.EventSink?) {
    eventSink = sink
    if (sink == null) {
      stopProgressTicker()
    } else {
      activeArgs?.let { startProgressTicker(it) }
    }
  }

  fun refreshStatus(args: Map<String, Any?>): Map<String, Any?> {
    val paths = paths(args)
    migrateLegacyModelIfNeeded(paths)
    val finalFile = File(paths.finalPath)
    if (finalFile.exists() && (paths.totalBytes <= 0L || finalFile.length() >= paths.totalBytes)) {
      clearDownloadId(paths)
      return statusMap(
        status = STATUS_SUCCEEDED,
        receivedBytes = finalFile.length(),
        totalBytes = paths.totalBytes,
        localPath = finalFile.absolutePath,
      )
    }

    val downloadId = getDownloadId(paths)
    if (downloadId > 0L) {
      val queried = queryDownload(paths, downloadId)
      if (queried != null) return queried
      clearDownloadId(paths)
    }

    val partial = File(paths.tmpPath)
    return if (partial.exists() && partial.length() > 0L) {
      statusMap(
        status = STATUS_PARTIALLY_DOWNLOADED,
        receivedBytes = partial.length(),
        totalBytes = paths.totalBytes,
        localPath = finalFile.absolutePath,
      )
    } else {
      statusMap(
        status = STATUS_NOT_DOWNLOADED,
        totalBytes = paths.totalBytes,
        localPath = finalFile.absolutePath,
      )
    }
  }

  fun download(args: Map<String, Any?>) {
    val paths = paths(args)
    activeArgs = args
    registerCompletionReceiver()

    val current = refreshStatus(args)
    if (current["status"] == STATUS_SUCCEEDED || current["status"] == STATUS_IN_PROGRESS) {
      emit(current)
      startProgressTicker(args)
      return
    }

    cancel(args, deleteFiles = false)
    File(paths.finalPath).parentFile?.mkdirs()
    File(paths.tmpPath).delete()

    val request = DownloadManager.Request(Uri.parse(paths.url))
      .setTitle("galleryFlutter model download")
      .setDescription(paths.modelName)
      .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
      .setAllowedOverMetered(true)
      .setAllowedOverRoaming(true)
      .setDestinationInExternalFilesDir(context, null, paths.tmpFileName)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      request.setRequiresCharging(false)
      request.setRequiresDeviceIdle(false)
    }

    val id = downloadManager.enqueue(request)
    Log.i(TAG, "Enqueued system download id=$id model=${paths.modelName} dest=${paths.tmpPath}")
    setDownloadId(paths, id)
    emit(
      statusMap(
        status = STATUS_IN_PROGRESS,
        totalBytes = paths.totalBytes,
        localPath = paths.finalPath,
      )
    )
    startProgressTicker(args)
  }

  fun cancel(args: Map<String, Any?>) {
    cancel(args, deleteFiles = false)
    emit(refreshStatus(args))
  }

  private fun cancel(args: Map<String, Any?>, deleteFiles: Boolean) {
    val paths = paths(args)
    val id = getDownloadId(paths)
    if (id > 0L) {
      runCatching { downloadManager.remove(id) }
      clearDownloadId(paths)
    }
    if (deleteFiles) {
      File(paths.finalPath).delete()
      File(paths.tmpPath).delete()
      val rootDir = context.getExternalFilesDir(null)
      rootDir?.listFiles { file -> file.name.startsWith("${paths.fileName}.$TMP_FILE_EXT") }
        ?.forEach { it.delete() }
      val legacyDir = rootDir?.let { File(it, paths.normalizedName) }
      if (legacyDir?.exists() == true) legacyDir.deleteRecursively()
    }
  }

  fun delete(args: Map<String, Any?>): Map<String, Any?> {
    cancel(args, deleteFiles = true)
    return refreshStatus(args)
  }

  private fun queryDownload(paths: DownloadPaths, downloadId: Long): Map<String, Any?>? {
    val cursor = downloadManager.query(DownloadManager.Query().setFilterById(downloadId)) ?: return null
    cursor.use {
      if (!it.moveToFirst()) return null
      val status = it.intColumn(DownloadManager.COLUMN_STATUS)
      val downloaded = it.longColumn(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
      val total = it.longColumn(DownloadManager.COLUMN_TOTAL_SIZE_BYTES).takeIf { value -> value > 0L }
        ?: paths.totalBytes
      val reason = it.intColumn(DownloadManager.COLUMN_REASON)
      if (status == DownloadManager.STATUS_FAILED) {
        Log.w(
          TAG,
          "System download failed id=$downloadId reason=$reason downloaded=$downloaded total=$total dest=${paths.tmpPath}",
        )
      }
      return when (status) {
        DownloadManager.STATUS_SUCCESSFUL -> promoteSystemDownload(paths, downloaded, total)
        DownloadManager.STATUS_RUNNING,
        DownloadManager.STATUS_PENDING,
        DownloadManager.STATUS_PAUSED -> statusMap(
          status = STATUS_IN_PROGRESS,
          receivedBytes = downloaded,
          totalBytes = total,
          localPath = paths.finalPath,
        )
        DownloadManager.STATUS_FAILED -> statusMap(
          status = STATUS_FAILED,
          receivedBytes = downloaded,
          totalBytes = total,
          errorMessage = downloadFailureReason(reason),
          localPath = paths.finalPath,
        )
        else -> statusMap(
          status = STATUS_NOT_DOWNLOADED,
          totalBytes = paths.totalBytes,
          localPath = paths.finalPath,
        )
      }
    }
  }

  private fun promoteSystemDownload(paths: DownloadPaths, downloaded: Long, total: Long): Map<String, Any?> {
    val tmp = File(paths.tmpPath)
    val finalFile = File(paths.finalPath)
    if (tmp.exists()) {
      finalFile.parentFile?.mkdirs()
      if (finalFile.exists()) finalFile.delete()
      if (!tmp.renameTo(finalFile)) {
        tmp.copyTo(finalFile, overwrite = true)
        tmp.delete()
      }
    }
    clearDownloadId(paths)
    stopProgressTicker()
    val received = if (finalFile.exists()) finalFile.length() else downloaded
    return statusMap(
      status = STATUS_SUCCEEDED,
      receivedBytes = received,
      totalBytes = maxOf(total, paths.totalBytes),
      localPath = finalFile.absolutePath,
    )
  }

  private fun startProgressTicker(args: Map<String, Any?>) {
    stopProgressTicker()
    activeArgs = args
    progressTicker = scheduler.scheduleAtFixedRate({
      val status = refreshStatus(args)
      emit(status)
      val type = status["status"]
      if (type == STATUS_SUCCEEDED || type == STATUS_FAILED || type == STATUS_NOT_DOWNLOADED) {
        stopProgressTicker()
      }
    }, 0L, PROGRESS_INTERVAL_MS, TimeUnit.MILLISECONDS)
  }

  private fun stopProgressTicker() {
    progressTicker?.cancel(false)
    progressTicker = null
  }

  private fun registerCompletionReceiver() {
    if (completionReceiverRegistered) return
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        if (DownloadManager.ACTION_DOWNLOAD_COMPLETE != intent.action) return
        val args = activeArgs ?: return
        emit(refreshStatus(args))
      }
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      context.registerReceiver(receiver, IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE), Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("DEPRECATION")
      context.registerReceiver(receiver, IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE))
    }
    completionReceiverRegistered = true
  }

  private fun emit(map: Map<String, Any?>) {
    val sink = eventSink ?: return
    mainHandler.post { sink.success(map) }
  }

  private fun getDownloadId(paths: DownloadPaths): Long = prefs.getLong(downloadIdKey(paths), -1L)

  private fun setDownloadId(paths: DownloadPaths, id: Long) {
    prefs.edit().putLong(downloadIdKey(paths), id).apply()
  }

  private fun clearDownloadId(paths: DownloadPaths) {
    prefs.edit().remove(downloadIdKey(paths)).apply()
  }

  private fun downloadIdKey(paths: DownloadPaths): String = "download:${paths.modelName}:${paths.version}:${paths.fileName}"

  private fun downloadFailureReason(reason: Int): String = when (reason) {
    DownloadManager.ERROR_CANNOT_RESUME -> "系统下载失败：不支持继续下载，请点删除后重试。"
    DownloadManager.ERROR_DEVICE_NOT_FOUND -> "系统下载失败：存储设备不可用。"
    DownloadManager.ERROR_FILE_ALREADY_EXISTS -> "系统下载失败：文件已存在。"
    DownloadManager.ERROR_FILE_ERROR -> "系统下载失败：文件写入错误。"
    DownloadManager.ERROR_HTTP_DATA_ERROR -> "系统下载失败：HTTP 数据错误。"
    DownloadManager.ERROR_INSUFFICIENT_SPACE -> "系统下载失败：存储空间不足。"
    DownloadManager.ERROR_TOO_MANY_REDIRECTS -> "系统下载失败：重定向过多。"
    DownloadManager.ERROR_UNHANDLED_HTTP_CODE -> "系统下载失败：服务器返回不支持的 HTTP 状态。"
    DownloadManager.ERROR_UNKNOWN -> "系统下载失败：未知错误。"
    else -> "系统下载失败：reason=$reason"
  }

  private fun migrateLegacyModelIfNeeded(paths: DownloadPaths) {
    val finalFile = File(paths.finalPath)
    if (finalFile.exists() && (paths.totalBytes <= 0L || finalFile.length() >= paths.totalBytes)) return
    val rootDir = context.getExternalFilesDir(null) ?: return
    val legacyFile = File(rootDir, listOf(paths.normalizedName, paths.version, paths.originalFileName).joinToString(File.separator))
    if (!legacyFile.exists()) return
    if (paths.totalBytes > 0L && legacyFile.length() < paths.totalBytes) return
    finalFile.parentFile?.mkdirs()
    try {
      legacyFile.renameTo(finalFile)
    } catch (_: Throwable) {
      legacyFile.copyTo(finalFile, overwrite = true)
    }
  }

  private fun paths(args: Map<String, Any?>): DownloadPaths {
    val modelName = args["name"] as? String ?: "Gemma-4-E2B-it"
    val url = args["url"] as? String ?: error("url missing")
    val normalizedName = args["normalizedName"] as? String ?: error("normalizedName missing")
    val version = args["version"] as? String ?: error("version missing")
    val fileName = args["fileName"] as? String ?: error("fileName missing")
    val totalBytes = (args["totalBytes"] as? Number)?.toLong() ?: 0L
    val dir = context.getExternalFilesDir(null) ?: error("externalFilesDir unavailable")
    val flatFileName = fileName.lowercase()
    return DownloadPaths(
      args = args,
      modelName = modelName,
      url = url,
      normalizedName = normalizedName,
      version = version,
      fileName = flatFileName,
      originalFileName = fileName,
      totalBytes = totalBytes,
      finalPath = File(dir, flatFileName).absolutePath,
      tmpPath = File(dir, "$flatFileName.$TMP_FILE_EXT").absolutePath,
      tmpFileName = "$flatFileName.$TMP_FILE_EXT",
    )
  }

  private fun statusMap(
    status: String,
    receivedBytes: Long = 0L,
    totalBytes: Long = 0L,
    bytesPerSecond: Long = 0L,
    errorMessage: String = "",
    localPath: String = "",
  ): Map<String, Any?> {
    return mapOf(
      "status" to status,
      "receivedBytes" to receivedBytes,
      "totalBytes" to totalBytes,
      "bytesPerSecond" to bytesPerSecond,
      "errorMessage" to errorMessage,
      "localPath" to localPath,
    )
  }

  private fun Cursor.intColumn(name: String): Int = getInt(getColumnIndexOrThrow(name))
  private fun Cursor.longColumn(name: String): Long = getLong(getColumnIndexOrThrow(name))

  companion object {
    private const val TAG = "ModelDownloadRepository"
    private const val PROGRESS_INTERVAL_MS = 1000L
  }
}

private data class DownloadPaths(
  val args: Map<String, Any?>,
  val modelName: String,
  val url: String,
  val normalizedName: String,
  val version: String,
  val fileName: String,
  val originalFileName: String,
  val totalBytes: Long,
  val finalPath: String,
  val tmpPath: String,
  val tmpFileName: String,
)

const val TMP_FILE_EXT = "gallerytmp"
const val KEY_MODEL_NAME = "modelName"
const val KEY_MODEL_URL = "modelUrl"
const val KEY_MODEL_NORMALIZED_NAME = "normalizedName"
const val KEY_MODEL_VERSION = "version"
const val KEY_MODEL_FILE_NAME = "fileName"
const val KEY_MODEL_TOTAL_BYTES = "totalBytes"
const val KEY_STATUS = "status"
const val KEY_RECEIVED_BYTES = "receivedBytes"
const val KEY_TOTAL_BYTES = "totalBytesOut"
const val KEY_BYTES_PER_SECOND = "bytesPerSecond"
const val KEY_LOCAL_PATH = "localPath"
const val KEY_ERROR_MESSAGE = "errorMessage"
const val STATUS_NOT_DOWNLOADED = "notDownloaded"
const val STATUS_PARTIALLY_DOWNLOADED = "partiallyDownloaded"
const val STATUS_IN_PROGRESS = "inProgress"
const val STATUS_SUCCEEDED = "succeeded"
const val STATUS_FAILED = "failed"
