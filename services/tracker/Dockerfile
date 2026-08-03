FROM ubuntu:24.04 AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential cmake ninja-build libprotobuf-dev protobuf-compiler && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY CMakeLists.txt ./
COPY protocol ./protocol
COPY services/tracker ./services/tracker
RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build
FROM ubuntu:24.04
COPY --from=build /src/build/services/tracker/moca-tracker /usr/local/bin/moca-tracker
ENTRYPOINT ["moca-tracker"]
