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
#    require_arguments(<command> <prefix> <parameter> [<parameter> ...])
#
# This macro is for use with the CMakeParseArguments module. You can ensure
# that one or more arguments were passed in, by raising a fatal error if any
# of them are not defined after cmake_parse_arguments() is called.
#
# Example usage:
#
#     function(my_test)
#         set(one_value_keywords MAGIC_WORD)
#         cmake_parse_arguments(MY "" "${one_value_keywords}" "" ${ARGN})
#         require_arguments(my_test MY MAGIC_WORD)
#     endfunction()
#
# Now, if function my_test() is called without the MAGIC_WORD parameter, CMake
# will abort with a fatal error telling the user to supply that parameter.
#
macro(require_arguments function prefix)
    foreach(arg ${ARGN})
        if(NOT ${prefix}_${arg})
            message(FATAL_ERROR "${function}(): Required parameter ${arg} was not given.")
        endif()
    endforeach()
endmacro()

