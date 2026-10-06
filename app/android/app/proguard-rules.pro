# ---- Flutter ----
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ---- Our security inspector (reads BuildConfig / stack traces) ----
-keep class com.dukandar.dukandar.** { *; }
-keepattributes SourceFile,LineNumberTable

# ---- flutter_local_notifications (Gson reflection) ----
-keep class com.dexterous.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ---- Google Sign-In / Play Services / Credentials ----
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.android.libraries.identity.** { *; }
-dontwarn com.google.android.libraries.identity.**
-keep class androidx.credentials.** { *; }
-dontwarn androidx.credentials.**
-keep class com.google.api.** { *; }
-dontwarn com.google.api.**

# ---- flutter_secure_storage / AndroidX security ----
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# ---- sqflite ----
-keep class com.tekartik.sqflite.** { *; }

# ---- Kotlin ----
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }
-keep class kotlin.Metadata { *; }

# ---- Play Core (deferred components stubs referenced by Flutter) ----
-dontwarn com.google.android.play.core.**

# ML Kit face detection (release builds are minified; keep its classes intact)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.odml.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.odml.**
# camera plugin
-keep class io.flutter.plugins.camerax.** { *; }
