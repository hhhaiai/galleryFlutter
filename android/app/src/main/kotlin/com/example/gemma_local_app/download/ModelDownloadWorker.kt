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
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
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
    val expectedTotalBytes = inputData.getLong(KEY_MODEL_TOTAL_BYTES, 0L)

    try {
      setForeground(createForegroundInfo(modelName, 0))
      val outputDir = appContext.getExternalFilesDir(null)
        ?: throw IOException("externalFilesDir unavailable")
      if (!outputDir.exists() && !outputDir.mkdirs()) {
        throw IOException("Failed to create model directory: ${outputDir.absolutePath}")
      }
      val flatFileName = fileName.lowercase()

      val outputTmpFile = File(outputDir, "$flatFileName.$TMP_FILE_EXT")
      val outputFile = File(outputDir, flatFileName)
      if (outputFile.exists() && (expectedTotalBytes <= 0L || outputFile.length() >= expectedTotalBytes)) {
        setProgress(
          workDataOf(
            KEY_STATUS to STATUS_SUCCEEDED,
            KEY_RECEIVED_BYTES to outputFile.length(),
            KEY_TOTAL_BYTES to expectedTotalBytes,
            KEY_LOCAL_PATH to outputFile.absolutePath,
          )
        )
        return@withContext Result.success()
      }

      val remote = probeRemote(url, expectedTotalBytes)
      if (!remote.supportsRanges || remote.totalBytes <= 0L || remote.totalBytes < MIN_PARALLEL_DOWNLOAD_BYTES) {
        downloadSingleStream(
          modelName = modelName,
          url = url,
          outputTmpFile = outputTmpFile,
          outputFile = outputFile,
          totalBytes = max(remote.totalBytes, expectedTotalBytes),
        )
      } else {
        downloadParallelRanges(
          modelName = modelName,
          url = url,
          outputDir = outputDir,
          outputTmpFile = outputTmpFile,
          outputFile = outputFile,
          fileName = flatFileName,
          totalBytes = remote.totalBytes,
        )
      }

      setProgress(
        workDataOf(
          KEY_STATUS to STATUS_SUCCEEDED,
          KEY_RECEIVED_BYTES to outputFile.length(),
          KEY_TOTAL_BYTES to max(outputFile.length(), expectedTotalBytes),
          KEY_LOCAL_PATH to outputFile.absolutePath,
        )
      )
      Result.success()
    } catch (throwable: Throwable) {
      Log.e(TAG, "Download failed", throwable)
      val pathsDir = File(appContext.getExternalFilesDir(null), listOf(normalizedName, version).joinToString(File.separator))
      val partialBytes = partialDownloadedBytes(pathsDir, fileName, File(pathsDir, "$fileName.$TMP_FILE_EXT"))
      setProgress(
        workDataOf(
          KEY_STATUS to STATUS_FAILED,
          KEY_RECEIVED_BYTES to partialBytes,
          KEY_TOTAL_BYTES to expectedTotalBytes,
          KEY_ERROR_MESSAGE to (throwable.message ?: "Unknown error"),
        )
      )
      Result.failure(workDataOf(KEY_ERROR_MESSAGE to (throwable.message ?: "Unknown error")))
    }
  }

  private suspend fun downloadParallelRanges(
    modelName: String,
    url: String,
    outputDir: File,
    outputTmpFile: File,
    outputFile: File,
    fileName: String,
    totalBytes: Long,
  ) = coroutineScope {
    val partCount = choosePartCount(totalBytes)
    val ranges = buildRanges(totalBytes, partCount)
    val partFiles = ranges.map { range -> File(outputDir, "$fileName.$TMP_FILE_EXT.part${range.index}") }

    // If a previous single-stream temp exists, keep it as resumable progress only when it is already complete.
    // Otherwise split/range state is the source of truth for parallel resume.
    if (outputTmpFile.exists() && outputTmpFile.length() >= totalBytes) {
      promoteTmpToFinal(outputTmpFile, outputFile)
      return@coroutineScope
    }

    val progressJob = async {
      var lastTs = 0L
      var lastBytes = partFiles.sumOf { it.safeLength() }
      while (isActive) {
        val now = System.currentTimeMillis()
        val downloadedBytes = partFiles.sumOf { it.safeLength().coerceAtMost(ranges[partFiles.indexOf(it)].length) }
        val elapsed = max(1L, now - lastTs)
        val delta = downloadedBytes - lastBytes
        val bytesPerSecond = if (lastTs == 0L) 0L else delta * 1000L / elapsed
        lastTs = now
        lastBytes = downloadedBytes
        publishProgress(modelName, downloadedBytes, totalBytes, bytesPerSecond, outputFile.absolutePath)
        delay(PROGRESS_INTERVAL_MS)
      }
    }

    try {
      ranges.map { range ->
        async(Dispatchers.IO) {
          downloadRangeToPart(url, range, partFiles[range.index])
        }
      }.awaitAll()
    } finally {
      progressJob.cancel()
    }

    mergeParts(partFiles, ranges, outputTmpFile, totalBytes)
    promoteTmpToFinal(outputTmpFile, outputFile)
    partFiles.forEach { it.delete() }
  }

  private fun downloadRangeToPart(url: String, range: ByteRange, partFile: File) {
    if (partFile.exists() && partFile.length() > range.length) {
      partFile.delete()
    }
    val existingBytes = partFile.safeLength()
    if (existingBytes >= range.length) return

    val start = range.start + existingBytes
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.instanceFollowRedirects = true
    connection.setRequestProperty("Range", "bytes=$start-${range.end}")
    connection.setRequestProperty("Accept-Encoding", "identity")
    connection.connect()
    if (connection.responseCode != HttpURLConnection.HTTP_PARTIAL) {
      throw IOException("Range ${range.index} expected HTTP 206 but got ${connection.responseCode}")
    }

    connection.inputStream.use { input ->
      FileOutputStream(partFile, true).use { output ->
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var bytesRead: Int
        while (input.read(buffer).also { bytesRead = it } != -1) {
          output.write(buffer, 0, bytesRead)
        }
      }
    }
    connection.disconnect()

    if (partFile.length() != range.length) {
      throw IOException("Range ${range.index} incomplete: ${partFile.length()} / ${range.length}")
    }
  }

  private suspend fun downloadSingleStream(
    modelName: String,
    url: String,
    outputTmpFile: File,
    outputFile: File,
    totalBytes: Long,
  ) {
    var downloadedBytes = if (outputTmpFile.exists()) outputTmpFile.length() else 0L
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.instanceFollowRedirects = true
    connection.setRequestProperty("Accept-Encoding", "identity")
    if (downloadedBytes > 0L) {
      connection.setRequestProperty("Range", "bytes=$downloadedBytes-")
    }
    connection.connect()
    if (downloadedBytes > 0L && connection.responseCode == HttpURLConnection.HTTP_OK) {
      downloadedBytes = 0L
      outputTmpFile.delete()
    } else if (connection.responseCode != HttpURLConnection.HTTP_OK &&
      connection.responseCode != HttpURLConnection.HTTP_PARTIAL
    ) {
      throw IOException("HTTP error code: ${connection.responseCode}")
    }

    connection.inputStream.use { input ->
      FileOutputStream(outputTmpFile, downloadedBytes > 0L).use { output ->
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
            publishProgress(modelName, downloadedBytes, totalBytes, bytesPerSecond, outputFile.absolutePath)
          }
        }
      }
    }
    connection.disconnect()
    promoteTmpToFinal(outputTmpFile, outputFile)
  }

  private fun probeRemote(url: String, expectedTotalBytes: Long): RemoteInfo {
    val head = URL(url).openConnection() as HttpURLConnection
    return try {
      head.instanceFollowRedirects = true
      head.requestMethod = "HEAD"
      head.setRequestProperty("Accept-Encoding", "identity")
      head.connect()
      val total = head.contentLengthLong.takeIf { it > 0L } ?: expectedTotalBytes
      val acceptRanges = head.getHeaderField("Accept-Ranges")?.contains("bytes", ignoreCase = true) == true
      val supportsRanges = acceptRanges || probeRangeSupport(url)
      RemoteInfo(totalBytes = total, supportsRanges = supportsRanges)
    } catch (throwable: Throwable) {
      Log.w(TAG, "HEAD probe failed; falling back to range probe", throwable)
      RemoteInfo(totalBytes = expectedTotalBytes, supportsRanges = probeRangeSupport(url))
    } finally {
      head.disconnect()
    }
  }

  private fun probeRangeSupport(url: String): Boolean {
    val connection = URL(url).openConnection() as HttpURLConnection
    return try {
      connection.instanceFollowRedirects = true
      connection.setRequestProperty("Range", "bytes=0-0")
      connection.setRequestProperty("Accept-Encoding", "identity")
      connection.connect()
      connection.responseCode == HttpURLConnection.HTTP_PARTIAL
    } catch (throwable: Throwable) {
      false
    } finally {
      connection.disconnect()
    }
  }

  private suspend fun publishProgress(
    modelName: String,
    downloadedBytes: Long,
    totalBytes: Long,
    bytesPerSecond: Long,
    localPath: String,
  ) {
    setProgress(
      workDataOf(
        KEY_STATUS to STATUS_IN_PROGRESS,
        KEY_RECEIVED_BYTES to downloadedBytes,
        KEY_TOTAL_BYTES to totalBytes,
        KEY_BYTES_PER_SECOND to bytesPerSecond,
        KEY_LOCAL_PATH to localPath,
      )
    )
    if (totalBytes > 0L) {
      setForeground(createForegroundInfo(modelName, (downloadedBytes * 100 / totalBytes).toInt()))
    }
  }

  private fun mergeParts(partFiles: List<File>, ranges: List<ByteRange>, outputTmpFile: File, totalBytes: Long) {
    if (outputTmpFile.exists()) outputTmpFile.delete()
    RandomAccessFile(outputTmpFile, "rw").use { output ->
      output.setLength(totalBytes)
      partFiles.forEachIndexed { index, partFile ->
        val range = ranges[index]
        if (partFile.length() != range.length) {
          throw IOException("Part $index incomplete before merge: ${partFile.length()} / ${range.length}")
        }
        partFile.inputStream().use { input ->
          output.seek(range.start)
          val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
          var bytesRead: Int
          while (input.read(buffer).also { bytesRead = it } != -1) {
            output.write(buffer, 0, bytesRead)
          }
        }
      }
    }
  }

  private fun promoteTmpToFinal(outputTmpFile: File, outputFile: File) {
    if (outputFile.exists() && !outputFile.delete()) {
      throw IOException("Failed to delete existing final file: ${outputFile.absolutePath}")
    }
    if (!outputTmpFile.renameTo(outputFile)) {
      throw IOException("Failed to rename ${outputTmpFile.absolutePath} to ${outputFile.absolutePath}")
    }
  }

  private fun choosePartCount(totalBytes: Long): Int {
    val bySize = (totalBytes / TARGET_PART_SIZE_BYTES).coerceAtLeast(1L).toInt()
    return bySize.coerceIn(2, MAX_PARALLEL_DOWNLOADS)
  }

  private fun buildRanges(totalBytes: Long, partCount: Int): List<ByteRange> {
    val partSize = totalBytes / partCount
    return (0 until partCount).map { index ->
      val start = index * partSize
      val end = if (index == partCount - 1) totalBytes - 1 else ((index + 1) * partSize) - 1
      ByteRange(index = index, start = start, end = end)
    }
  }

  private fun partialDownloadedBytes(dir: File, fileName: String, tmpFile: File): Long {
    val partBytes = dir.listFiles { file -> file.name.startsWith("$fileName.$TMP_FILE_EXT.part") }
      ?.sumOf { it.safeLength() }
      ?: 0L
    return max(tmpFile.safeLength(), partBytes)
  }

  private fun File.safeLength(): Long = if (exists()) length() else 0L

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
    private const val MAX_PARALLEL_DOWNLOADS = 4
    private const val TARGET_PART_SIZE_BYTES = 512L * 1024L * 1024L
    private const val MIN_PARALLEL_DOWNLOAD_BYTES = 64L * 1024L * 1024L
  }
}

private data class RemoteInfo(
  val totalBytes: Long,
  val supportsRanges: Boolean,
)

private data class ByteRange(
  val index: Int,
  val start: Long,
  val end: Long,
) {
  val length: Long get() = end - start + 1
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
