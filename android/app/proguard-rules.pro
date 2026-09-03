# Keep the Kotlin metadata for reflection-based plugins.
-keep class kotlin.Metadata { *; }

# Firebase / Play services classes reference reflection.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }

# AppsFlyer SDK.
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# WebView JS <-> Dart interop.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Retain source-file names so crash traces stay readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Suppress a few well-known missing symbols.
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
