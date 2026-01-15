#/bin/bash

DEBUG_BUILD_DIR="build/debug"
RELEASE_BUILD_DIR="build/release"
ASSETS_SRC_DIR="resources/assets"

C3_OPTS=""
IS_RELEASE=0;
IS_VERBOSE=0; 
BUILD_TESTS=0;
COPY_ASSETS=0;
VSYNC=0;
CMAKE_OPTS=""
CMAKE_BUILD_OPTS=""
# TODO: vulkan driver should be configurable
LIBRARIES="-l glfw3 -l vulkan_radeon -l volk "
PLATFORM_WAYLAND="PLATFORM_WAYLAND"
PLATFORM_X11="PLATFORM_X11"
PLATFORM_WIN32="PLATFORM_WIN32"
NOT_SUPPORTED_MSG="This os is not supported for now, sorry:("

# check OS
case "$OSTYPE" in
    msys*)
      echo "Detected OS: Windows (MSYS/Git Bash)"
      C3_OPTS+="-D $PLATFORM_WIN32 "
    ;;
    cygwin*)
      echo "Detected OS: Windows (Cygwin)"
      C3_OPTS+="-D $PLATFORM_WIN32 "
    ;;
    linux*)
      echo "Detected OS: Linux"
      if [ "$XDG_SESSION_TYPE" == "wayland" ]; then
          echo "session: Wayland"
          C3_OPTS+="-D $PLATFORM_WAYLAND "
          LIBRARIES+="-l wayland-client "
        elif [ "$XDG_SESSION_TYPE" == "x11" ]; then
          echo "session: X11."
          C3_OPTS+="-D $PLATFORM_X11 "
          LIBRARIES+="-l xcb -l xcb-xkb -l X11 -l X11-xcb "
      else
          echo "Current session is Windows."
      fi
    ;;
    darwin*)
      echo "Detected OS: macOS"
      echo $NOT_SUPPORTED_MSG
      exit
    ;;
    *)
      echo "Detected OS: $OSTYPE"
      echo $NOT_SUPPORTED_MSG
      exit
    ;;
esac

C3_OPTS+="$LIBRARIES "

for arg in "$@"; do
  case "$arg" in
  -r | --release)
    IS_RELEASE=1
    ;;
  -small | --small)
    C3_OPTS+="--optsize=tiny "
    ;;
  -san | --sanitize)
    echo "Building with sanitizer"
    C3_OPTS+="--sanitize=address "
    ;;
  -strict | --strict)
    C3_OPTS+="--validation=obnoxious "
    ;;
  -c | --cleanup)
    echo "Rebuilding"
    CMAKE_BUILD_OPTS+="--clean-first "
    ;;
  -v | --verb)
    C3_OPTS+="-v --build-env "
    IS_VERBOSE=1
    ;;
  --vsync)
    echo "Vsync enabled"
    C3_OPTS+="-D VSYNC"
    ;;
  --test | -t)
    echo "Building tests..."
    BUILD_TESTS=1
    ;;
  -as | --assets)
    echo "Copying assets"
    COPY_ASSETS=1
    ;;
  *)
    echo "Unknown argument: $arg"
    ;;
  esac
done

# Debug
if [ $IS_RELEASE -eq 0 ]; then
  echo "Building in DEBUG mode"
  C3_OPTS+="-O0 -g --output-dir $DEBUG_BUILD_DIR -L $DEBUG_BUILD_DIR -L $DEBUG_BUILD_DIR/glfw/src -L $DEBUG_BUILD_DIR/volk -D SF_DEBUG "
  if [ $IS_VERBOSE -eq 1 ]; then
    echo "c3 options are: $C3_OPTS"
  fi

  CMAKE_OPTS+=" -DCMAKE_BUILD_TYPE=Debug "
  [ -d "$DEBUG_BUILD_DIR" ] || mkdir "$DEBUG_BUILD_DIR"
  # assets
  if [ $COPY_ASSETS -eq 1 ]; then
    [ -d "$DEBUG_BUILD_DIR/assets" ] || mkdir -p "$DEBUG_BUILD_DIR/assets"
    cp -r "$ASSETS_SRC_DIR" "$DEBUG_BUILD_DIR/assets"
  fi
  cd "$DEBUG_BUILD_DIR"
  cmake $CMAKE_OPTS ../../ && cmake --build . $CMAKE_BUILD_OPTS
  cd ../../
  c3c build $C3_OPTS

# Release
else
  echo "Building in RELEASE mode"
  C3_OPTS+="-O5 -optlevel=max -g0 --output-dir $RELEASE_BUILD_DIR -L $RELEASE_BUILD_DIR -L $RELEASE_BUILD_DIR/glfw/src -L $RELEASE_BUILD_DIR/volk -D SF_RELEASE "
  if [ $IS_VERBOSE -eq 1 ]; then
    echo "c3 options are: $C3_OPTS"
  fi

  CMAKE_OPTS+=" -DCMAKE_BUILD_TYPE=Release"
  [ -d "$RELEASE_BUILD_DIR" ] || mkdir "$RELEASE_BUILD_DIR"
  # assets
  if [ $COPY_ASSETS -eq 1 ]; then
    [ -d "$RELEASE_BUILD_DIR/assets" ] || mkdir -p "$RELEASE_BUILD_DIR/assets"
    cp -r "$ASSETS_SRC_DIR" "$RELEASE_BUILD_DIR/assets"
  fi
  cd "$RELEASE_BUILD_DIR"
  cmake $CMAKE_OPTS ../../ && cmake --build . $CMAKE_BUILD_OPTS
  cd ../../
  c3c build $C3_OPTS
fi
