# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Play Core库保持规则
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}

# Keep webdav_client
-keep class com.thegrizzlylabs.sardineandroid.** { *; }

# Keep file_picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Keep path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Keep shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep geolocator
-keep class com.baseflow.geolocator.** { *; }

# Keep flutter_map
-keep class com.github.johnpryan.flutter_map.** { *; }

# Keep permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep http
-keep class io.flutter.plugins.http.** { *; }

# Keep xml
-keep class org.xmlpull.v1.** { *; }

# Keep latlong2
-keep class com.github.johnpryan.latlong2.** { *; } 