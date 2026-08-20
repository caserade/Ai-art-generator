# Keep Flutter / Flame / plugin classes for native release builds.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.gamemaker.mobile_game_maker.** { *; }

# Flame / gamepads / image plugins
-dontwarn com.google.android.play.core.**
-keep class com.llfbandit.** { *; }

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-dontwarn javax.annotation.**
-dontwarn org.bouncycastle.**
