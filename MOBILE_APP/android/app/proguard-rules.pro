# TFLite Flutter - keep native bindings
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.** { *; }

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Google Generative AI
-keep class com.google.ai.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Prevent stripping of Flutter plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter embeds Play Core deferred-component helpers even when the app does
# not use dynamic feature delivery. Suppress R8 warnings for those unused
# classes so release minification can complete.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
