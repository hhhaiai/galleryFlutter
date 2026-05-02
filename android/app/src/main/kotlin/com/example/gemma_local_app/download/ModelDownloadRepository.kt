package com.example.gemma_local_app.download

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.flutter.plugin.common.EventChannel
import java.io.File

class ModelDownloadRepository(private val context: Context) {
  private val workManager = WorkManager.getInstance(context)
  private var eventSink: EventChannel.EventSink? = null

  fun setEventSink(sink: EventChannel.EventSink?) {
    eventSink = sink
  }

  fun refreshStatus(args: Map<String, Any?>): Map<String, Any?> {
    val paths = paths(args)
    migrateLegacyModelIfNeeded(paths)
    val finalFile = File(paths.finalPath)
    val tmpFile = File(paths.tmpPath)
    return when {
      finalFile.exists() && (paths.totalBytes <= 0L || finalFile.length() >= paths.totalBytes) -> statusMap(
        status = STATUS_SUCCEEDED,
        receivedBytes = finalFile.length(),
        totalBytes = paths.totalBytes,
        localPath = finalFile.absolutePath,
      )
      tmpFile.exists() || partialPartBytes(paths) > 0L -> statusMap(
        status = STATUS_PARTIALLY_DOWNLOADED,
        receivedBytes = maxOf(tmpFile.length(), partialPartBytes(paths)),
        totalBytes = paths.totalBytes,
        localPath = finalFile.absolutePath,
      )
      else -> statusMap(
        status = STATUS_NOT_DOWNLOADED,
        totalBytes = paths.totalBytes,
        localPath = finalFile.absolutePath,
      )
    }
  }

  fun download(args: Map<String, Any?>) {
    val paths = paths(args)
    val request = OneTimeWorkRequestBuilder<ModelDownloadWorker>()
      .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
      .setInputData(
        workDataOf(
          KEY_MODEL_NAME to paths.modelName,
          KEY_MODEL_URL to paths.url,
          KEY_MODEL_NORMALIZED_NAME to paths.normalizedName,
          KEY_MODEL_VERSION to paths.version,
          KEY_MODEL_FILE_NAME to paths.fileName,
          KEY_MODEL_TOTAL_BYTES to paths.totalBytes,
        )
      )
      .addTag(paths.modelName)
      .build()

    workManager.cancelUniqueWork(paths.modelName)
    workManager.pruneWork()
    workManager.enqueueUniqueWork(paths.modelName, ExistingWorkPolicy.REPLACE, request)
    workManager.getWorkInfoByIdLiveData(request.id).observeForever { info ->
      if (info != null) emitWorkInfo(paths, info)
    }
  }

  fun cancel(args: Map<String, Any?>) {
    val modelName = args["name"] as? String ?: "Gemma-4-E2B-it"
    workManager.cancelUniqueWork(modelName)
  }

  fun delete(args: Map<String, Any?>): Map<String, Any?> {
    cancel(args)
    val paths = paths(args)
    val rootDir = context.getExternalFilesDir(null) ?: error("externalFilesDir unavailable")
    File(paths.finalPath).delete()
    File(paths.tmpPath).delete()
    rootDir.listFiles { file -> file.name.startsWith("${paths.fileName}.$TMP_FILE_EXT.part") }
      ?.forEach { it.delete() }
    val legacyDir = File(rootDir, paths.normalizedName)
    if (legacyDir.exists()) legacyDir.deleteRecursively()
    return refreshStatus(args)
  }

  private fun emitWorkInfo(paths: DownloadPaths, info: WorkInfo) {
    val progress = info.progress
    when (info.state) {
      WorkInfo.State.ENQUEUED -> emit(
        statusMap(
          status = STATUS_IN_PROGRESS,
          totalBytes = paths.totalBytes,
          localPath = paths.finalPath,
        )
      )
      WorkInfo.State.RUNNING -> emit(
        statusMap(
          status = STATUS_IN_PROGRESS,
          receivedBytes = progress.getLong(KEY_RECEIVED_BYTES, 0L),
          totalBytes = progress.getLong(KEY_TOTAL_BYTES, paths.totalBytes),
          bytesPerSecond = progress.getLong(KEY_BYTES_PER_SECOND, 0L),
          localPath = progress.getString(KEY_LOCAL_PATH) ?: paths.finalPath,
        )
      )
      WorkInfo.State.SUCCEEDED -> emit(refreshStatus(paths.args))
      WorkInfo.State.FAILED -> emit(
        statusMap(
          status = STATUS_FAILED,
          totalBytes = paths.totalBytes,
          errorMessage = info.outputData.getString(KEY_ERROR_MESSAGE)
            ?: progress.getString(KEY_ERROR_MESSAGE)
            ?: "Download failed",
          localPath = paths.finalPath,
        )
      )
      WorkInfo.State.CANCELLED -> emit(refreshStatus(paths.args))
      WorkInfo.State.BLOCKED -> Unit
    }
  }

  private fun emit(map: Map<String, Any?>) {
    eventSink?.success(map)
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

  private fun partialPartBytes(paths: DownloadPaths): Long {
    val dir = context.getExternalFilesDir(null) ?: return 0L
    return dir.listFiles { file -> file.name.startsWith("${paths.fileName}.$TMP_FILE_EXT.part") }
      ?.sumOf { it.length() }
      ?: 0L
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
)
