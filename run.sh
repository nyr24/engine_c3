RELEASE=0
SAFE=0

for arg in "$@"; do
  case "$arg" in
  -r | -release)
    RELEASE=1
    ;;
  -s | -safe)
    SAFE=1
    ;;
  esac
done


if [ $RELEASE == 0 ]; then
  ./build/debug/debug
elif [ $SAFE == 1 ]; then
  ./build/release/release_safe
else
  ./build/release/release_fast
fi
