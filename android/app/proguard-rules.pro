# kotlinx.serialization: keep generated serializers (R8 ≈ link-time dead stripping, but reflective lookups need rules).
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keep,includedescriptorclasses class app.invoicebuilder.**$$serializer { *; }
-keepclassmembers class app.invoicebuilder.** { *** Companion; }
-keepclasseswithmembers class app.invoicebuilder.** { kotlinx.serialization.KSerializer serializer(...); }
# Room entities and DAOs are generated code; Room ships its own rules.
