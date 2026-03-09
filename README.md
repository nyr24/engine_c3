### Rendering engine written in C3 (wip)

### Download
`git clone --shallow-submodules git@github.com:nyr24/engine_c3.git .`
`git submodule update --remote --init src/dependencies/utils`
`git submodule update --remote --init src/dependencies/serializer`
`git submodule update --remote --init src/dependencies/soa`
`git submodule update --remote --init src/dependencies/arena_alloc`

### Build
`./build.sh [-r]`
  - `-r` - build in release mode

### Run
`./run.sh [-r]`
  - `-r` - run in release mode
