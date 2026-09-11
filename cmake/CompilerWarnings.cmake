# 统一编译告警策略。见总体设计文档 20.5。
function(keycerthub_apply_warnings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /permissive-)
    else()
        target_compile_options(${target} PRIVATE
            -Wall -Wextra -Wpedantic -Wshadow
            -Wconversion -Wsign-conversion
            -Wnon-virtual-dtor -Wold-style-cast
            -Wcast-align -Wunused -Woverloaded-virtual
            -Wnull-dereference -Wdouble-promotion
            -Wformat=2 -Wimplicit-fallthrough)
    endif()
endfunction()
