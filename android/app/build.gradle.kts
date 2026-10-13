import groovy.json.JsonSlurper
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val communityDefines = (project.findProperty("dart-defines") as String?)
    ?.split(",")?.filter { it.isNotEmpty() }?.associate {
        val decoded = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
        val separator = decoded.indexOf('=')
        require(separator > 0) { "Invalid dart define" }
        decoded.substring(0, separator) to decoded.substring(separator + 1)
    } ?: emptyMap()
val firebaseOptions = communityDefines["FIREBASE_OPTIONS"]?.takeIf { it.isNotBlank() }
val googleServices = file("google-services.json")
// Never apply a production registration accidentally in an unconfigured build.
if (googleServices.exists() && firebaseOptions != null) {
    val nativeConfig = JsonSlurper().parse(googleServices) as Map<*, *>
    val dartConfig = JsonSlurper().parseText(firebaseOptions) as Map<*, *>
    val androidConfig = dartConfig["android"] as? Map<*, *>
    val projectInfo = nativeConfig["project_info"] as? Map<*, *>
    val androidProjectId = androidConfig?.get("projectId")
    require(androidProjectId != null &&
        projectInfo?.get("project_id") == androidProjectId) {
        "Google Services and FIREBASE_OPTIONS must use the same project"
    }
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.example.trabajo_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Debe coincidir con el cliente registrado en google-services.json.
        applicationId = "com.example.trabajo_app"
        manifestPlaceholders["appDisplayName"] = communityDefines["APP_NAME"] ?: "MiComunidad"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "edition"
    productFlavors {
        create("demo") {
            dimension = "edition"
            applicationIdSuffix = ".demo"
        }
        create("private") {
            dimension = "edition"
        }
    }

    buildTypes {
        release {
            // Firma local de prueba. Para publicar, usar un keystore privado.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
