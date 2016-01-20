# Artifactory.cmake

This is a [CMake] module that provides integration with the JFrog [Artifactory]
artifact cache server.

It allows you to implement binary artifact caching and reuse in your
CMake-generated build system. Your project and its build system need to be
organised in a specific way in order to use Artifactory.cmake effectively.

This module is inspired by [Maven], a build tool for Java projects. Maven
transparently supports caching and reuse of built artifacts, and we wanted
similar functionality for C/C++ projects built with CMake.

The JFrog [artifactory-cli-go] tool needs to be installed on any machine
that is running builds that use Artifactory.cmake.

## Disclaimer

This has so far only seen fairly limited use. It may well be broken, inadequate
or under-documented. Questions, patches and bug reports are welcome, but there
may not be much time available for ongoing maintenance. We have released it in
the hope that it's useful, but we don't promise that it will be!

## How it works

The general idea of Artifactory.cmake is that *each artifact is defined in its
own CMakeLists.txt file*. Since you can only have one CMakeLists.txt
per directory, this means that each artifact must be defined in its own
directory.

The [Maven] build tool works in the same way, and the layout of
Artifactory/Maven repositories is also based around the idea of a different
directory per artifact.

The main entry point of the module is the artifactory_add_artifact() function.
This should be called from the toplevel CMakeLists.txt and given the name of
the directory that contains the artifact to be built, and the coordinates for
the artifact within Artifactory.

At configure-time (when you run CMake), if the ARTIFACTORY_FETCH flag is set to
TRUE, artifactory_add_artifact() function will use [artifactory-cli-go] to
check for prebuilt versions of all the artifacts involved in the build, and
will download any that are found.

The artifactory_add_artifact() can filter by properties when looking for
prebuilt artifacts, which means you can ensure that the prebuilt artifact
corresponds to the exact same commit that the user is trying to build now.
Note that the free version of Artifactory ("Artifactory OSS") doesn't support
properties, that feature is only available in the paid-for ("Artifactory Pro")
version.

The add_subdirectory() call for each artifact is done by
artifactory_add_artifact(). The CMakeLists.txt in each subdirectory should
follow the following procedure when added:

- if a prebuilt version of the artifact exists in
  ${CMAKE_CURRENT_BINARY_DIR}/artifact-prebuilt, generate build commands
  to unpack the prebuilt artifact
- otherwise, generate build commands to build the artifact from source,
  and produce a suitable binary artifact (most likely a .tar.gz file)

If ARTIFACTORY_SUBMIT is set to to TRUE, the artifactory_add_artifact()
function generates an 'artifactory-upload-xxx' target for each artifact, and an
overall 'artifactory-submit' target that depends on all of them. This can be
run once the build is finished to submit any artifacts that were built to
Artifactory.

For more information, please refer to the [examples] and the function
documentation comments in [Artifactory.cmake] itself.

## Related projects

As far as we know this is the only public implementation of binary artifact
caching for CMake.

There are several CMake modules that deal with external *source* projects:

  - the CMake [ExternalProject](https://cmake.org/cmake/help/v3.4/module/ExternalProject.html) module
  - [CPM](https://github.com/iauns/cpm) (C++ Package Manager)
  - [Hunter](https://github.com/ruslo/hunter)

All of these projects could theoretically work with Artifactory.cmake, or
another binary artifact caching mechanism that works with CMake.

The [Buildroot.cmake] module can be used with Artifactory.cmake, which allows
you to cache and reuse the results of Buildroot builds (which often take along
time!).

The [Maven] build tool, which inspired this module, has a plugin available that
adds support for C and C++ code: the
[nar-maven-plugin](https://github.com/maven-nar/nar-maven-plugin).

[Artifactory]: https://www.jfrog.com/artifactory/
[Artifactory.cmake]: https://github.com/raumfeld/Artifactory.cmake/blob/master/Artifactory.cmake
[artifactory-cli-go]: https://github.com/JFrogDev/artifactory-cli-go
[Buildroot.cmake]: https://github.com/raumfeld/Buildroot.cmake/
[CMake]: https://www.cmake.org/
[examples]: https://github.com/raumfeld/Artifactory.cmake/tree/master/examples/
[Maven]: https://maven.apache.org/
