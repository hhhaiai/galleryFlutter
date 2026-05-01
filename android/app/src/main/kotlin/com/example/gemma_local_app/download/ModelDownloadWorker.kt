package com.example.gemma_local_app.download

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class ModelDownloadWorker(
  private val appContext: Context,
  params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
  override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
    val modelName = inputData.getString(KEY_MODEL_NAME) ?: return@withContext failure("modelName missing")
    val url = inputData.getString(KEY_MODEL_URL) ?: return@withContext failure("url missing")
    val normalizedName = inputData.getString(KEY_MODEL_NORMALIZED_NAME)
      ?: return@withContext failure("normalizedName missing")
    val version = inputData.getString(KEY_MODEL_VERSION) ?: return@withContext failure("version missing")
    val fileName = inputData.getString(KEY_MODEL_FILE_NAME) ?: return@withContext failure("fileName missing")
    val totalBytes = inputData.getLong(KEY_MODEL_TOTAL_BYTES, 0L)

    try {
      setForeground(createForegroundInfo(modelName, 0))
      val outputDir = File(appContext.getExternalFilesDir(null), listOf(normalizedName, version).joinToString(File.separator))
      if (!outputDir.exists()) outputDir.mkdirs()

      val outputTmpFile = File(outputDir, "$fileName.$TMP_FILE_EXT")
      val outputFile = File(outputDir, fileName)
      if (outputFile.exists() && (totalBytes <= 0L || outputFile.length() >= totalBytes)) {
        setProgress(
          workDataOf(
            KEY_STATUS to STATUS_SUCCEEDED,
            KEY_RECEIVED_BYTES to outputFile.length(),
            KEY_TOTAL_BYTES to totalBytes,
            KEY_LOCAL_PATH to outputFile.absolutePath,
          )
        )
        return@withContext Result.success()
      }
      var downloadedBytes = if (outputTmpFile.exists()) outputTmpFile.length() else 0L

      val connection = URL(url).openConnection() as HttpURLConnection
      if (downloadedBytes > 0L) {
        connection.setRequestProperty("Range", "bytes=$downloadedBytes-")
        connection.setRequestProperty("Accept-Encoding", "identity")
      }
      connection.connect()
      if (connection.responseCode != HttpURLConnection.HTTP_OK &&
        connection.responseCode != HttpURLConnection.HTTP_PARTIAL
      ) {
        throw IOException("HTTP error code: ${connection.responseCode}")
      }

      connection.inputStream.use { input ->
        FileOutputStream(outputTmpFile, true).use { output ->
          val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
          var lastProgressTs = 0L
          var lastProgressBytes = downloadedBytes
          var bytesRead: Int
          while (input.read(buffer).also { bytesRead = it } != -1) {
            output.write(buffer, 0, bytesRead)
            downloadedBytes += bytesRead
            val now = System.currentTimeMillis()
            if (now - lastProgressTs >= PROGRESS_INTERVAL_MS) {
              val elapsed = max(1L, now - lastProgressTs)
              val delta = downloadedBytes - lastProgressBytes
              val bytesPerSecond = if (lastProgressTs == 0L) 0L else delta * 1000L / elapsed
              lastProgressTs = now
              lastProgressBytes = downloadedBytes
              setProgress(
                workDataOf(
                  KEY_STATUS to STATUS_IN_PROGRESS,
                  KEY_RECEIVED_BYTES to downloadedBytes,
                  KEY_TOTAL_BYTES to totalBytes,
                  KEY_BYTES_PER_SECOND to bytesPerSecond,
                  KEY_LOCAL_PATH to outputFile.absolutePath,
                )
              )
              if (totalBytes > 0L) {
                setForeground(createForegroundInfo(modelName, (downloadedBytes * 100 / totalBytes).toInt()))
              }
            }
          }
        }
      }

      if (outputFile.exists()) outputFile.delete()
      if (!outputTmpFile.renameTo(outputFile)) {
        throw IOException("Failed to rename ${outputTmpFile.absolutePath} to ${outputFile.absolutePath}")
      }
      setProgress(
        workDataOf(
          KEY_STATUS to STATUS_SUCCEEDED,
          KEY_RECEIVED_BYTES to downloadedBytes,
          KEY_TOTAL_BYTES to totalBytes,
          KEY_LOCAL_PATH to outputFile.absolutePath,
        )
      )
      Result.success()
    } catch (throwable: Throwable) {
      Log.e(TAG, "Download failed", throwable)
      setProgress(
        workDataOf(
          KEY_STATUS to STATUS_FAILED,
          KEY_RECEIVED_BYTES to 0L,
          KEY_TOTAL_BYTES to totalBytes,
          KEY_ERROR_MESSAGE to (throwable.message ?: "Unknown error"),
        )
      )
      Result.failure(workDataOf(KEY_ERROR_MESSAGE to (throwable.message ?: "Unknown error")))
    }
  }

  private fun failure(message: String): Result {
    return Result.failure(workDataOf(KEY_ERROR_MESSAGE to message))
  }

  private fun createForegroundInfo(modelName: String, progress: Int): ForegroundInfo {
    createNotificationChannel()
    val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.stat_sys_download)
      .setContentTitle("galleryFlutter model download")
      .setContentText(modelName)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setProgress(100, progress.coerceIn(0, 100), progress <= 0)
      .build()
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    } else {
      ForegroundInfo(NOTIFICATION_ID, notification)
    }
  }

  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return
    manager.createNotificationChannel(
      NotificationChannel(CHANNEL_ID, "Model downloads", NotificationManager.IMPORTANCE_LOW)
    )
  }

  companion object {
    private const val TAG = "ModelDownloadWorker"
    private const val CHANNEL_ID = "gallery_flutter_model_downloads"
    private const val NOTIFICATION_ID = 44001
    private const val PROGRESS_INTERVAL_MS = 500L
  }
}

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
