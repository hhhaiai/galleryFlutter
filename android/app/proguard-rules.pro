# LiteRT-LM / MediaPipe optional proto classes referenced by runtime profiling/template APIs.
# They are not needed by the app path, but R8 treats them as missing in release minification.
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
