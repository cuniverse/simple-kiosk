cmake_minimum_required(VERSION 3.14)
project(ysignage_launcher LANGUAGES CXX)

add_executable(ysignage_launcher WIN32
  "launcher.cpp"
  "launcher.rc"
)

target_compile_features(ysignage_launcher PRIVATE cxx_std_17)
target_compile_options(ysignage_launcher PRIVATE /W4 /WX /utf-8 /EHsc)
target_compile_definitions(ysignage_launcher PRIVATE UNICODE _UNICODE NOMINMAX)
target_link_libraries(ysignage_launcher PRIVATE
  shell32.lib
  wintrust.lib
  crypt32.lib
)
