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
}

// The upstream resolver writes downloads directly to its cache filename. A
// concurrent build can mistake a partial download for a usable shared library.
// Validate the copied ELF before any Android variant merges it into an APK.
subprojects {
    if (name == "nobodywho") {
        val validateNativeLibrary = tasks.register("validateNobodyWhoNativeLibrary") {
            dependsOn("resolveNativeLibraries")
            doLast {
                val libraries = fileTree(layout.buildDirectory.dir("jniLibs")) {
                    include("**/libnobodywho_flutter.so")
                }
                check(!libraries.isEmpty) { "NobodyWho native libraries were not resolved" }
                libraries.forEach { library ->
                    java.io.RandomAccessFile(library, "r").use { input ->
                        val header = ByteArray(64)
                        input.readFully(header)
                        val elf = java.nio.ByteBuffer.wrap(header)
                            .order(java.nio.ByteOrder.LITTLE_ENDIAN)
                        check(header.take(6) == listOf<Byte>(0x7f, 0x45, 0x4c, 0x46, 2, 1)) {
                            "Invalid ELF64 library: $library"
                        }
                        val sectionOffset = elf.getLong(40)
                        val sectionSize = elf.getShort(58).toInt() and 0xffff
                        val sectionCount = elf.getShort(60).toInt() and 0xffff
                        val tableSize = sectionSize.toLong() * sectionCount
                        check(sectionOffset >= 0 && sectionOffset <= input.length() &&
                            tableSize <= input.length() - sectionOffset) {
                            "Incomplete NobodyWho native library: $library (${input.length()} bytes). " +
                                "Wait for other builds/downloads to finish, delete build/nobodywho, " +
                                "then rebuild. Refusing to package a truncated library."
                        }
                    }
                }
            }
        }
        tasks.matching { it.name == "resolveNativeLibraries" }.configureEach {
            outputs.upToDateWhen { false }
        }
        tasks.matching { it.name.contains("merge") && it.name.contains("JniLibFolders") }
            .configureEach { dependsOn(validateNativeLibrary) }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
