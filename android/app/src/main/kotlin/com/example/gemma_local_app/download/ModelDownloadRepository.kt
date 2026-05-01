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
    val finalFile = File(paths.finalPath)
    val tmpFile = File(paths.tmpPath)
    return when {
      finalFile.exists() && (paths.totalBytes <= 0L || finalFile.length() >= paths.totalBytes) -> statusMap(
        status = STATUS_SUCCEEDED,
        receivedBytes = finalFile.length(),
        totalBytes = paths.totalBytes,
        localPath = finalFile.absolutePath,
      )
      tmpFile.exists() -> statusMap(
        status = STATUS_PARTIALLY_DOWNLOADED,
        receivedBytes = tmpFile.length(),
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
    val dir = File(context.getExternalFilesDir(null), paths.normalizedName)
    if (dir.exists()) dir.deleteRecursively()
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

  private fun paths(args: Map<String, Any?>): DownloadPaths {
    val modelName = args["name"] as? String ?: "Gemma-4-E2B-it"
    val url = args["url"] as? String ?: error("url missing")
    val normalizedName = args["normalizedName"] as? String ?: error("normalizedName missing")
    val version = args["version"] as? String ?: error("version missing")
    val fileName = args["fileName"] as? String ?: error("fileName missing")
    val totalBytes = (args["totalBytes"] as? Number)?.toLong() ?: 0L
    val dir = File(context.getExternalFilesDir(null), listOf(normalizedName, version).joinToString(File.separator))
    return DownloadPaths(
      args = args,
      modelName = modelName,
      url = url,
      normalizedName = normalizedName,
      version = version,
      fileName = fileName,
      totalBytes = totalBytes,
      finalPath = File(dir, fileName).absolutePath,
      tmpPath = File(dir, "$fileName.$TMP_FILE_EXT").absolutePath,
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
  val totalBytes: Long,
  val finalPath: String,
  val tmpPath: String,
)
