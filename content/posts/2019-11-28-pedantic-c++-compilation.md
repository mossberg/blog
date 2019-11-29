+++
title = "Being pedantic about C++ compilation"
date = 2019-11-28T11:18:14-05:00
tags = [
"linux",
"cmake",
"C++",
"Build",
]
categories = [""]
draft = false
+++

> **Takeaways**:

> - Don't assume it's safe to use pre-built dependencies when compiling C++ programs. You might want to build from source,
> especially if you can't determine how a pre-built object was compiled, or if you want to use a different C++ standard
> than was used to compile it.

> - Ubuntu has public build logs which you can help you determine if you can use a pre-built object, or if you should compile from source.

> - `pkg-config` is useful for generating the flags needed to compile a complex third-party dependency.
> CMake's `PkgConfig` module can make it easy to integrate a dep into your build system.

> - Use CMake `IMPORTED` targets (e.g. `BZip2::Bzip2`) versus legacy variables (e.g. `BZIP2_INCLUDE_DIRS` and `BZIP2_LIBRARIES`).

----

## Introduction

Let's set up a simple C++ program that links to libxml++ on Ubuntu 18.04.

First, we'll install libxml++ from apt.

```txt
sudo apt install libxml++2.6-dev
```

This installs a pre-built libxml++ shared object, and also header files that
we'll need for development.

Sidenote: If you simply want to install libxml++
as a dependency for another app, and aren't planning on doing any dev work,
you can simply download the `libxml++2.6-2v5` package, which only contains
the shared objects, and no headers.

We can check what's inside an apt package using `dpkg -L`.

```txt
[I] vagrant ubuntu-bionic /v/l/c/x/l/b ❯ dpkg -L libxml++2.6-dev | head -n10
/.
/usr
/usr/include
/usr/include/libxml++-2.6
/usr/include/libxml++-2.6/libxml++
/usr/include/libxml++-2.6/libxml++/attribute.h
/usr/include/libxml++-2.6/libxml++/attributedeclaration.h
/usr/include/libxml++-2.6/libxml++/attributenode.h
/usr/include/libxml++-2.6/libxml++/document.h
/usr/include/libxml++-2.6/libxml++/dtd.h
[I] vagrant ubuntu-bionic /v/l/c/x/l/b ❯ dpkg -L libxml++2.6-dev | grep .so
/usr/lib/x86_64-linux-gnu/libxml++-2.6.so
[I] vagrant ubuntu-bionic /v/l/c/x/l/b ❯ dpkg -L libxml++2.6-2v5
/.
/usr
/usr/lib
/usr/lib/x86_64-linux-gnu
/usr/lib/x86_64-linux-gnu/libxml++-2.6.so.2.0.7
/usr/share
/usr/share/doc
/usr/share/doc/libxml++2.6-2v5
/usr/share/doc/libxml++2.6-2v5/changelog.Debian.gz
/usr/share/doc/libxml++2.6-2v5/copyright
/usr/lib/x86_64-linux-gnu/libxml++-2.6.so.2
[I] vagrant ubuntu-bionic /v/l/c/x/l/b ❯
```

## ABI Incompatibility

**In general, we should exercise a bit of caution when dealing with pre-built
objects.**

Due to ABI incompatibility, it's technically good practice to
ensure that all objects used in a compilation process were compiled with the
same[^1]:

- C++ language standard
- Compiler (major) version
- Compiler flags (including ABI version [`-fabi-version`])

Otherwise, we could (at best) have link errors, or even runtime errors and
*memory corruption* 😋.

So if we really wanted to be confident that we are avoiding these issues,
 we could check how this `libxml++2.6.so.2`
was compiled and ensure we compile our app in the same way.
To do this, we can look at the build logs.

I googled "ubuntu libxml++ apt" and found this: https://launchpad.net/ubuntu/+source/libxml%2B%2B2.6.
Digging around a bit more, I was able to find the build log for the amd64 build
for 18.04: https://launchpadlibrarian.net/349579832/buildlog_ubuntu-bionic-amd64.libxml++2.6_2.40.1-2_BUILDING.txt.gz.
It's pretty cool that this info is public, and we can see exactly how our packages
were built!

Searching through that page for "g++" I find these lines:

```txt
Preparing to unpack .../10-g++-7_7.2.0-18ubuntu2_amd64.deb ...
Unpacking g++-7 (7.2.0-18ubuntu2) over (7.2.0-6ubuntu1) ...
```

So it looks like they're compiling with g++ 7.2.0. What version is installed on
my system?

