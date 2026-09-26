#pragma once
#include <catch2/catch_test_macros.hpp>

#if defined(CATCH_CONFIG_MAIN)
#include <catch2/catch_session.hpp>
int main(int argc, char* argv[]) {
    return Catch::Session().run(argc, argv);
}
#endif
