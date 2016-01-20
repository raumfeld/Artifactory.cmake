# Copyright 2016 Raumfeld
#
# Distributed under the OSI-approved BSD License (the "License");
# see accompanying file LICENSE for details.
#
# This software is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the License for more information.

# ::
#
#    ensure_all_arguments_parsed(<command> "<unparsed_arguments>")
#
# Helper for the CMakeParseArguments module, to check if there were any
# unparsed arguments after cmake_parse_arguments() has been called.
#
# Raises a fatal error if <unparsed_arguments> is not an empty string.
#
# For use like this:
#
#   function(my_function)
#       set(options FIE FOE FUM)
#       cmake_parse_arguments(FOO "${options}" "" "" ${ARGN})
#       ensure_all_arguments_parsed(my_function "${FOO_UNPARSED_ARGUMENTS}")
#       ...
#   endfunction()
#
# This will raise an error if my_function() is called with any arguments other
# than FIE, FOE or FUM.
#
# You must always quote the second argument, otherwise, if it is an empty
# string then you will get a "Function invoked with incorrect arguments" error.
function(ensure_all_arguments_parsed command unparsed_arguments)
    if(unparsed_arguments)
        message(FATAL_ERROR "Unparsed arguments to ${command}(): ${unparsed_arguments}")
    endif()
endfunction()
