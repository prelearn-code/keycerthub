# 消毒器开关。见总体设计文档 20.5 与第二十四章。
function(keycerthub_apply_sanitizers target)
    if(KEYCERTHUB_ENABLE_ASAN AND KEYCERTHUB_ENABLE_TSAN)
        message(FATAL_ERROR "ASan 与 TSan 不能同时启用")
    endif()

    if(KEYCERTHUB_ENABLE_ASAN)
        target_compile_options(${target} PRIVATE -fsanitize=address -fno-omit-frame-pointer)
        target_link_options(${target}    PRIVATE -fsanitize=address)
    endif()

    if(KEYCERTHUB_ENABLE_UBSAN)
        target_compile_options(${target} PRIVATE -fsanitize=undefined -fno-omit-frame-pointer)
        target_link_options(${target}    PRIVATE -fsanitize=undefined)
    endif()

    if(KEYCERTHUB_ENABLE_TSAN)
        target_compile_options(${target} PRIVATE -fsanitize=thread -fno-omit-frame-pointer)
        target_link_options(${target}    PRIVATE -fsanitize=thread)
    endif()
endfunction()
