# Keep ML Kit barcode scanning + mobile_scanner classes. These are partly loaded
# via reflection / manifest component registrars, so R8 must not remove or rename
# them. Without these, release builds throw a NullPointerException inside ML Kit
# when the camera starts and the scanner shows "Camera unavailable".
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
