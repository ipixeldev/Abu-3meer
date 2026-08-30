allprojects {
    repositories {
        google()
        mavenCentral()
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
subprojects {
    project.evaluationDependsOn(":app")

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            freeCompilerArgs.add("-Xannotation-default-target=param-property")
        }
    }

    // Firebase Auth's Android SDK exposes Checker Framework type annotations
    // in listener signatures. Kotlin 2.4 needs those annotations on the plugin
    // compile classpath, even though they are not required at runtime.
    if (name == "firebase_auth") {
        pluginManager.withPlugin("com.android.library") {
            dependencies.add(
                "compileOnly",
                "org.checkerframework:checker-qual:3.49.5",
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
