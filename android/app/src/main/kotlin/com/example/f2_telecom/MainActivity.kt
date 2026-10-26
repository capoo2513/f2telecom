package com.example.f2_telecom

import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import android.media.AudioAttributes
import android.media.ExifInterface
import android.media.MediaActionSound
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// 생체인식(local_auth)은 FlutterFragmentActivity 에서만 동작
class MainActivity : FlutterFragmentActivity() {
    private val galleryChannel = "f2telecom/gallery"
    private val bandChannel = "f2telecom/band"
    private val bandPackage = "com.nhn.android.band"
    private val cameraChannel = "f2telecom/camera"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // [실사] 촬영 사진을 휴대폰 갤러리의 DCIM/F2실사(F2개통)/<국소명>/ 에 지정한 파일명으로 저장
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, galleryChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveImage") {
                    val path = call.argument<String>("path")
                    val album = call.argument<String>("album")
                    val name = call.argument<String>("name")
                    val label = call.argument<String>("label") ?: ""
                    if (path == null || album == null || name == null) {
                        result.error("ARG", "path/album/name 누락", null)
                    } else {
                        try {
                            // label 이 있으면 사진 위쪽에 글자를 새긴 사본을 갤러리에 저장 (개통 선번 등)
                            var src = path
                            var tmp: File? = null
                            if (label.isNotEmpty()) {
                                try {
                                    tmp = File(cacheDir, "stamp_" + System.currentTimeMillis() + ".jpg")
                                    makeLabeledCopy(File(path), label, tmp)
                                    src = tmp.absolutePath
                                } catch (e: Exception) {
                                    src = path // 글자 새기기 실패 시 원본 그대로
                                }
                            }
                            saveImage(src, album, name)
                            tmp?.delete()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SAVE", e.message, null)
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }

        // [실사] 공유 창 없이 밴드 앱으로 바로 사진+본문 전달
        // 반환값: true = 밴드 열림 / false = 밴드 미설치 (앱에서 일반 공유 창으로 대체)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bandChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "shareToBand") {
                    val items = call.argument<List<Map<String, String>>>("items") ?: emptyList()
                    val text = call.argument<String>("text") ?: ""
                    // 사진에 글자 새기기는 시간이 걸리므로 백그라운드에서
                    Thread {
                        try {
                            val status = shareToBand(items, text)
                            runOnUiThread { result.success(status) }
                        } catch (e: Throwable) {
                            runOnUiThread { result.success("error: ${e.javaClass.simpleName} ${e.message}") }
                        }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }

        // [실사] 촬영 시 찰칵 소리 + 진동
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cameraChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "shutter") {
                    result.success(playShutterFeedback()) // "ok" 또는 실패 이유
                } else {
                    result.notImplemented()
                }
            }
    }

    private val shutterSound: MediaActionSound by lazy {
        MediaActionSound().apply { load(MediaActionSound.SHUTTER_CLICK) }
    }

    /// 찰칵 소리 + 진동. 반환: "ok" 또는 실패 이유(진단용)
    private fun playShutterFeedback(): String {
        val problems = ArrayList<String>()
        try {
            shutterSound.play(MediaActionSound.SHUTTER_CLICK)
        } catch (e: Throwable) {
            problems.add("소리: ${e.javaClass.simpleName} ${e.message}")
        }
        try {
            val vibrator = getVibrator()
            if (!vibrator.hasVibrator()) {
                problems.add("진동: 진동 모터 없음")
            } else {
                vibrateStrong(vibrator)
            }
        } catch (e: Throwable) {
            problems.add("진동: ${e.javaClass.simpleName} ${e.message}")
        }
        return if (problems.isEmpty()) "ok" else problems.joinToString(" / ")
    }

    /// 휴대폰의 '터치 진동' 설정이 꺼져 있어도 느껴지도록 알람 용도로 짧고 강하게 진동
    @Suppress("DEPRECATION")
    private fun vibrateStrong(vibrator: Vibrator) {
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                val effect = VibrationEffect.createOneShot(120, 255)
                vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                val amp = if (vibrator.hasAmplitudeControl()) 255 else VibrationEffect.DEFAULT_AMPLITUDE
                val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
                vibrator.vibrate(VibrationEffect.createOneShot(120, amp), attrs)
            }
            else -> vibrator.vibrate(120)
        }
    }

    @Suppress("DEPRECATION")
    private fun getVibrator(): Vibrator {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
    }

    /// 사진 위쪽에 항목 이름 띠를 새긴 사본 만들기 (원본은 그대로)
    private fun makeLabeledCopy(src: File, label: String, dst: File) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(src.absolutePath, bounds)
        var sample = 1
        val maxDim = 2560
        while (bounds.outWidth / sample > maxDim || bounds.outHeight / sample > maxDim) sample *= 2
        val decoded = BitmapFactory.decodeFile(
            src.absolutePath,
            BitmapFactory.Options().apply { inSampleSize = sample }
        ) ?: throw Exception("사진을 읽을 수 없습니다: ${src.name}")

        // 카메라 사진의 회전 정보(EXIF) 반영
        val orientation = try {
            ExifInterface(src.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
            )
        } catch (e: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val degrees = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        val rotated = if (degrees != 0f) {
            val m = Matrix().apply { postRotate(degrees) }
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, m, true)
        } else decoded
        val bmp = if (rotated.isMutable) rotated else rotated.copy(Bitmap.Config.ARGB_8888, true)

        val canvas = Canvas(bmp)
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = bmp.width * 0.045f
            typeface = Typeface.DEFAULT_BOLD
        }
        val pad = textPaint.textSize * 0.5f
        val textH = textPaint.descent() - textPaint.ascent()
        val barH = textH + pad * 2
        val bgPaint = Paint().apply { color = Color.argb(170, 0, 0, 0) }
        canvas.drawRect(0f, 0f, bmp.width.toFloat(), barH, bgPaint)

        // 글자가 너무 길면 뒤를 줄임
        var t = label
        val maxW = bmp.width - pad * 2
        if (textPaint.measureText(t) > maxW) {
            while (t.length > 1 && textPaint.measureText("$t…") > maxW) t = t.dropLast(1)
            t = "$t…"
        }
        canvas.drawText(t, pad, pad - textPaint.ascent(), textPaint)

        FileOutputStream(dst).use { bmp.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        if (bmp !== decoded) decoded.recycle()
        if (rotated !== decoded && rotated !== bmp) rotated.recycle()
        bmp.recycle()
    }

    private fun isBandInstalled(): Boolean {
        return try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(bandPackage, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    /// 반환: "ok" = 밴드 열림 / "no_band" = 밴드 미설치 / "no_activity" = 밴드가 공유를 받지 않음
    private fun shareToBand(items: List<Map<String, String>>, text: String): String {
        if (!isBandInstalled()) return "no_band"

        // 밴드에 넘길 사진을 공유용 임시 폴더(cache/band_share)에 만들기
        // (사진 위쪽에 항목 이름을 새긴 사본, 원본은 그대로)
        val dir = File(cacheDir, "band_share")
        dir.deleteRecursively()
        dir.mkdirs()
        val uris = ArrayList<Uri>()
        items.forEachIndexed { i, item ->
            val src = File(item["path"] ?: return@forEachIndexed)
            if (!src.exists()) return@forEachIndexed
            val label = item["label"] ?: ""
            val dst = File(dir, String.format("%03d_%s", i + 1, src.name))
            try {
                if (label.isNotEmpty()) makeLabeledCopy(src, label, dst) else src.copyTo(dst, overwrite = true)
            } catch (e: Exception) {
                src.copyTo(dst, overwrite = true) // 글자 새기기 실패 시 원본 그대로
            }
            uris.add(FileProvider.getUriForFile(this, "$packageName.f2fileprovider", dst))
        }

        val intent = when {
            uris.isEmpty() -> Intent(Intent.ACTION_SEND).apply { type = "text/plain" }
            uris.size == 1 -> Intent(Intent.ACTION_SEND).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_STREAM, uris[0])
            }
            else -> Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = "image/*"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            }
        }
        intent.putExtra(Intent.EXTRA_TEXT, text)
        intent.setPackage(bandPackage)
        if (uris.isNotEmpty()) {
            val clip = ClipData.newRawUri("", uris[0])
            for (i in 1 until uris.size) clip.addItem(ClipData.Item(uris[i]))
            intent.clipData = clip
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(packageManager) == null) return "no_activity"
        runOnUiThread { startActivity(intent) }
        return "ok"
    }

    private fun saveImage(path: String, album: String, name: String) {
        val src = File(path)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // 안드로이드 10 이상: 권한 없이 MediaStore 로 저장
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(MediaStore.Images.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_DCIM + "/" + album)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("갤러리 저장 위치를 만들 수 없습니다")
            resolver.openOutputStream(uri)?.use { out ->
                src.inputStream().use { input -> input.copyTo(out) }
            } ?: throw Exception("파일 쓰기 실패")
            val done = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            resolver.update(uri, done, null, null)
        } else {
            // 안드로이드 9 이하: 저장소 쓰기 권한 필요
            @Suppress("DEPRECATION")
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM),
                album
            )
            if (!dir.exists()) dir.mkdirs()
            var dest = File(dir, name)
            if (dest.exists()) {
                dest = File(dir, name.removeSuffix(".jpg") + "_" + System.currentTimeMillis() + ".jpg")
            }
            src.copyTo(dest)
            MediaScannerConnection.scanFile(this, arrayOf(dest.absolutePath), arrayOf("image/jpeg"), null)
        }
    }
}
