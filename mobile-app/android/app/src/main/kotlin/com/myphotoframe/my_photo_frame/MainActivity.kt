package com.myphotoframe.my_photo_frame

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "my_photo_frame/import_metadata")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("invalid_path", "Missing image path", null)
                    return@setMethodCallHandler
                }
                try {
                    val exif = ExifInterface(path)
                    val coordinates = exif.latLong
                    result.success(mapOf(
                        "date" to exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL),
                        "offset" to exif.getAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL),
                        "latitude" to coordinates?.get(0),
                        "longitude" to coordinates?.get(1)
                    ))
                } catch (error: Exception) {
                    // The image may be valid even when its metadata cannot be read.
                    result.success(emptyMap<String, Any?>())
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "my_photo_frame/maps")
            .setMethodCallHandler { call, result ->
                if (call.method != "openLocation") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val latitude = call.argument<Double>("latitude")
                val longitude = call.argument<Double>("longitude")
                if (latitude == null || longitude == null ||
                    !latitude.isFinite() || !longitude.isFinite() ||
                    latitude !in -90.0..90.0 || longitude !in -180.0..180.0) {
                    result.error("invalid_location", "Invalid location coordinates", null)
                    return@setMethodCallHandler
                }
                val uri = Uri.parse("geo:0,0?q=$latitude,$longitude")
                val mapIntent = Intent(Intent.ACTION_VIEW, uri)
                try {
                    startActivity(Intent.createChooser(mapIntent, "Open location with"))
                    result.success(null)
                } catch (_: ActivityNotFoundException) {
                    result.error("no_map_app", "No map app can open this location", null)
                }
            }
    }
}
