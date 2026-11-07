// Gradle 仓库统一在 settings 的 dependencyResolutionManagement 里声明。
//
// 不要在这里添加 allprojects { repositories { ... } }：
// Flutter 自带的 flutter_tools/gradle 以 FAIL_ON_PROJECT_REPOS 模式运行，
// 任何 project 级 repositories 块都会让构建报错：
//   "Build was configured to prefer settings repositories over project repositories
//    but repository 'maven' was added by settings file"
// 该文案有误导性，实际指的是 project 仓库。
//
// Flutter 引擎产物（io.flutter:*_release）来自 FLUTTER_STORAGE_BASE_URL，
// 不是 Maven 仓库，国内需设置为 https://storage.flutter-io.cn，见 scripts/build_android.ps1。

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