```txt
[I] vagrant ubuntu-bionic /v/l/c/x/l/b ❯ g++ --version
g++ (Ubuntu 7.4.0-1ubuntu1~18.04.1) 7.4.0
```

They're not the same version, but since they're only a few minor versions away,
it should still be fine. Honestly, even if they were even a major version away,
gcc is known for prioritizing ABI stability, so it probably wouldn't be a problem
anyway[^2].
In general, most platforms unofficially guarantee ABI stability, so this is not
really a big concern. In the past, however, Windows intentionally broke
ABI in every major release of Visual Studio[^3], so it's good to be aware of this stuff.
With modern Visual Studio, they also seem to be trending more towards stability.

> We heard it loud and clear that a major reason contributing to MSVC v141’s fast adoption today is its binary compatibility with MSVC v140. This allowed you to migrate your own code to the v141 toolset at your own pace, without having to wait for any of your 3rd party library dependencies to migrate first.
> We want to keep the momentum going and make sure that you have a similarly successful adoption experience with MSVC v142 too. This is why we’re announcing today that our team is committed to provide binary compatibility for MSVC v142 with both MSVC v141 and v140.
[^4]

I didn't see `-std=` anywhere in that output, so we'll assume the code is compiled
with the default c++ standard for g++ 7.2.0. Find exactly what standard it is,
we can look at the gcc documentation for that version. Version 7.2.0 isn't available
on the [gcc website](https://gcc.gnu.org/onlinedocs/), but the URLs are consistent, so we can
guess the URL for 7.2.0: https://gcc.gnu.org/onlinedocs/gcc-7.2.0/gcc/Standards.html#C_002b_002b-Language.

> The default, if no C++ language dialect options are given, is -std=gnu++14.

Therefore, when I build my app, to ensure compatibility, we should
make sure to use exactly this standard flag.

In case I happened to have that version of gcc installed locally, it seems
that this is the *easiest* way to find the default c++ version[^default_version] 😔:

```
[I] vagrant ubuntu-bionic /v/l/c/compileplay ❯ g++ -dM -E -xc++ /dev/null | grep __cplusplus
#define __cplusplus 201402L
```

## When do I need to build from source?

What if there wasn't a build log available?
Then we have no way of knowing how that object was built, and furthermore,
no way of knowing if we are building our client app in an ABI compatible way. 
We should build libxml++ from source, or "risk" incompatibility issues.

What if we want to use c++ 17 instead of 14 (with GNU extensions) for our app? 
What if we want to use standard c++ 14 instead of GNU c++ 14?
We have no choice here; we should compile libxml++ from source with whatever
standard we want to use in our app. (Although in this case, we can't because
`std::auto_ptr` was removed in c++ 17, and libxml++-2.6 uses it. libxml++-3.0
fixes this, but it this wasn't available, we'd need to find another xml library
or port it ourselves).

## Building our app

Anyway, now that we've roughly checked that it's ok to use this binary with our
system toolchain, and determined what `-std=` flag we should use,
let's continue.

My goal is to get this program to compile, which tests whether we can include
the libxml++ headers, and instantiate a class.

```c++
#include <libxml++/libxml++.h>

int main() {
    xmlpp::DomParser parser;
}
```

libxml++ includes a `pkg-config` `.pc` file which is really helpful. `pkg-config`
is a program that prints out the compiler/linker flags needed to compilation.

```txt
[I] vagrant ubuntu-bionic /v/l/c/x/l/b ❯ dpkg -L libxml++2.6-dev | grep .pc
/usr/lib/x86_64-linux-gnu/pkgconfig/libxml++-2.6.pc
[I] vagrant ubuntu-bionic /v/l/c/x/l/b ❯ pkg-config --cflags --libs libxml++-2.6
-I/usr/include/libxml++-2.6 -I/usr/lib/x86_64-linux-gnu/libxml++-2.6/include -I/usr/include/libxml2 -I/usr/include/glibmm-2.4 -I/usr/lib/x86_64-linux-gnu/glibmm-2.4/include -I/usr/include/glib-2.0 -I/usr/lib/x86_64-linux-gnu/glib-2.0/include -I/usr/include/sigc++-2.0 -I/usr/lib/x86_64-linux-gnu/sigc++-2.0/include -lxml++-2.6 -lxml2 -lglibmm-2.4 -lgobject-2.0 -lglib-2.0 -lsigc-2.0
```

libxml++ is apparently pretty complex to build because of *its* dependencies:
libxml2, glibmm, and sigc++. Each of these has their own include directories
that need to be passed to the compiler, and also their own `-l` linker flags.

Using pkg-config, we can easily run a manual gcc command to compile our app.

```txt
[I] vagrant ubuntu-bionic /v/l/c/x/libxml++play ❯ eval g++ main.cc -std=gnu++14 (pkg-config --cflags --libs libxml++-2.6)
In file included from /usr/include/libxml++-2.6/libxml++/libxml++.h:53:0,
                 from main.cc:1:
/usr/include/libxml++-2.6/libxml++/parsers/saxparser.h:224:8: warning: ‘template<class> class std::auto_ptr’ is deprecated [-Wdeprecated-declarations]
   std::auto_ptr<_xmlSAXHandler> sax_handler_;
        ^~~~~~~~
In file included from /usr/include/c++/7/memory:80:0,
                 from /usr/include/libxml++-2.6/libxml++/parsers/saxparser.h:14,
                 from /usr/include/libxml++-2.6/libxml++/libxml++.h:53,
                 from main.cc:1:
/usr/include/c++/7/bits/unique_ptr.h:51:28: note: declared here
   template<typename> class auto_ptr;
                            ^~~~~~~~
In file included from /usr/include/libxml++-2.6/libxml++/libxml++.h:54:0,
                 from main.cc:1:
/usr/include/libxml++-2.6/libxml++/parsers/textreader.h:260:10: warning: ‘template<class> class std::auto_ptr’ is deprecated [-Wdeprecated-declarations]
     std::auto_ptr<PropertyReader> propertyreader;
          ^~~~~~~~
In file included from /usr/include/c++/7/memory:80:0,
                 from /usr/include/libxml++-2.6/libxml++/parsers/saxparser.h:14,
                 from /usr/include/libxml++-2.6/libxml++/libxml++.h:53,
                 from main.cc:1:
...
```

I needed to use `eval` because I use fish shell, which apparently has some issues
with command substitution used this way[^5].

There's a TON of warnings about `std::auto_ptr` (which is deprecated, and removed in C++17[^6]🤮), but no errors, so yay,
it worked! Also, all those warnings appear in ubuntu's official build output too!
That's pretty cool to see.

## Building our app with CMake

Using this, we could start to write a Makefile, and create a build
system for our app.
I'd like to use CMake though; it's a bit more modern and lets you avoid
rolling your own build system from scratch via make.

A basic `CMakeLists.txt` looks like this.

```cmake
cmake_minimum_required(VERSION 3.6)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)  # it might "decay" to a previous std otherwise
set(CMAKE_CXX_EXTENSIONS ON)  # it's on by default anyway

project(main)
add_executable(main main.cc)
```

The three `set` lines will produce the `-std=gnu++14` flag that we want.
`CMAKE_CXX_STANDARD_REQUIRED` will trigger an error if, for some reason,
c++ 14 support is not available in our compiler. Otherwise, CMake might silently
"decay" to a previous standard[^decay]. `CMAKE_CXX_EXTENSIONS` is what requests
using `-std=gnu++14` vs `-std=c++14`[^gnu]. This is actually enabled by default!
So keep in mind that if you want your project to strictly use standard c++,
with no extensions, you should disable this variable.

Now that we've taken care of setting the proper standard, we need to
tell CMake about our libxml++ dependency, otherwise, we
get an error about includes. When you want to add a system dependency (typically
residing in `/usr`, not in your source tree), you typically use a CMake "find module".
These are little CMake programs that ship with CMake designed to build targets
for specific pieces of software.

```txt
[I] vagrant ubuntu-bionic /v/l/c/x/libxml++play ❯ cmake --help-module-list|head -n10
AddFileDependencies
AndroidTestUtilities
BundleUtilities
CMakeAddFortranSubdirectory
CMakeBackwardCompatibilityCXX
CMakeDependentOption
CMakeDetermineVSServicePack
CMakeExpandImportedTargets
CMakeFindDependencyMacro
CMakeFindFrameworks
```

If CMake includes a find module for the dependency you're linking to, that's great news.
You can just do something like:

```cmake
find_package(BZip2 REQUIRED)
```

which will automatically find the locations of the bzip2 headers and shared objects
and prepare a CMake `IMPORTED` target for you to link against in a `target_link_libraries` call.

```cmake
# the modern way; prefer this
# `BZip2::BZip2` is an IMPORTED target
target_link_libraries(main BZip2::BZip2)
```

That find module will also go the legacy route of defining certain CMake variables
that you manually include in your own `target_include_directories` and `target_link_libraries` calls.

```cmake
# legacy way; avoid this
target_include_directories(main ${BZIP2_INCLUDE_DIRS})
target_link_libraries(main ${BZIP2_LIBRARIES})
```

The documentation for the various included modules is available with the CMake
documentation: http://cmake.org/cmake/help/v3.15/module/FindBZip2.html

Unfortunately, CMake does not include a module for libxml++.
This means that we need to find some random one online somewhere, or write our
own. Searching for "cmake findlibxml++" yields a couple results:

- https://github.com/Washington-University/CiftiLib/blob/master/cmake/Modules/Findlibxml%2B%2B.cmake
- https://github.com/nitram2342/degate/blob/master/cmake/Modules/FindLibXML%2B%2B.cmake
- https://models.slf.ch/p/meteoio/source/tree/HEAD/trunk/tools/cmake/FindLibXML%2B%2B.cmake
- https://sahara.irt-saintexupery.com/MOISE/Timed-Altarica-To-Fiacre-Translator/blob/master/config/FindLibXML++.cmake

To use these, you need to copy them somewhere in your source tree, and then
write a bit of CMake to allow CMake to find it. There is some documentation on
this here: https://gitlab.kitware.com/cmake/community/wikis/doc/tutorials/How-To-Find-Libraries. All of these links I found seem to do things the legacy way,
and have a ton of cmake code.

Since libxml++ includes a `pkg-config` file, writing our own cmake to link
against it is actually not too hard. CMake's `pkg-config` module
includes the `pkg_check_modules` helper function which will automatically
create an `IMPORTED` target if you use the `IMPORTED_TARGET` argument.
Then you can easily use that target in a `target_link_libraries` call.

It seems like this is not that widely known? All of the above links use the
legacy way with CMake `*_INCLUDE_DIRS` and `*_LIBRARIES` variables.

```cmake
cmake_minimum_required(VERSION 3.6)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)  # it might "decay" to a previous std otherwise
set(CMAKE_CXX_EXTENSIONS ON)  # it's on by default anyway

project(main)

function(main)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(
        LIBXML++
        REQUIRED IMPORTED_TARGET
        libxml++-2.6
    )

    add_executable(main main.cc)
    target_link_libraries(main PkgConfig::LIBXML++)

endfunction()

main()
```

```txt
[I] vagrant ubuntu-bionic /v/l/c/x/l/build ❯ cmake ..                       ❮ 11/
-- The C compiler identification is GNU 7.4.0
-- The CXX compiler identification is GNU 7.4.0
-- Check for working C compiler: /usr/bin/cc
-- Check for working C compiler: /usr/bin/cc -- works
-- Detecting C compiler ABI info
-- Detecting C compiler ABI info - done
-- Detecting C compile features
-- Detecting C compile features - done
-- Check for working CXX compiler: /usr/bin/c++
-- Check for working CXX compiler: /usr/bin/c++ -- works
-- Detecting CXX compiler ABI info
-- Detecting CXX compiler ABI info - done
-- Detecting CXX compile features
-- Detecting CXX compile features - done
-- Found PkgConfig: /usr/bin/pkg-config (found version "0.29.1")
-- Checking for module 'libxml++-2.6'
--   Found libxml++-2.6, version 2.40.1
-- Configuring done
-- Generating done
-- Build files have been written to: /vagrant/lang/cpp/xmlplay/libxml++play/build
[I] vagrant ubuntu-bionic /v/l/c/x/l/build ❯ make
Scanning dependencies of target main
[ 50%] Building CXX object CMakeFiles/main.dir/main.cc.o
[100%] Linking CXX executable main
[100%] Built target main
```

## Conclusion

This works pretty well! Our program builds and links successfully, and we can
actually start development. We can be especially confident that we've avoided
subtle ABI incompatibility issues (that might only manifest at runtime!)
because we took the time to ensure that our app builds in the same way as
the pre-built library.  Plus, our CMake to handle libxml++
is a lot simpler than what was in those random links we found.

[^1]: For more info, see this talk: https://youtu.be/ncyQAjTyPwU?list=WL&t=571
[^2]: https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html.
[^3]: https://www.reddit.com/r/cpp/comments/13zex3/can_vs2010_c_libsdlls_be_linked_into_a_vs2012_c/c78ott7/
[^4]: https://devblogs.microsoft.com/cppblog/cpp-binary-compatibility-and-pain-free-upgrades-to-visual-studio-2019/
[^5]: https://github.com/fish-shell/fish-shell/issues/982
[^6]: https://en.cppreference.com/w/cpp/memory
[^default_version]: https://stackoverflow.com/a/44735016
[^decay]: http://cmake.org/cmake/help/v3.16/prop_tgt/CXX_STANDARD_REQUIRED.html
[^gnu]: http://cmake.org/cmake/help/v3.16/prop_tgt/CXX_EXTENSIONS.html
