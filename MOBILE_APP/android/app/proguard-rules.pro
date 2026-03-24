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
