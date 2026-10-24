allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    // Suppress obsolete Java 8 warnings
    tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 1. Hook namespace and JVM targets BEFORE evaluation
subprojects {
    // Force Kotlin tasks to compile at 1.8
    project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions.jvmTarget = "1.8"
    }

    afterEvaluate {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                // Inject missing namespace
                val namespace = android.javaClass.getMethod("getNamespace").invoke(android)
                if (namespace == null) {
                    android.javaClass.getMethod("setNamespace", String::class.java).invoke(android, project.group.toString())
                }

                // Force Java compiler to match Kotlin's 1.8 target
                val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
                compileOptions.javaClass.getMethod("setSourceCompatibility", org.gradle.api.JavaVersion::class.java).invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_1_8)
                compileOptions.javaClass.getMethod("setTargetCompatibility", org.gradle.api.JavaVersion::class.java).invoke(compileOptions, org.gradle.api.JavaVersion.VERSION_1_8)
            } catch (e: Exception) {
                // Ignore if the extension doesn't support namespace/options mapping
            }
        }
    }
}

// 2. Force the evaluation dependency SECOND
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}