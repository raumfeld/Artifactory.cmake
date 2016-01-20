# Copyright 2016 Raumfeld
#
# Distributed under the OSI-approved BSD License (the "License");
# see accompanying file LICENSE for details.
#
# This software is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the License for more information.

# This is an example project for the Artifactory.cmake CMake module.
#
# It demonstrates how to cache and reuse builds of ZLib, a popular compression
# library. The build of ZLib is driven by the CMake ExternalProject module,
# which is maintained as part of the CMake project itself.
#
# To run it:
#
#   mkdir build
#   cmake .. -DARTIFACTORY_FETCH=ON -DARTIFACTORY_SUBMIT=ON
#
# Build zlib from source:
#
#   make
#
# Submit the prebuilt artifact to your Artifactory server. (You must have
# configured the artifactory-cli-go with the correct location and credentials
# first, using the `art config` command.).
#
#   make artifactory-submit
#
# If you now try a second build in a different directory, you should see that
# it picks up the prebuilt artifact from the first build.

cmake_minimum_required(VERSION 3.2)

# Set up the module path so Artifactory.cmake is found.
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../)

include(Artifactory)

set(ZLIB_GIT_REPOSITORY git://git.baserock.org/delta/zlib)
set(ZLIB_GIT_VERSION master)

set_property(GLOBAL PROPERTY ZLIB_GIT_REPOSITORY ${ZLIB_GIT_REPOSITORY})
set_property(GLOBAL PROPERTY ZLIB_GIT_VERSION ${ZLIB_GIT_VERSION})

artifactory_add_artifact(
    # Local directory containing the artifact
    com.example/zlib

    # Name of the target created by com.example/zlib/CMakeLists.txt
    LOCAL_TARGET zlib

    # Coordinates for the remote artifact. The remote directory will be:
    #
    #   com.example.repo/com/example/zlib/${VERSION}/
    #
    # The remote filename will be:
    #
    #   zlib-${VERSION}.tar.gz
    #
    REPO com.example.repo
    GROUP com.example
    NAME zlib

    # This is the version number used when uploading the prebuilt artifact.
    # Artifactory will automatically replace -SNAPSHOT with a timestamp and
    # build number. You can do that yourself if you prefer, replacing SNAPSHOT
    # here with something following the pattern of date.time-buildnumber
    # (for example: 20160101.125100-1 for build #1 on the 1st of January 2016,
    # at 12:51).
    UPLOAD_VERSION ${ZLIB_GIT_VERSION}-SNAPSHOT

    # This is the version number to be used when looking for prebuilt
    # artifacts. Artifactory.cmake will replace -SNAPSHOT with -* for the
    # filenames, since they will have timestamps in their names.
    VERSION ${ZLIB_GIT_VERSION}-SNAPSHOT
    )

add_custom_target(
    all-external ALL DEPENDS zlib)
